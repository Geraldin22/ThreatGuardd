import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import '../models/sms_message.dart';
import '../state/guard_state.dart';
import 'backend_client.dart';
import 'sms_source.dart';

/// Where the server address and API key are remembered between launches.
abstract interface class ConnectionStore {
  Future<({String? url, String? token})> load();
  Future<void> save({required String url, String? token});
  Future<void> clearToken();
}

class PrefsConnectionStore implements ConnectionStore {
  static const _urlKey = 'tg.serverUrl';
  static const _tokenKey = 'tg.apiKey';

  @override
  Future<({String? url, String? token})> load() async {
    final p = await SharedPreferences.getInstance();
    return (url: p.getString(_urlKey), token: p.getString(_tokenKey));
  }

  @override
  Future<void> save({required String url, String? token}) async {
    final p = await SharedPreferences.getInstance();
    await p.setString(_urlKey, url);
    if (token != null) await p.setString(_tokenKey, token);
  }

  @override
  Future<void> clearToken() async {
    final p = await SharedPreferences.getInstance();
    await p.remove(_tokenKey);
  }
}

class MemoryConnectionStore implements ConnectionStore {
  String? url, token;

  @override
  Future<({String? url, String? token})> load() async => (url: url, token: token);

  @override
  Future<void> save({required String url, String? token}) async {
    this.url = url;
    if (token != null) this.token = token;
  }

  @override
  Future<void> clearToken() async => token = null;
}

/// Connects [GuardState] to a ThreatGuard server.
///
/// It installs itself into the hooks the UI already had (`scanHandler`,
/// `backend`) and keeps the screen in step with the server: it polls for new
/// messages, and saves preference changes as they happen.
class BackendConnector implements BackendActions {
  BackendConnector(
    this.state, {
    ConnectionStore? store,
    http.Client? httpClient,
    Uri? pageUri,
    SmsSource? sms,
    this.pollEvery = const Duration(seconds: 12),
  }) : _store = store ?? PrefsConnectionStore(),
       _http = httpClient,
       _sms = sms ?? SmsSource.forPlatform(),
       _pageUri = pageUri ?? Uri.base {
    state.backend = this;
    state.scanHandler = _scan;
  }

  /// How many of the newest inbox messages a scan reads, and how many go to
  /// the server per request.
  static const inboxLimit = 300;
  static const importChunk = 100;

  final GuardState state;
  final ConnectionStore _store;
  final SmsSource _sms;
  final http.Client? _http;
  bool _importing = false;
  final Uri _pageUri;
  final Duration pollEvery;

  BackendClient? _client;
  Timer? _poll;
  Timer? _saveDebounce;
  String? _revision;
  bool _polling = false;
  bool _saving = false;
  bool _saveAgain = false;
  int _failures = 0;
  bool _disposed = false;

  /// The page this app was loaded from, when it is a web page served by a
  /// ThreatGuard server (the normal way a phone gets it).
  Uri? get _pageOrigin =>
      kIsWeb && (_pageUri.scheme == 'http' || _pageUri.scheme == 'https')
      ? Uri(scheme: _pageUri.scheme, host: _pageUri.host, port: _pageUri.hasPort ? _pageUri.port : null)
      : null;

  BackendClient _clientFor(Uri base, {String? token}) =>
      BackendClient(base, token: token, client: _http);

  // ------------------------------------------------------------- start up

  /// Picks up where the last session left off, or follows a pairing link.
  Future<void> start() async {
    state.setDeviceSms(await _sms.status());
    final saved = await _store.load();
    var url = saved.url == null ? null : normalizeServerUrl(saved.url!);
    final token = saved.token;
    final pageOrigin = _pageOrigin;

    // A phone opening the link printed by the server: same-origin pairing.
    final code = _pageUri.queryParameters['pair'];
    if (token == null && code != null && pageOrigin != null) {
      final error = await _pairAndConnect(pageOrigin, code);
      if (error != null) {
        state.setBackendStatus(
          BackendStatus.needsPairing,
          url: pageOrigin.toString(),
          error: error,
        );
      }
      return;
    }

    // Opened straight from a ThreatGuard server: that server is the default.
    if (url == null && pageOrigin != null) {
      final probe = _clientFor(pageOrigin);
      if (await probe.isThreatGuard()) url = pageOrigin;
      probe.close();
    }

    if (url == null) {
      state.setBackendStatus(BackendStatus.notConfigured);
      return;
    }
    if (token == null) {
      state.setBackendStatus(BackendStatus.needsPairing, url: url.toString());
      return;
    }
    await _useCredentials(url, token);
  }

  // ----------------------------------------------------------- connecting

