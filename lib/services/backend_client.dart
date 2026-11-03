import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import '../models/sms_message.dart';
import 'sms_source.dart';

/// A failed call to the server. [status] is null when the server could not
/// be reached at all.
class BackendException implements Exception {
  BackendException(this.message, {this.status});
  final String message;
  final int? status;

  bool get unauthorized => status == 401;
  bool get unreachable => status == null;

  @override
  String toString() => message;
}

/// One snapshot of everything the server holds.
class ServerState {
  ServerState({
    required this.revision,
    required this.settings,
    required this.blocked,
    required this.messages,
    required this.protectionScore,
    required this.engine,
  });

  final String revision;
  final Map<String, Object?> settings;
  final List<String> blocked;
  final List<SmsMessage> messages;
  final int protectionScore;
  final String engine;

  factory ServerState.fromJson(Map<String, Object?> j) => ServerState(
    revision: j['revision'] as String,
    settings: Map<String, Object?>.from(j['settings'] as Map),
    blocked: (j['blocked'] as List).cast<String>(),
    messages: [
      for (final m in j['messages'] as List)
        SmsMessage.fromJson(Map<String, Object?>.from(m as Map)),
    ],
    protectionScore: (j['protectionScore'] as num).round(),
    engine: ((j['engine'] as Map)['name'] as String),
  );
}

/// Turns what a person types ("192.168.1.10:8080", "my-server.com") into a
/// server origin, or null if it cannot be one.
Uri? normalizeServerUrl(String input) {
  var text = input.trim();
  if (text.isEmpty) return null;
  if (!text.contains('://')) {
    final host = text.split(RegExp(r'[/:?#]')).first.toLowerCase();
    final local =
        host == 'localhost' ||
        host.endsWith('.local') ||
        RegExp(r'^\d{1,3}(\.\d{1,3}){3}$').hasMatch(host);
    text = '${local ? 'http' : 'https'}://$text';
  }
  final uri = Uri.tryParse(text);
  if (uri == null || !uri.hasAuthority || uri.host.isEmpty) return null;
  if (uri.scheme != 'http' && uri.scheme != 'https') return null;
  return Uri(scheme: uri.scheme, host: uri.host, port: uri.hasPort ? uri.port : null);
}

/// Thin, typed wrapper over the server's JSON API.
class BackendClient {
  BackendClient(this.base, {this.token, http.Client? client})
    : _http = client ?? http.Client();

  final Uri base;
  String? token;
  final http.Client _http;

  static const _timeout = Duration(seconds: 10);

  void close() => _http.close();

  Future<Map<String, Object?>> _send(
    String method,
    String path, {
    Object? body,
    Map<String, String>? query,
    bool auth = true,
  }) async {
    final uri = base.replace(path: path, queryParameters: query);
    final request = http.Request(method, uri)
      ..headers['accept'] = 'application/json';
    if (auth && token != null) request.headers['authorization'] = 'Bearer $token';
    if (body != null) {
      request.headers['content-type'] = 'application/json';
      request.body = jsonEncode(body);
    }
    final http.Response res;
    try {
      res = await http.Response.fromStream(
        await _http.send(request).timeout(_timeout),
      );
    } on TimeoutException {
      throw BackendException('The server took too long to answer.');
    } on Object {
      // SocketException, ClientException (also how browsers report a blocked
      // or failed request) and anything else the transport raises.
      throw BackendException('Cannot reach the server.');
    }
    Map<String, Object?>? json;
    try {
      final decoded = jsonDecode(utf8.decode(res.bodyBytes));
      if (decoded is Map) json = Map<String, Object?>.from(decoded);
    } on FormatException {
      // not JSON
    }
    if (res.statusCode >= 200 && res.statusCode < 300) {
      return json ?? const {};
    }
    throw BackendException(
      (json?['error'] as String?) ?? 'The server returned ${res.statusCode}.',
      status: res.statusCode,
    );
  }

  /// True if [base] is a ThreatGuard server.
  Future<bool> isThreatGuard() async {
    try {
      final j = await _send('GET', '/api/health', auth: false);
      return j['service'] == 'threatguard';
    } on BackendException {
      return false;
    }
  }

  /// Exchanges a one-time pairing code for the API key.
  Future<String> pair(String code) async {
    final j = await _send('POST', '/api/pair', body: {'code': code}, auth: false);
    return j['token'] as String;
  }

  /// Null when [revision] is still current.
  Future<ServerState?> state({String? revision}) async {
    final j = await _send(
      'GET',
      '/api/state',
      query: revision == null ? null : {'rev': revision},
    );
    return j['unchanged'] == true ? null : ServerState.fromJson(j);
  }

  Future<ServerState> scan() async =>
      ServerState.fromJson(await _send('POST', '/api/scan'));

  Future<ServerState> saveSettings(Map<String, Object?> settings) async =>
      ServerState.fromJson(await _send('PUT', '/api/settings', body: settings));

  Future<ServerState> setBlocked(String sender, bool blocked) async =>
      ServerState.fromJson(
        await _send('POST', '/api/blocked', body: {'sender': sender, 'blocked': blocked}),
      );

  Future<ServerState> deleteMessage(int id) async =>
      ServerState.fromJson(await _send('DELETE', '/api/messages/$id'));

  Future<ServerState> clearMessages() async =>
      ServerState.fromJson(await _send('DELETE', '/api/messages'));

  Future<SmsMessage> checkMessage(String sender, String body) async {
    final j = await _send(
      'POST',
      '/api/messages',
      body: {'sender': sender, 'body': body, 'source': 'manual'},
    );
    return SmsMessage.fromJson(j);
  }

  /// Sends messages read from the phone's inbox. Messages the server already
  /// has are ignored, so this is safe to repeat. Returns how many were new.
  Future<int> importMessages(List<InboxSms> messages) async {
    final j = await _send(
      'POST',
      '/api/messages/import',
      body: {'messages': [for (final m in messages) m.toJson()]},
    );
    return (j['added'] as num?)?.toInt() ?? 0;
  }

  /// A fresh one-time code for linking another device.
  Future<String> newPairingCode() async {
    final j = await _send('POST', '/api/pair/new');
    return j['code'] as String;
  }
}
