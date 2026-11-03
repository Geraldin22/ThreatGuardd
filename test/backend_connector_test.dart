import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:threat_guard/models/sms_message.dart';
import 'package:threat_guard/services/backend_client.dart';
import 'package:threat_guard/services/backend_connector.dart';
import 'package:threat_guard/services/sms_source.dart';
import 'package:threat_guard/state/guard_state.dart';

final _key = 'k' * 43;
const _code = 'ABCD2345';

Map<String, Object?> _msg(int id, String sender, int risk, {String category = 'banking', DateTime? at}) => {
  'id': id,
  'sender': sender,
  'body': 'body $id',
  'receivedAt': (at ?? DateTime.now()).toUtc().toIso8601String(),
  'risk': risk,
  'category': category,
  'confidence': 90,
  'url': null,
};

/// A stand-in for the phone's inbox and the Android permission.
class FakeSms implements SmsSource {
  DeviceSmsAccess access = DeviceSmsAccess.granted;
  DeviceSmsAccess answerToRequest = DeviceSmsAccess.granted;
  List<InboxSms> inbox = [];
  Object? readError;
  String? linkedUrl, linkedToken;
  int requests = 0;
  bool settingsOpened = false;

  @override
  Future<DeviceSmsAccess> status() async => access;
  @override
  Future<DeviceSmsAccess> request() async {
    requests++;
    return access = answerToRequest;
  }

  @override
  Future<List<InboxSms>> readRecent(int limit) async {
    if (readError != null) throw readError!;
    return inbox.take(limit).toList();
  }

  @override
  Future<void> linkServer(String url, String token) async {
    linkedUrl = url;
    linkedToken = token;
  }

  @override
  Future<void> unlinkServer() async => linkedUrl = linkedToken = null;
  @override
  Future<void> openSettings() async => settingsOpened = true;
}

List<InboxSms> _inbox(int n) => [
  for (var i = 0; i < n; i++)
    InboxSms(
      sender: 'S$i',
      body: 'text $i',
      at: DateTime.utc(2026, 1, 1).add(Duration(minutes: i)),
    ),
];

/// A tiny stand-in for the real server.
class FakeServer {
  final importSizes = <int>[];
  final _seen = <String>{};
  bool up = true;
  bool keyRevoked = false;
  String revision = 'r1';
  Map<String, Object?> settings = {
    'monitoring': true,
    'autoBlock': true,
    'linkScanning': true,
    'alerts': true,
    'shareIntel': false,
    'sensitivity': 'balanced',
  };
  List<String> blocked = [];
  List<Map<String, Object?>> messages = [_msg(1, 'BANK', 95)];
  final requests = <String>[];
  Map<String, Object?>? lastSettingsBody;
  bool failBlock = false;

  Map<String, Object?> get _state => {
    'revision': revision,
    'unchanged': false,
    'settings': settings,
    'protectionScore': 98,
    'monitoring': settings['monitoring'],
    'blocked': blocked,
    'messages': messages,
    'engine': {'name': 'rules-test', 'version': '1'},
  };

  http.Response _json(Object body, [int status = 200]) => http.Response(
    jsonEncode(body),
    status,
    headers: {'content-type': 'application/json'},
  );

