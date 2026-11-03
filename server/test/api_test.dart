import 'dart:convert';
import 'dart:io';

import 'package:shelf/shelf.dart';
import 'package:test/test.dart';
import 'package:threatguard_server/src/app.dart';
import 'package:threatguard_server/src/auth.dart';
import 'package:threatguard_server/src/store.dart';

const _key = 'test-key-0123456789abcdef';
const _phish =
    'Your account has been suspended. Verify immediately at http://secure-bank-verify.example.com';

late Store store;
late Auth auth;
late Handler app;
var now = DateTime.utc(2026, 1, 1, 12);

void setUpApp({String? webDir}) {
  store = Store.open(null);
  auth = Auth(_key, clock: () => now);
  app = buildApp(store: store, auth: auth, webDir: webDir);
}

Future<Response> call(
  String method,
  String path, {
  Object? body,
  Map<String, String>? headers,
  bool authed = true,
}) async {
  return await app(
    Request(
      method,
      Uri.parse('http://localhost$path'),
      body: body is String ? body : (body == null ? null : jsonEncode(body)),
      headers: {
        if (authed) 'authorization': 'Bearer $_key',
        if (body != null) 'content-type': 'application/json',
        ...?headers,
      },
    ),
  );
}

Future<Map<String, Object?>> jsonOf(Response r) async =>
    Map<String, Object?>.from(jsonDecode(await r.readAsString()) as Map);

