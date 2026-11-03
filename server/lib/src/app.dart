import 'dart:convert';
import 'dart:io';

import 'package:shelf/shelf.dart';
import 'package:shelf_router/shelf_router.dart';
import 'package:shelf_static/shelf_static.dart';

import 'auth.dart';
import 'store.dart';

const serviceName = 'threatguard';
const serverVersion = '1.0.0';
const engineName = 'rules-1.0';

const _maxRequestBytes = 64 * 1024;
const _maxImportBytes = 512 * 1024;
const maxImportBatch = 200;

class ApiError implements Exception {
  ApiError(this.status, this.message);
  final int status;
  final String message;
}

Response _json(Object? body, {int status = 200}) => Response(
  status,
  body: jsonEncode(body),
  headers: {'content-type': 'application/json; charset=utf-8'},
);

Future<Map<String, Object?>> _readJson(
  Request request, {
  int maxBytes = _maxRequestBytes,
}) async {
  final declared = request.contentLength;
  if (declared != null && declared > maxBytes) {
    throw ApiError(413, 'Request is too large.');
  }
  final bytes = <int>[];
  await for (final chunk in request.read()) {
    bytes.addAll(chunk);
    if (bytes.length > maxBytes) {
      throw ApiError(413, 'Request is too large.');
    }
  }
  try {
    final value = jsonDecode(utf8.decode(bytes));
    if (value is Map) return Map<String, Object?>.from(value);
  } on FormatException {
    // fall through
  }
  throw ApiError(400, 'Request body must be a JSON object.');
}

String _text(
  Map<String, Object?> body,
  String key, {
  required int max,
  bool required = false,
  String fallback = '',
}) {
  final v = body[key];
  if (v == null && !required) return fallback;
  if (v is! String) throw ApiError(400, '"$key" must be text.');
  final trimmed = v.trim();
  if (required && trimmed.isEmpty) throw ApiError(400, '"$key" is required.');
  if (v.length > max) throw ApiError(400, '"$key" is longer than $max characters.');
  return trimmed.isEmpty ? fallback : trimmed;
}