  Future<http.Response> handle(http.Request r) async {
    if (!up) throw http.ClientException('connection refused');
    final route = '${r.method} ${r.url.path}';
    requests.add(route);
    if (route == 'GET /api/health') {
      return _json({'ok': true, 'service': 'threatguard'});
    }
    if (route == 'POST /api/pair') {
      final code = (jsonDecode(r.body) as Map)['code'];
      return code == _code ? _json({'token': _key}) : _json({'error': 'wrong code'}, 403);
    }
    if (keyRevoked || r.headers['authorization'] != 'Bearer $_key') {
      return _json({'error': 'bad key'}, 401);
    }
    switch (route) {
      case 'GET /api/state':
        return r.url.queryParameters['rev'] == revision
            ? _json({'revision': revision, 'unchanged': true})
            : _json(_state);
      case 'POST /api/scan':
        return _json(_state);
      case 'PUT /api/settings':
        lastSettingsBody = Map<String, Object?>.from(jsonDecode(r.body) as Map);
        settings = {...settings, ...lastSettingsBody!};
        revision = 'r${requests.length}';
        return _json(_state);
      case 'POST /api/blocked':
        if (failBlock) return _json({'error': 'boom'}, 500);
        final b = jsonDecode(r.body) as Map;
        blocked = [
          if (b['blocked'] == true) b['sender'] as String,
        ];
        revision = 'r${requests.length}';
        return _json(_state);
      case 'POST /api/messages':
        final b = jsonDecode(r.body) as Map;
        final m = _msg(messages.length + 1, (b['sender'] as String).isEmpty ? 'Unknown' : b['sender'] as String, 88, category: 'delivery');
        messages = [m, ...messages];
        revision = 'r${requests.length}';
        return _json(m, 201);
      case 'POST /api/pair/new':
        return _json({'code': 'NEWCODE22'});
      case 'POST /api/messages/import':
        final rows = (jsonDecode(r.body) as Map)['messages'] as List;
        importSizes.add(rows.length);
        var added = 0;
        for (final row in rows.cast<Map>()) {
          final key = '${row['sender']}|${row['receivedAt']}|${row['body']}';
          if (!_seen.add(key)) continue;
          messages = [
            _msg(messages.length + 100, row['sender'] as String, 10, category: 'safe'),
            ...messages,
          ];
          added++;
        }
        if (added > 0) revision = 'r${requests.length}';
        return _json({'added': added, 'revision': revision});
    }
    if (r.method == 'DELETE' && r.url.path.startsWith('/api/messages/')) {
      final id = int.parse(r.url.pathSegments.last);
      messages = messages.where((m) => m['id'] != id).toList();
      revision = 'r${requests.length}';
      return _json(_state);
    }
    return _json({'error': 'not found'}, 404);
  }
}