void main() {
  setUp(() {
    now = DateTime.utc(2026, 1, 1, 12);
    setUpApp();
  });

  group('auth', () {
    test('health is public', () async {
      final r = await call('GET', '/api/health', authed: false);
      expect(r.statusCode, 200);
      expect((await jsonOf(r))['service'], 'threatguard');
    });

    test('everything else needs the key', () async {
      for (final (method, path) in [
        ('GET', '/api/state'),
        ('GET', '/api/settings'),
        ('POST', '/api/scan'),
        ('POST', '/api/messages'),
        ('DELETE', '/api/messages'),
      ]) {
        final r = await call(method, path, authed: false);
        expect(r.statusCode, 401, reason: '$method $path');
      }
    });

    test('rejects a wrong key, accepts Bearer and X-Api-Key', () async {
      expect(
        (await call('GET', '/api/state', authed: false, headers: {'authorization': 'Bearer nope'})).statusCode,
        401,
      );
      expect(
        (await call('GET', '/api/state', authed: false, headers: {'x-api-key': _key})).statusCode,
        200,
      );
      expect((await call('GET', '/api/state')).statusCode, 200);
    });
  });

  group('pairing', () {
    test('a code is exchanged for the key exactly once', () async {
      final code = auth.newPairingCode().code;
      final ok = await call('POST', '/api/pair', body: {'code': code}, authed: false);
      expect(ok.statusCode, 200);
      expect((await jsonOf(ok))['token'], _key);
      final again = await call('POST', '/api/pair', body: {'code': code}, authed: false);
      expect(again.statusCode, 403);
    });

    test('codes are forgiving about case and spacing', () async {
      final code = auth.newPairingCode().code;
      final spaced = '${code.substring(0, 4)} - ${code.substring(4).toLowerCase()}';
      final r = await call('POST', '/api/pair', body: {'code': spaced}, authed: false);
      expect(r.statusCode, 200);
    });

    test('five wrong guesses burn the code', () async {
      final code = auth.newPairingCode().code;
      for (var i = 0; i < Auth.maxWrongAttempts; i++) {
        final r = await call('POST', '/api/pair', body: {'code': 'WRONG$i'}, authed: false);
        expect(r.statusCode, 403);
      }
      final r = await call('POST', '/api/pair', body: {'code': code}, authed: false);
      expect(r.statusCode, 403, reason: 'the right code no longer works');
    });

    test('codes expire', () async {
      final code = auth.newPairingCode().code;
      now = now.add(Auth.codeLifetime + const Duration(seconds: 1));
      final r = await call('POST', '/api/pair', body: {'code': code}, authed: false);
      expect(r.statusCode, 403);
    });

    test('a new code replaces the old one, and needs the key', () async {
      final old = auth.newPairingCode().code;
      expect((await call('POST', '/api/pair/new', authed: false)).statusCode, 401);
      final fresh = (await jsonOf(await call('POST', '/api/pair/new')))['code'] as String;
      expect(fresh, isNot(old));
      expect(
        (await call('POST', '/api/pair', body: {'code': old}, authed: false)).statusCode,
        403,
      );
    });

    test('Auth.load rejects a short environment token', () {
      expect(() => Auth.load(envToken: 'short'), throwsArgumentError);
    });
  });

  group('messages', () {
    test('analyzes, stores and returns a message', () async {
      final r = await call('POST', '/api/messages', body: {
        'sender': 'BANK ALERT',
        'body': _phish,
        'source': 'manual',
      });
      expect(r.statusCode, 201);
      final m = await jsonOf(r);
      expect(m['id'], 1);
      expect(m['category'], 'banking');
      expect(m['band'], 'high');
      expect(m['action'], 'block');
      expect(m['url'], 'secure-bank-verify.example.com');
      expect((m['signals'] as List), isNotEmpty);

      final state = await jsonOf(await call('GET', '/api/state'));
      expect((state['messages'] as List).length, 1);
    });

    test('a harmless message is allowed', () async {
      final m = await jsonOf(await call('POST', '/api/messages',
          body: {'sender': 'MOM', 'body': "I'll be home around 6."}));
      expect(m['category'], 'safe');
      expect(m['action'], 'allow');
    });

    test('newest message comes first and ids increase', () async {
      await call('POST', '/api/messages', body: {'body': 'first'});
      await call('POST', '/api/messages', body: {'body': 'second'});
      final msgs = (await jsonOf(await call('GET', '/api/state')))['messages'] as List;
      expect([for (final m in msgs) (m as Map)['body']], ['second', 'first']);
    });

    test('missing sender becomes Unknown', () async {
      final m = await jsonOf(await call('POST', '/api/messages', body: {'body': 'hi'}));
      expect(m['sender'], 'Unknown');
    });

    test('validation', () async {
      expect((await call('POST', '/api/messages', body: {'body': '   '})).statusCode, 400);
      expect((await call('POST', '/api/messages', body: {'sender': 'x'})).statusCode, 400);
      expect((await call('POST', '/api/messages', body: {'body': 5})).statusCode, 400);
      expect((await call('POST', '/api/messages', body: {'body': 'x' * 2001})).statusCode, 400);
      expect((await call('POST', '/api/messages', body: {'body': 'x', 'sender': 'y' * 101})).statusCode, 400);
      expect((await call('POST', '/api/messages', body: {'body': 'x', 'receivedAt': 'yesterday'})).statusCode, 400);
      expect((await call('POST', '/api/messages', body: 'not json')).statusCode, 400);
      expect((await call('POST', '/api/messages', body: '[1,2]')).statusCode, 400);
      expect((await call('POST', '/api/messages', body: 'x' * (70 * 1024))).statusCode, 413);
      expect(store.messages, isEmpty);
    });

    test('a future timestamp is clamped to now', () async {
      final m = await jsonOf(await call('POST', '/api/messages', body: {
        'body': 'hi',
        'receivedAt': DateTime.now().toUtc().add(const Duration(days: 30)).toIso8601String(),
      }));
      expect(DateTime.parse(m['receivedAt'] as String).isAfter(DateTime.now().toUtc().add(const Duration(minutes: 1))), isFalse);
    });

    test('delete one, 404 for unknown, clear all', () async {
      await call('POST', '/api/messages', body: {'body': 'a'});
      await call('POST', '/api/messages', body: {'body': 'b'});
      expect((await call('DELETE', '/api/messages/99')).statusCode, 404);
      expect((await call('DELETE', '/api/messages/abc')).statusCode, 404);
      expect((await call('DELETE', '/api/messages/1')).statusCode, 200);
      expect(store.messages.length, 1);
      final r = await jsonOf(await call('DELETE', '/api/messages'));
      expect(r['deleted'], 1);
      expect(store.messages, isEmpty);
    });

    test('history is capped', () async {
      for (var i = 0; i < maxMessages + 3; i++) {
        store.add(sender: 's', body: 'm$i', source: 'forward');
      }
      expect(store.messages.length, maxMessages);
      expect(store.messages.first.body, 'm${maxMessages + 2}');
    });
  });

  group('phone inbox import', () {
    Future<Response> import(Object? messages) =>
        call('POST', '/api/messages/import', body: {'messages': messages});

    Map<String, Object?> row(String sender, String body, DateTime at) =>
        {'sender': sender, 'body': body, 'receivedAt': at.toUtc().toIso8601String()};

    final t0 = DateTime.utc(2026, 1, 1, 9);

    test('adds messages, and importing the same inbox again adds nothing', () async {
      final rows = [
        row('BANK', _phish, t0),
        row('MOM', 'home at 6', t0.add(const Duration(hours: 1))),
      ];
      var r = await jsonOf(await import(rows));
      expect(r['added'], 2);
      expect(r['duplicates'], 0);
      expect(store.messages.length, 2);

      r = await jsonOf(await import(rows));
      expect(r['added'], 0);
      expect(r['duplicates'], 2);
      expect(store.messages.length, 2);
    });

    test('old messages sort by when they were received, not when they arrived', () async {
      store.add(sender: 'NEW', body: 'new', source: 'manual', receivedAt: t0.add(const Duration(days: 2)));
      await import([
        row('OLD', 'old', t0),
        row('MID', 'mid', t0.add(const Duration(days: 1))),
      ]);
      expect([for (final m in store.messages) m.sender], ['NEW', 'MID', 'OLD']);
    });

    test('works while monitoring is off, because the user asked for it', () async {
      await call('PUT', '/api/settings', body: {'monitoring': false});
      expect((await jsonOf(await import([row('A', 'hi', t0)])))['added'], 1);
    });

    test('messy rows are skipped, long text is cut, a missing sender is named', () async {
      final r = await jsonOf(await import([
        'not a map',
        {'sender': 'X', 'body': '   ', 'receivedAt': t0.toIso8601String()},
        {'sender': 'X', 'body': 'ok', 'receivedAt': 'yesterday'},
        {'sender': 'X', 'body': 5, 'receivedAt': t0.toIso8601String()},
        {'body': 'y' * 5000, 'receivedAt': t0.toIso8601String()},
      ]));
      expect(r['added'], 1);
      expect(r['skipped'], 4);
      expect(store.messages.single.body.length, maxBodyLength);
      expect(store.messages.single.sender, 'Unknown');
    });

    test('is analyzed like any other message and tagged as from the device', () async {
      await import([row('BANK', _phish, t0)]);
      final m = store.messages.single;
      expect(m.analysis.kind.name, 'banking');
      expect(m.source, 'device');
    });

    test('validation and limits', () async {
      expect((await call('POST', '/api/messages/import', body: {'messages': 'x'})).statusCode, 400);
      expect((await call('POST', '/api/messages/import', body: {})).statusCode, 400);
      expect((await import(List.generate(maxImportBatch + 1, (i) => row('s', 'm$i', t0)))).statusCode, 400);
      expect((await import(List.generate(maxImportBatch, (i) => row('s', 'm$i', t0.add(Duration(seconds: i)))))).statusCode, 200);
      expect((await call('POST', '/api/messages/import', body: {'messages': []}, authed: false)).statusCode, 401);
    });

    test('a single message with a timestamp is not stored twice', () async {
      final body = {'sender': 'MOM', 'body': 'hi', 'source': 'device', 'receivedAt': t0.toIso8601String()};
      final first = await call('POST', '/api/messages', body: body);
      final again = await call('POST', '/api/messages', body: body);
      expect(first.statusCode, 201);
      expect(again.statusCode, 200);
      expect((await jsonOf(again))['id'], (await jsonOf(first))['id']);
      expect(store.messages.length, 1);
    });

    test('live device messages are ignored while monitoring is off', () async {
      await call('PUT', '/api/settings', body: {'monitoring': false});
      final r = await call('POST', '/api/messages', body: {'body': 'hi', 'source': 'device'});
      expect(r.statusCode, 202);
    });
  });

  group('monitoring', () {
    test('forwarded messages are ignored while off, manual checks still work', () async {
      await call('PUT', '/api/settings', body: {'monitoring': false});
      final fwd = await call('POST', '/api/messages', body: {'body': _phish});
      expect(fwd.statusCode, 202);
      expect((await jsonOf(fwd))['reason'], 'monitoring_off');
      expect(store.messages, isEmpty);

      final manual = await call('POST', '/api/messages', body: {'body': _phish, 'source': 'manual'});
      expect(manual.statusCode, 201);
    });
  });

  group('blocking', () {
    test('manual block makes a harmless message from that sender blocked', () async {
      await call('POST', '/api/messages', body: {'sender': 'LUCAS', 'body': 'lunch at 12?'});
      var state = await jsonOf(await call('POST', '/api/blocked', body: {'sender': 'LUCAS', 'blocked': true}));
      expect(state['blocked'], ['LUCAS']);
      expect(((state['messages'] as List).first as Map)['action'], 'block');

      state = await jsonOf(await call('POST', '/api/blocked', body: {'sender': 'LUCAS', 'blocked': false}));
      expect(state['blocked'], isEmpty);
      expect(((state['messages'] as List).first as Map)['action'], 'allow');
    });

    test('auto-block only applies while the setting is on', () async {
      await call('PUT', '/api/settings', body: {'autoBlock': false});
      final m = await jsonOf(await call('POST', '/api/messages', body: {'body': _phish}));
      expect(m['band'], 'high');
      expect(m['action'], 'flag');

      final state = await jsonOf(await call('PUT', '/api/settings', body: {'autoBlock': true}));
      // autoBlock does not change scoring, but a re-scan must pick it up.
      await call('POST', '/api/scan');
      expect(((await jsonOf(await call('GET', '/api/state')))['messages'] as List).cast<Map>().first['action'], 'block');
      expect(state['settings'], isA<Map>());
    });

    test('validation', () async {
      expect((await call('POST', '/api/blocked', body: {'sender': 'x'})).statusCode, 400);
      expect((await call('POST', '/api/blocked', body: {'blocked': true})).statusCode, 400);
    });
  });

  group('settings', () {
    test('defaults, partial update and score', () async {
      final s = await jsonOf(await call('GET', '/api/settings'));
      expect((s['settings'] as Map)['monitoring'], true);
      expect(s['protectionScore'], 98); // 40+25+15+10+8

      final updated = await jsonOf(await call('PUT', '/api/settings',
          body: {'monitoring': false, 'sensitivity': 'relaxed'}));
      expect((updated['settings'] as Map)['monitoring'], false);
      expect((updated['settings'] as Map)['sensitivity'], 'relaxed');
      expect((updated['settings'] as Map)['autoBlock'], true, reason: 'untouched');
      expect(updated['protectionScore'], 40 + 15 + 10 + 4);
      expect(updated['monitoring'], false);
    });

    test('rejects bad values and changes nothing', () async {
      expect((await call('PUT', '/api/settings', body: {'monitoring': 'yes'})).statusCode, 400);
      expect((await call('PUT', '/api/settings', body: {'sensitivity': 'insane'})).statusCode, 400);
      expect((await call('PUT', '/api/settings', body: {'alerts': false, 'sensitivity': 'insane'})).statusCode, 400);
      expect(store.settings.alerts, true);
    });

    test('changing sensitivity re-scores history', () async {
      const text = 'Please verify your account now: http://example.com/check';
      final before = await jsonOf(await call('POST', '/api/messages', body: {'body': text}));
      final state = await jsonOf(await call('PUT', '/api/settings', body: {'sensitivity': 'strict'}));
      final after = (state['messages'] as List).cast<Map>().first;
      expect(after['risk'] as int, greaterThan(before['risk'] as int));
    });

    test('turning link scanning off re-scores history', () async {
      final before = await jsonOf(await call('POST', '/api/messages', body: {'body': _phish}));
      final state = await jsonOf(await call('PUT', '/api/settings', body: {'linkScanning': false}));
      final after = (state['messages'] as List).cast<Map>().first;
      expect(after['risk'] as int, lessThan(before['risk'] as int));
      expect(after['url'], isNull);
    });
  });

  group('state', () {
    test('an unchanged revision returns a tiny response', () async {
      final first = await jsonOf(await call('GET', '/api/state'));
      final rev = first['revision'] as String;
      final same = await jsonOf(await call('GET', '/api/state?rev=$rev'));
      expect(same, {'revision': rev, 'unchanged': true});

      await call('POST', '/api/messages', body: {'body': 'new'});
      final changed = await jsonOf(await call('GET', '/api/state?rev=$rev'));
      expect(changed['unchanged'], false);
      expect(changed['revision'], isNot(rev));
    });

    test('analyze does not store anything', () async {
      final r = await jsonOf(await call('POST', '/api/analyze', body: {'text': _phish}));
      expect(r['category'], 'banking');
      expect(store.messages, isEmpty);
    });

    test('scan returns the full state', () async {
      store.add(sender: 'a', body: _phish, source: 'forward');
      final r = await jsonOf(await call('POST', '/api/scan'));
      expect((r['messages'] as List).length, 1);
      expect(r['engine'], isA<Map>());
    });
  });

  group('http', () {
    test('unknown api path is a JSON 404', () async {
      final r = await call('GET', '/api/nope', authed: false);
      expect(r.statusCode, 404);
      expect((await jsonOf(r))['error'], isNotNull);
    });

    test('CORS preflight and headers', () async {
      final pre = await call('OPTIONS', '/api/messages', authed: false);
      expect(pre.statusCode, 204);
      expect(pre.headers['access-control-allow-headers'], contains('authorization'));
      final res = await call('GET', '/api/health', authed: false);
      expect(res.headers['access-control-allow-origin'], '*');
      expect(res.headers['cache-control'], 'no-store');
      expect(res.headers['x-content-type-options'], 'nosniff');
    });

    test('server errors do not leak details', () async {
      // A store whose save fails: point it at a path that cannot be written.
      final bad = Store.open('${Directory.systemTemp.path}/tg-test-${DateTime.now().microsecondsSinceEpoch}/x\u0000y');
      final failing = buildApp(store: bad, auth: auth);
      final r = await failing(Request('POST', Uri.parse('http://localhost/api/messages'),
          body: jsonEncode({'body': 'hi'}),
          headers: {'authorization': 'Bearer $_key'}));
      expect(r.statusCode, 500);
      expect(await r.readAsString(), isNot(contains('x\u0000y')));
    });
  });

  group('persistence', () {
    late Directory dir;
    setUp(() => dir = Directory.systemTemp.createTempSync('tg-store-'));
    tearDown(() => dir.deleteSync(recursive: true));

    test('messages, blocks and settings survive a restart', () {
      final a = Store.open(dir.path);
      a.updateSettings({'sensitivity': 'strict', 'alerts': false});
      a.setBlocked('SPAMMER', true);
      a.add(sender: 'BANK ALERT', body: _phish, source: 'manual');
      a.add(sender: 'MOM', body: 'home at 6', source: 'forward');

      final b = Store.open(dir.path);
      expect(b.messages.length, 2);
      expect(b.messages.last.sender, 'BANK ALERT');
      expect(b.messages.last.analysis.band.name, 'high');
      expect(b.blocked, ['SPAMMER']);
      expect(b.settings.sensitivity.name, 'strict');
      expect(b.settings.alerts, false);
      // ids keep counting up rather than being reused
      expect(b.add(sender: 's', body: 'x', source: 'forward').$1.id, 3);
    });

    test('the API key is created once and reused', () {
      final first = Auth.load(dir: dir.path);
      final second = Auth.load(dir: dir.path);
      expect(second.token, first.token);
      expect(first.token.length, greaterThanOrEqualTo(32));
    });

    test('an environment token wins over the file', () {
      Auth.load(dir: dir.path);
      expect(Auth.load(dir: dir.path, envToken: 'x' * 20).token, 'x' * 20);
    });
  });

  group('static web app', () {
    late Directory web;
    setUp(() {
      web = Directory.systemTemp.createTempSync('tg-web-');
      File('${web.path}/index.html').writeAsStringSync('<html>app</html>');
      File('${web.path}/main.js').writeAsStringSync('console.log(1)');
      Directory('${web.path}/secret').createSync();
      File('${web.parent.path}/tg-outside.txt').writeAsStringSync('outside');
      setUpApp(webDir: web.path);
    });
    tearDown(() {
      web.deleteSync(recursive: true);
      final f = File('${web.parent.path}/tg-outside.txt');
      if (f.existsSync()) f.deleteSync();
    });

    test('serves index at / (also with a pairing query) and files by path', () async {
      expect(await (await call('GET', '/', authed: false)).readAsString(), '<html>app</html>');
      expect(await (await call('GET', '/?pair=ABCD2345', authed: false)).readAsString(), '<html>app</html>');
      expect(await (await call('GET', '/main.js', authed: false)).readAsString(), 'console.log(1)');
    });

    test('unknown paths fall back to the app, but /api never does', () async {
      expect(await (await call('GET', '/some/deep/link', authed: false)).readAsString(), '<html>app</html>');
      final api = await call('GET', '/api/missing', authed: false);
      expect(api.statusCode, 404);
      expect(api.headers['content-type'], contains('json'));
    });

    test('cannot read outside the web folder', () async {
      for (final p in ['/../tg-outside.txt', '/%2e%2e/tg-outside.txt', '/..%2ftg-outside.txt']) {
        final body = await (await call('GET', p, authed: false)).readAsString();
        expect(body, isNot('outside'), reason: p);
      }
    });
  });
}