  @override
  Future<String?> connect(String input, String secret) async {
    final url = normalizeServerUrl(input);
    if (url == null) return 'That does not look like a server address.';
    final key = secret.trim();
    if (key.isEmpty) return 'Enter the pairing code or API key.';
    if (kIsWeb &&
        _pageUri.scheme == 'https' &&
        url.scheme == 'http' &&
        url.host != 'localhost') {
      return 'This page is secure (https), so it can only connect to an '
          'https server. Open ThreatGuard from your server\'s own address '
          'instead.';
    }

    state.setBackendStatus(BackendStatus.connecting, url: url.toString());
    final probe = _clientFor(url);
    if (!await probe.isThreatGuard()) {
      probe.close();
      _restoreIdle(url);
      return 'No ThreatGuard server answered at $url.';
    }
    probe.close();

    final isCode = key.replaceAll(RegExp(r'[\s-]'), '').length <= 12;
    if (isCode) {
      final error = await _pairAndConnect(url, key);
      if (error != null) _restoreIdle(url, error: error);
      return error;
    }
    final error = await _useCredentials(url, key, remember: true);
    if (error != null) _restoreIdle(url, error: error);
    return error;
  }

  void _restoreIdle(Uri url, {String? error}) => state.setBackendStatus(
    BackendStatus.needsPairing,
    url: url.toString(),
    error: error,
  );

  Future<String?> _pairAndConnect(Uri url, String code) async {
    final client = _clientFor(url);
    try {
      final token = await client.pair(code);
      client.close();
      return await _useCredentials(url, token, remember: true);
    } on BackendException catch (e) {
      client.close();
      return e.message;
    }
  }

  /// Fetches state with the key. Returns an error message, or null when the
  /// device is connected.
  Future<String?> _useCredentials(Uri url, String token, {bool remember = false}) async {
    _stopPolling();
    _client?.close();
    final client = _client = _clientFor(url, token: token);
    state.setBackendStatus(BackendStatus.connecting, url: url.toString());
    try {
      final snapshot = await client.state();
      if (remember) await _store.save(url: url.toString(), token: token);
      _failures = 0;
      _apply(snapshot!, includeSettings: true);
      _startPolling();
      // Let the background receiver reach this server, and catch up on any
      // texts that arrived while the app was closed.
      await _sms.linkServer(url.toString(), token);
      unawaited(_autoImport());
      return null;
    } on BackendException catch (e) {
      if (e.unauthorized) {
        await _store.clearToken();
        await _sms.unlinkServer();
        _client = null;
        client.close();
        state.setBackendStatus(
          BackendStatus.needsPairing,
          url: url.toString(),
          error: 'This device is no longer linked. Pair it again.',
        );
        return 'That API key was not accepted.';
      }
      // Keep the credentials: the server may just be off for now.
      _startPolling();
      state.setBackendStatus(
        BackendStatus.unreachable,
        url: url.toString(),
        error: e.message,
      );
      return e.message;
    }
  }

  @override
  Future<void> retry() => _refresh(force: true);

  @override
  Future<void> disconnect() async {
    _stopPolling();
    _saveDebounce?.cancel();
    _client?.close();
    _client = null;
    _revision = null;
    await _store.clearToken();
    await _sms.unlinkServer(); // the receiver must stop sending texts
    // This device should not keep a copy of the message history.
    state.setDeviceMessages(const []);
    state.lastScan = null;
    state.setBackendStatus(BackendStatus.needsPairing);
  }

  // -------------------------------------------------------------- syncing

  void _apply(ServerState s, {required bool includeSettings}) {
    _revision = s.revision;
    state.applyServerState(
      settings: s.settings,
      blocked: s.blocked,
      messages: s.messages,
      protectionScore: s.protectionScore,
      engine: s.engine,
      includeSettings: includeSettings,
    );
  }

  void _startPolling() {
    _poll?.cancel();
    _poll = Timer.periodic(pollEvery, (_) => _refresh());
  }

  void _stopPolling() {
    _poll?.cancel();
    _poll = null;
  }

  /// Brings the screen up to date. Quiet on failure: after a few misses the
  /// app says it cannot reach the server, and keeps trying.
  Future<void> _refresh({bool force = false}) async {
    final client = _client;
    if (client == null || _polling || state.scanning || _saving) return;
    _polling = true;
    try {
      final s = await client.state(revision: force ? null : _revision);
      _failures = 0;
      if (_disposed) return;
      if (s != null) {
        // Preferences are only taken from the server on connect and scan, so
        // a poll never undoes a switch the user just flipped.
        _apply(s, includeSettings: false);
      } else if (!state.connected) {
        // Same data as before, but the server is back.
        final again = await client.state();
        if (again != null) _apply(again, includeSettings: true);
      }
    } on BackendException catch (e) {
      if (_disposed) return;
      if (e.unauthorized) {
        _stopPolling();
        await _store.clearToken();
        await _sms.unlinkServer();
        _client = null;
        state.setBackendStatus(
          BackendStatus.needsPairing,
          error: 'This device is no longer linked. Pair it again.',
        );
      } else if (++_failures >= 2 && state.connected) {
        state.setBackendStatus(BackendStatus.unreachable, error: e.message);
      }
    } finally {
      _polling = false;
    }
  }