void main() {
  late FakeServer server;
  late GuardState state;
  late MemoryConnectionStore store;
  late BackendConnector connector;
  late FakeSms sms;

  setUp(() {
    server = FakeServer();
    state = GuardState();
    store = MemoryConnectionStore();
    sms = FakeSms()..access = DeviceSmsAccess.unsupported;
    connector = BackendConnector(
      state,
      store: store,
      httpClient: MockClient(server.handle),
      sms: sms,
      pollEvery: const Duration(hours: 1), // polled by hand in tests
    );
  });
  tearDown(() {
    connector.dispose();
    state.dispose();
  });

  group('normalizeServerUrl', () {
    test('adds a sensible scheme', () {
      expect(normalizeServerUrl('192.168.1.10:8080').toString(), 'http://192.168.1.10:8080');
      expect(normalizeServerUrl('localhost:8080').toString(), 'http://localhost:8080');
      expect(normalizeServerUrl('guard.example.com').toString(), 'https://guard.example.com');
      expect(normalizeServerUrl('  http://10.0.0.2:9000/  ').toString(), 'http://10.0.0.2:9000');
    });
    test('drops paths and queries, rejects junk', () {
      expect(normalizeServerUrl('https://a.example.com/x/y?z=1').toString(), 'https://a.example.com');
      expect(normalizeServerUrl(''), isNull);
      expect(normalizeServerUrl('ftp://x.example.com'), isNull);
      expect(normalizeServerUrl('http://'), isNull);
    });
  });

  test('SmsMessage.fromJson tolerates an unknown category', () {
    final m = SmsMessage.fromJson(_msg(7, 'X', 70, category: 'from-the-future'));
    expect(m.category, ThreatCategory.impersonation);
    expect(m.id, 7);
    expect(m.risk, 70);
  });

  group('connecting', () {
    test('a pairing code links the device and loads everything', () async {
      expect(state.status, ProtectionStatus.permissionRequired);

      final error = await connector.connect('10.0.0.5:8080', _code);

      expect(error, isNull);
      expect(state.connected, isTrue);
      expect(state.smsPermission, SmsPermission.granted);
      expect(state.engineConnected, isTrue);
      expect(state.monitoringRunning, isTrue);
      expect(state.blockingAvailable, isTrue);
      expect(state.protectionScore, 98);
      expect(state.engineName, 'rules-test');
      expect(state.messages.length, 1);
      expect(state.backendUrl, 'http://10.0.0.5:8080');
      expect(store.token, _key, reason: 'key is remembered');
      expect(store.url, 'http://10.0.0.5:8080');
      expect(state.status, ProtectionStatus.monitoringActive);
    });

    test('an API key works directly', () async {
      expect(await connector.connect('10.0.0.5:8080', _key), isNull);
      expect(state.connected, isTrue);
    });

    test('a wrong code is refused and nothing is saved', () async {
      final error = await connector.connect('10.0.0.5:8080', 'WRONG123');
      expect(error, 'wrong code');
      expect(state.connected, isFalse);
      expect(state.backendStatus, BackendStatus.needsPairing);
      expect(store.token, isNull);
    });

    test('a wrong API key is refused', () async {
      final error = await connector.connect('10.0.0.5:8080', 'z' * 43);
      expect(error, isNotNull);
      expect(state.connected, isFalse);
      expect(store.token, isNull);
    });

    test('an address that is not a ThreatGuard server is refused', () async {
      final other = BackendConnector(
        state,
        store: store,
        httpClient: MockClient((r) async => http.Response('<html></html>', 200)),
      );
      final error = await other.connect('10.0.0.9:80', _code);
      expect(error, contains('No ThreatGuard server'));
      other.dispose();
    });

    test('a server that is down is reported, not hung', () async {
      server.up = false;
      final error = await connector.connect('10.0.0.5:8080', _code);
      expect(error, contains('No ThreatGuard server'));
      expect(state.connected, isFalse);
    });

    test('empty and malformed input is caught before any request', () async {
      expect(await connector.connect('', _code), contains('server address'));
      expect(await connector.connect('10.0.0.5', '  '), contains('pairing code'));
      expect(server.requests, isEmpty);
    });
  });

  group('start-up', () {
    test('restores a saved connection', () async {
      store.url = 'http://10.0.0.5:8080';
      store.token = _key;
      await connector.start();
      expect(state.connected, isTrue);
      expect(state.messages, isNotEmpty);
    });

    test('nothing saved: not configured', () async {
      await connector.start();
      expect(state.backendStatus, BackendStatus.notConfigured);
    });

    test('an address but no key: asks to pair', () async {
      store.url = 'http://10.0.0.5:8080';
      await connector.start();
      expect(state.backendStatus, BackendStatus.needsPairing);
    });

    test('a revoked key is forgotten and the device must pair again', () async {
      store.url = 'http://10.0.0.5:8080';
      store.token = _key;
      server.keyRevoked = true;
      await connector.start();
      expect(state.connected, isFalse);
      expect(state.backendStatus, BackendStatus.needsPairing);
      expect(store.token, isNull);
    });

    test('a server that is down keeps the key and reports unreachable', () async {
      store.url = 'http://10.0.0.5:8080';
      store.token = _key;
      server.up = false;
      await connector.start();
      expect(state.backendStatus, BackendStatus.unreachable);
      expect(state.status, ProtectionStatus.permissionRequired);
      expect(store.token, _key, reason: 'the server may just be off for now');
    });
  });

  group('while connected', () {
    setUp(() async {
      await connector.connect('10.0.0.5:8080', _code);
      server.requests.clear();
    });

    test('scan pulls fresh state from the server', () async {
      server.messages = [_msg(1, 'A', 90), _msg(2, 'B', 5, category: 'safe')];
      await state.runScan();
      expect(state.scanError, isNull);
      expect(state.lastScan, isNotNull);
      expect(state.messages.length, 2);
      expect(state.threatCount, 1);
      expect(server.requests, contains('POST /api/scan'));
    });

    test('a failed scan is reported', () async {
      server.up = false;
      await state.runScan();
      expect(state.scanError, isNotNull);
      expect(state.scanning, isFalse);
    });

    test('a settings change is saved after a short pause, once', () async {
      state.update(() => state.sensitivity = Sensitivity.strict);
      state.update(() => state.autoBlock = false);
      expect(server.requests, isEmpty, reason: 'debounced');
      await Future<void>.delayed(const Duration(milliseconds: 600));

      expect(server.requests.where((r) => r == 'PUT /api/settings').length, 1);
      expect(server.lastSettingsBody, containsPair('sensitivity', 'strict'));
      expect(server.lastSettingsBody, containsPair('autoBlock', false));
      expect(state.sensitivity, Sensitivity.strict, reason: 'echo must not undo the UI');
    });

    test('blocking a sender is saved; the block list is the server\'s', () async {
      state.blockSender('SPAMMER');
      await Future<void>.delayed(const Duration(milliseconds: 50));
      expect(server.blocked, ['SPAMMER']);
      expect(state.isManuallyBlocked('SPAMMER'), isTrue);
    });

    test('a block the server rejects is undone and reported', () async {
      server.failBlock = true;
      state.blockSender('SPAMMER');
      expect(state.isManuallyBlocked('SPAMMER'), isTrue, reason: 'optimistic');
      await Future<void>.delayed(const Duration(milliseconds: 50));
      expect(state.isManuallyBlocked('SPAMMER'), isFalse);
      expect(state.syncError, isNotNull);
    });

    test('checking a message adds it immediately', () async {
      final m = await connector.checkMessage('DHL', 'pay a fee');
      expect(m.sender, 'DHL');
      expect(state.messages.first.sender, 'DHL');
    });

    test('an empty sender is sent through for the server to name', () async {
      final m = await connector.checkMessage('', 'hello');
      expect(m.sender, 'Unknown');
    });

    test('deleting a message removes it', () async {
      await state.deleteMessage(state.messages.first);
      expect(state.messages, isEmpty);
    });

    test('a poll applies changes but never overwrites preferences', () async {
      state.monitoring = false; // flipped locally, not yet saved
      server.messages = [_msg(1, 'A', 90), _msg(2, 'NEW', 80)];
      server.revision = 'r-new';
      await connector.retry();
      expect(state.messages.length, 2);
      expect(state.monitoring, isFalse, reason: 'local switch survives the poll');
    });

    test('a link for another phone carries a fresh code', () async {
      final link = await connector.newPairingLink();
      expect(link, 'http://10.0.0.5:8080/?pair=NEWCODE22');
    });

    test('disconnecting forgets the key and wipes the local history', () async {
      expect(state.messages, isNotEmpty);
      await connector.disconnect();
      expect(state.connected, isFalse);
      expect(state.messages, isEmpty);
      expect(store.token, isNull);
      expect(state.backendStatus, BackendStatus.needsPairing);
      expect(state.protectionScore, isNull);
    });

    test('losing the server clears the "protected" flags', () async {
      server.up = false;
      await connector.retry();
      await connector.retry(); // two misses
      expect(state.backendStatus, BackendStatus.unreachable);
      expect(state.monitoringRunning, isFalse);
      expect(state.engineConnected, isFalse);
      expect(state.status, ProtectionStatus.permissionRequired);
    });
  });

  group('phone text messages (Android)', () {
    Future<void> settle() => Future<void>.delayed(const Duration(milliseconds: 80));

    setUp(() {
      sms.access = DeviceSmsAccess.granted;
      sms.inbox = _inbox(3);
    });

    test('the access state is read at start-up', () async {
      await connector.start();
      expect(state.deviceSms, DeviceSmsAccess.granted);
      sms.access = DeviceSmsAccess.unsupported;
      await connector.start();
      expect(state.deviceSms, DeviceSmsAccess.unsupported);
    });

    test('connecting links the background receiver and imports the inbox', () async {
      await connector.start();
      await connector.connect('10.0.0.5:8080', _code);
      await settle();

      expect(sms.linkedUrl, 'http://10.0.0.5:8080');
      expect(sms.linkedToken, _key);
      expect(server.importSizes, [3]);
      expect(state.messages.length, 1 + 3, reason: 'the server\'s own + 3 imported');
    });

    test('without permission nothing is read, but the receiver is still linked', () async {
      sms.access = DeviceSmsAccess.notGranted;
      await connector.start();
      await connector.connect('10.0.0.5:8080', _code);
      await settle();
      expect(server.importSizes, isEmpty);
      expect(sms.linkedToken, _key, reason: 'ready for the moment access is allowed');
    });

    test('where the inbox is not supported, nothing is imported', () async {
      sms.access = DeviceSmsAccess.unsupported;
      await connector.start();
      await connector.connect('10.0.0.5:8080', _code);
      await settle();
      expect(server.importSizes, isEmpty);
    });

    test('a scan imports first, in chunks, then scans', () async {
      await connector.start();
      await connector.connect('10.0.0.5:8080', _code);
      await settle();
      server.importSizes.clear();
      server.requests.clear();
      sms.inbox = _inbox(250);

      await state.runScan();

      expect(state.scanError, isNull);
      expect(server.importSizes, [100, 100, 50]);
      final order = server.requests;
      expect(
        order.indexOf('POST /api/messages/import'),
        lessThan(order.indexOf('POST /api/scan')),
      );
    });

    test('scanning again adds no duplicates', () async {
      await connector.start();
      await connector.connect('10.0.0.5:8080', _code);
      await settle();
      final before = state.messages.length;
      await state.runScan();
      await state.runScan();
      expect(state.messages.length, before);
    });

    test('a scan limits how much of the inbox it reads', () async {
      await connector.start();
      await connector.connect('10.0.0.5:8080', _code);
      await settle();
      server.importSizes.clear();
      sms.inbox = _inbox(1000);
      await state.runScan();
      expect(server.importSizes.fold<int>(0, (a, b) => a + b), BackendConnector.inboxLimit);
    });

    test('permission taken away mid-use: the scan fails and the state corrects itself', () async {
      await connector.start();
      await connector.connect('10.0.0.5:8080', _code);
      await settle();
      sms.access = DeviceSmsAccess.notGranted;
      sms.readError = PlatformException(code: 'no_permission');

      await state.runScan();

      expect(state.scanError, isNotNull);
      expect(state.deviceSms, DeviceSmsAccess.notGranted);
    });

    test('a failed background import is silent', () async {
      sms.readError = PlatformException(code: 'read_failed');
      await connector.start();
      await connector.connect('10.0.0.5:8080', _code);
      await settle();
      expect(state.connected, isTrue);
      expect(state.syncError, isNull);
    });

    test('allowing access starts an import; refusing does not', () async {
      sms.access = DeviceSmsAccess.notGranted;
      await connector.start();
      await connector.connect('10.0.0.5:8080', _code);
      await settle();

      sms.answerToRequest = DeviceSmsAccess.notGranted;
      await connector.requestDeviceSms();
      await settle();
      expect(state.deviceSms, DeviceSmsAccess.notGranted);
      expect(server.importSizes, isEmpty);

      sms.answerToRequest = DeviceSmsAccess.granted;
      await connector.requestDeviceSms();
      await settle();
      expect(state.deviceSms, DeviceSmsAccess.granted);
      expect(server.importSizes, [3]);
      expect(sms.requests, 2);
    });

    test('returning to the app notices a permission granted in Android settings', () async {
      sms.access = DeviceSmsAccess.notGranted;
      await connector.start();
      await connector.connect('10.0.0.5:8080', _code);
      await settle();
      expect(server.importSizes, isEmpty);

      sms.access = DeviceSmsAccess.granted; // the user flipped it in Settings
      await connector.onAppResumed();
      await settle();

      expect(state.deviceSms, DeviceSmsAccess.granted);
      expect(server.importSizes, [3]);
    });

    test('opening Android settings is passed through', () async {
      await connector.openDeviceSmsSettings();
      expect(sms.settingsOpened, isTrue);
    });

    test('disconnecting stops the background receiver from sending texts', () async {
      await connector.start();
      await connector.connect('10.0.0.5:8080', _code);
      await settle();
      expect(sms.linkedToken, isNotNull);

      await connector.disconnect();
      expect(sms.linkedUrl, isNull);
      expect(sms.linkedToken, isNull);
    });

    test('a revoked key also stops the receiver', () async {
      await connector.start();
      await connector.connect('10.0.0.5:8080', _code);
      await settle();
      server.keyRevoked = true;
      await connector.retry();
      expect(sms.linkedToken, isNull);
      expect(state.backendStatus, BackendStatus.needsPairing);
    });
  });

  group('AndroidSmsSource (the native channel)', () {
    const channel = MethodChannel('threatguard/sms');
    late TestDefaultBinaryMessenger messenger;
    final calls = <MethodCall>[];

    setUp(() {
      messenger = TestWidgetsFlutterBinding.ensureInitialized().defaultBinaryMessenger;
      calls.clear();
    });
    tearDown(() => messenger.setMockMethodCallHandler(channel, null));

    void mock(Future<Object?> Function(MethodCall) h) =>
        messenger.setMockMethodCallHandler(channel, (c) {
          calls.add(c);
          return h(c);
        });

    test('maps permission answers', () async {
      mock((c) async => c.method == 'status' ? true : false);
      final source = AndroidSmsSource();
      expect(await source.status(), DeviceSmsAccess.granted);
      expect(await source.request(), DeviceSmsAccess.notGranted);
    });

    test('reads rows: blank bodies dropped, blank senders named, times in UTC', () async {
      mock((c) async => [
        {'sender': '  BANK ', 'body': 'hello', 'date': 1767225600000},
        {'sender': null, 'body': 'from nobody', 'date': 1767225660000},
        {'sender': 'X', 'body': '   ', 'date': 1},
        {'sender': 'Y', 'body': null, 'date': 1},
      ]);
      final msgs = await AndroidSmsSource().readRecent(50);
      expect(calls.single.arguments, {'limit': 50});
      expect(msgs.length, 2);
      expect(msgs[0].sender, 'BANK');
      expect(msgs[0].at, DateTime.utc(2026, 1, 1));
      expect(msgs[1].sender, 'Unknown');
    });

    test('hands the server to the native receiver', () async {
      mock((c) async => null);
      final source = AndroidSmsSource();
      await source.linkServer('http://10.0.0.5:8080', 'secret');
      await source.unlinkServer();
      expect(calls.map((c) => c.method), ['saveServer', 'clearServer']);
      expect(calls.first.arguments, {'url': 'http://10.0.0.5:8080', 'token': 'secret'});
    });

    test('outside the Android app it quietly reports unsupported', () async {
      // No handler registered: MissingPluginException.
      final source = AndroidSmsSource();
      expect(await source.status(), DeviceSmsAccess.unsupported);
      await source.linkServer('u', 't'); // must not throw
      await source.unlinkServer();
      await source.openSettings();
    });

    test('InboxSms goes to the server in the import format', () {
      final json = InboxSms(sender: 'A', body: 'b', at: DateTime.utc(2026, 1, 2, 3)).toJson();
      expect(json, {'sender': 'A', 'body': 'b', 'receivedAt': '2026-01-02T03:00:00.000Z'});
    });

    test('NoSmsSource is inert', () async {
      const source = NoSmsSource();
      expect(await source.status(), DeviceSmsAccess.unsupported);
      expect(await source.readRecent(10), isEmpty);
    });
  });

  group('trends are computed from real timestamps', () {
    test('daily and weekly buckets', () {
      final now = DateTime.now();
      final today = DateTime(now.year, now.month, now.day);
      state.setDeviceMessages([
        SmsMessage.fromJson(_msg(1, 'a', 90, at: today.add(const Duration(hours: 1)))),
        SmsMessage.fromJson(_msg(2, 'b', 90, at: today.add(const Duration(hours: 5)))),
        SmsMessage.fromJson(_msg(3, 'c', 5, category: 'safe', at: today.add(const Duration(hours: 5)))),
        SmsMessage.fromJson(_msg(4, 'd', 90, at: today.subtract(const Duration(days: 2)))),
        SmsMessage.fromJson(_msg(5, 'e', 90, at: today.subtract(const Duration(days: 30)))),
      ]);
      // Only threats count, in the right four-hour block.
      expect(state.dailyTrend.sublist(0, 2), [1, 1]);
      expect(state.dailyTrend.fold<int>(0, (a, b) => a + b), lessThanOrEqualTo(2));
      expect(state.weeklyTrend.length, 7);
      expect(state.weeklyTrend[6], greaterThanOrEqualTo(1)); // today
      expect(state.weeklyTrend[4], 1); // two days ago
      expect(state.weeklyTrend.fold<int>(0, (a, b) => a + b), lessThanOrEqualTo(4),
          reason: 'the 30-day-old message is outside the window');
    });
  });
}