/// Builds the whole server: JSON API under /api, then the web app (if
/// [webDir] exists) for everything else.
Handler buildApp({
  required Store store,
  required Auth auth,
  String? webDir,
  void Function(String line)? log,
}) {
  Map<String, Object?> statePayload() => {
    'revision': store.revision,
    'unchanged': false,
    'settings': store.settings.toJson(),
    'protectionScore': store.settings.protectionScore,
    'monitoring': store.settings.monitoring,
    'blocked': store.blocked,
    'messages': [for (final m in store.messages) m.toJson()],
    'engine': {'name': engineName, 'version': serverVersion},
  };

  Handler authed(Future<Response> Function(Request r) next) => (request) {
    final header = request.headers['authorization'];
    final bearer = header != null && header.toLowerCase().startsWith('bearer ')
        ? header.substring(7).trim()
        : null;
    final key = bearer ?? request.headers['x-api-key'];
    if (!auth.isValidToken(key)) {
      return _json({'error': 'Missing or invalid API key.'}, status: 401);
    }
    return next(request);
  };

  final api = Router()
    ..get('/api/health', (Request r) {
      return _json({
        'ok': true,
        'service': serviceName,
        'version': serverVersion,
        'engine': engineName,
      });
    })
    ..post('/api/pair', (Request r) async {
      final body = await _readJson(r);
      final token = auth.redeem(body['code'] is String ? body['code'] as String : null);
      if (token == null) {
        return _json(
          {'error': 'That pairing code is wrong, expired or already used.'},
          status: 403,
        );
      }
      return _json({'token': token});
    })
    ..post('/api/pair/new', authed((r) async {
      final code = auth.newPairingCode();
      return _json({
        'code': code.code,
        'expiresAt': code.expiresAt.toUtc().toIso8601String(),
      });
    }))
    ..get('/api/state', authed((r) async {
      if (r.url.queryParameters['rev'] == store.revision) {
        return _json({'revision': store.revision, 'unchanged': true});
      }
      return _json(statePayload());
    }))
    ..post('/api/analyze', authed((r) async {
      final body = await _readJson(r);
      final text = _text(body, 'text', max: maxBodyLength, required: true);
      return _json(store.analyze(text).toJson());
    }))
    ..post('/api/messages', authed((r) async {
      final body = await _readJson(r);
      final text = _text(body, 'body', max: maxBodyLength, required: true);
      final sender = _text(body, 'sender', max: maxSenderLength, fallback: 'Unknown');
      // 'manual' = checked by hand in the app, 'device' = read from the
      // phone's own inbox, anything else = a forwarder.
      final source = switch (body['source']) {
        'manual' => 'manual',
        'device' => 'device',
        _ => 'forward',
      };

      // Messages that arrive on their own are ignored while monitoring is
      // off. Messages the user checks by hand always work.
      if (!store.settings.monitoring && source != 'manual') {
        return _json({'ignored': true, 'reason': 'monitoring_off'}, status: 202);
      }

      DateTime? at;
      if (body['receivedAt'] != null) {
        at = body['receivedAt'] is String
            ? DateTime.tryParse(body['receivedAt'] as String)?.toUtc()
            : null;
        if (at == null) throw ApiError(400, '"receivedAt" must be an ISO-8601 time.');
        final now = DateTime.now().toUtc();
        if (at.isAfter(now)) at = now;
      }
      final (msg, :created) = store.add(
        sender: sender,
        body: text,
        source: source,
        receivedAt: at,
      );
      // 200 (not 201) tells a retrying sender it was already stored.
      return _json(msg.toJson(), status: created ? 201 : 200);
    }))
    ..post('/api/messages/import', authed((r) async {
      // Bulk load from a phone's inbox. The user asked for it, so it works
      // even while monitoring is off. Messy rows are skipped, not fatal.
      final body = await _readJson(r, maxBytes: _maxImportBytes);
      final raw = body['messages'];
      if (raw is! List) throw ApiError(400, '"messages" must be a list.');
      if (raw.length > maxImportBatch) {
        throw ApiError(400, 'Send at most $maxImportBatch messages at a time.');
      }
      final now = DateTime.now().toUtc();
      final items = <({String sender, String body, DateTime at})>[];
      var skipped = 0;
      for (final row in raw) {
        if (row is! Map || row['body'] is! String || row['receivedAt'] is! String) {
          skipped++;
          continue;
        }
        var text = (row['body'] as String).trim();
        var at = DateTime.tryParse(row['receivedAt'] as String)?.toUtc();
        if (text.isEmpty || at == null) {
          skipped++;
          continue;
        }
        if (text.length > maxBodyLength) text = text.substring(0, maxBodyLength);
        if (at.isAfter(now)) at = now;
        var sender = row['sender'] is String ? (row['sender'] as String).trim() : '';
        if (sender.isEmpty) sender = 'Unknown';
        if (sender.length > maxSenderLength) sender = sender.substring(0, maxSenderLength);
        items.add((sender: sender, body: text, at: at));
      }
      final added = store.addAll(items, source: 'device');
      return _json({
        'added': added,
        'duplicates': items.length - added,
        'skipped': skipped,
        'revision': store.revision,
      });
    }))
    ..delete('/api/messages', authed((r) async {
      return _json({'deleted': store.clear(), ...statePayload()});
    }))
    ..delete('/api/messages/<id>', (Request r, String id) {
      return authed((r) async {
        final n = int.tryParse(id);
        if (n == null || !store.delete(n)) {
          throw ApiError(404, 'No such message.');
        }
        return _json(statePayload());
      })(r);
    })
    ..post('/api/scan', authed((r) async {
      store.reanalyze();
      return _json(statePayload());
    }))
    ..get('/api/settings', authed((r) async {
      return _json({
        'settings': store.settings.toJson(),
        'protectionScore': store.settings.protectionScore,
      });
    }))
    ..put('/api/settings', authed((r) async {
      final patch = await _readJson(r);
      final problem = store.settings.validate(patch);
      if (problem != null) throw ApiError(400, problem);
      store.updateSettings(patch);
      return _json(statePayload());
    }))
    ..post('/api/blocked', authed((r) async {
      final body = await _readJson(r);
      final sender = _text(body, 'sender', max: maxSenderLength, required: true);
      if (body['blocked'] is! bool) {
        throw ApiError(400, '"blocked" must be true or false.');
      }
      store.setBlocked(sender, body['blocked'] as bool);
      store.reanalyze(); // refresh each message's allow/flag/block action
      return _json(statePayload());
    }))
    ..all('/api/<rest|.*>', (Request r) {
      return _json({'error': 'Not found.'}, status: 404);
    });

  Handler root = api.call;

  final dir = webDir == null ? null : Directory(webDir);
  if (dir != null && dir.existsSync()) {
    final files = createStaticHandler(dir.path, defaultDocument: 'index.html');
    final index = File('${dir.path}/index.html');
    root = (request) async {
      if (request.url.path.startsWith('api/')) return api(request);
      final res = await files(request);
      // Unknown paths belong to the single-page app.
      if (res.statusCode == 404 && request.method == 'GET' && index.existsSync()) {
        return Response.ok(
          index.openRead(),
          headers: {'content-type': 'text/html; charset=utf-8'},
        );
      }
      return res;
    };
  }

  return const Pipeline()
      .addMiddleware(_errors(log))
      .addMiddleware(_headers)
      .addMiddleware(_requestLog(log))
      .addHandler(root);
}

// --------------------------------------------------------------- middleware

Middleware _errors(void Function(String)? log) => (inner) => (request) async {
  try {
    return await inner(request);
  } on ApiError catch (e) {
    return _json({'error': e.message}, status: e.status);
  } catch (e) {
    log?.call('ERROR ${request.method} ${request.url.path}: $e');
    return _json({'error': 'Something went wrong on the server.'}, status: 500);
  }
};

/// CORS for the API (the key travels in a header, never a cookie, so a
/// foreign page cannot ride on a signed-in session), plus safe defaults.
Handler _headers(Handler inner) => (request) async {
  final isApi = request.url.path.startsWith('api/');
  if (isApi && request.method == 'OPTIONS') {
    return Response(204, headers: _corsHeaders);
  }
  final res = await inner(request);
  return res.change(
    headers: {
      'x-content-type-options': 'nosniff',
      'referrer-policy': 'no-referrer',
      if (isApi) ..._corsHeaders,
      if (isApi) 'cache-control': 'no-store',
    },
  );
};

const _corsHeaders = {
  'access-control-allow-origin': '*',
  'access-control-allow-methods': 'GET, POST, PUT, DELETE, OPTIONS',
  'access-control-allow-headers': 'authorization, content-type, x-api-key',
  'access-control-max-age': '600',
};

/// Logs method, path and status. Never the body, query string or headers,
/// which can hold message text, pairing codes and keys.
Middleware _requestLog(void Function(String)? log) => (inner) => (request) async {
  final sw = Stopwatch()..start();
  final res = await inner(request);
  log?.call(
    '${request.method} /${request.url.path} ${res.statusCode} ${sw.elapsedMilliseconds}ms',
  );
  return res;
};