  Future<void> _scan(GuardState s) async {
    final client = _client;
    if (client == null) throw StateError('Not connected');
    s.setScanProgress(0.05);
    // On Android, read the phone's inbox first so the scan covers real texts.
    if (state.deviceSms == DeviceSmsAccess.granted) {
      try {
        await _importInbox(
          onProgress: (done) => s.setScanProgress(0.05 + 0.65 * done),
        );
      } on PlatformException {
        // Most likely the permission was taken back in Android settings.
        state.setDeviceSms(await _sms.status());
        rethrow;
      }
    }
    s.setScanProgress(0.75);
    final snapshot = await client.scan();
    s.setScanProgress(0.95);
    _apply(snapshot, includeSettings: true);
  }

  // ------------------------------------------------------ phone inbox

  /// Reads the newest inbox messages and sends them to the server in chunks.
  /// The server skips any it already has. Returns how many were new.
  Future<int> _importInbox({void Function(double done)? onProgress}) async {
    final client = _client;
    if (client == null || _importing) return 0;
    _importing = true;
    try {
      final messages = await _sms.readRecent(inboxLimit);
      var added = 0;
      for (var i = 0; i < messages.length; i += importChunk) {
        final end = math.min(i + importChunk, messages.length);
        added += await client.importMessages(messages.sublist(i, end));
        onProgress?.call(end / messages.length);
      }
      return added;
    } finally {
      _importing = false;
    }
  }

  /// Background catch-up. Never interrupts the user: a failure here only
  /// means the next scan will do it.
  Future<void> _autoImport() async {
    if (state.deviceSms != DeviceSmsAccess.granted) return;
    try {
      if (await _importInbox() > 0) await _refresh(force: true);
    } on PlatformException {
      state.setDeviceSms(await _sms.status());
    } on BackendException {
      // Server unreachable; the poll reports that.
    }
  }

  @override
  Future<void> requestDeviceSms() async {
    final access = await _sms.request();
    state.setDeviceSms(access);
    if (access == DeviceSmsAccess.granted) unawaited(_autoImport());
  }

  @override
  Future<void> openDeviceSmsSettings() => _sms.openSettings();

  /// Called when the app comes back to the foreground: the user may have
  /// changed the SMS permission in Android settings, and texts may have
  /// arrived that the receiver could not deliver.
  Future<void> onAppResumed() async {
    state.setDeviceSms(await _sms.status());
    if (_client == null) return;
    await _autoImport();
    unawaited(_refresh());
  }

  @override
  void preferencesChanged() {
    if (_client == null) return;
    _saveDebounce?.cancel();
    _saveDebounce = Timer(const Duration(milliseconds: 400), _savePreferences);
  }

  Future<void> _savePreferences() async {
    final client = _client;
    if (client == null) return;
    if (_saving) {
      _saveAgain = true;
      return;
    }
    _saving = true;
    try {
      do {
        _saveAgain = false;
        final snapshot = await client.saveSettings({
          'monitoring': state.monitoring,
          'autoBlock': state.autoBlock,
          'linkScanning': state.linkScanning,
          'alerts': state.alerts,
          'shareIntel': state.shareIntel,
          'sensitivity': state.sensitivity.name,
        });
        if (!_saveAgain && !_disposed) _apply(snapshot, includeSettings: false);
      } while (_saveAgain);
    } on BackendException catch (e) {
      if (e.unauthorized) {
        _client = null;
        _stopPolling();
        state.setBackendStatus(BackendStatus.needsPairing);
      } else {
        state.reportSyncError(
          'Could not save your settings. They will be tried again when you change one.',
        );
      }
    } finally {
      _saving = false;
    }
  }

  // ------------------------------------------------------------- actions

  BackendClient get _ready {
    final c = _client;
    if (c == null || !state.connected) {
      throw BackendException('Not connected to a server.');
    }
    return c;
  }

  @override
  Future<SmsMessage> checkMessage(String sender, String body) async {
    final message = await _ready.checkMessage(sender, body);
    state.addDeviceMessage(message);
    // Pull the authoritative list (block flags, score) without waiting.
    unawaited(_refresh(force: true));
    return message;
  }

  @override
  Future<void> setBlocked(String sender, bool blocked) async =>
      _apply(await _ready.setBlocked(sender, blocked), includeSettings: false);

  @override
  Future<void> deleteMessage(int id) async =>
      _apply(await _ready.deleteMessage(id), includeSettings: false);

  @override
  Future<void> clearMessages() async =>
      _apply(await _ready.clearMessages(), includeSettings: false);

  @override
  Future<String> newPairingLink() async {
    final client = _ready;
    final code = await client.newPairingCode();
    return client.base.replace(path: '/', queryParameters: {'pair': code}).toString();
  }

  void dispose() {
    _disposed = true;
    _stopPolling();
    _saveDebounce?.cancel();
    _client?.close();
  }
}
