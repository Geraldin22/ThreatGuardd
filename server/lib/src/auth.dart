import 'dart:convert';
import 'dart:io';
import 'dart:math';

/// Characters that cannot be confused when read aloud or typed on a phone.
const _codeAlphabet = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789';

class PairingCode {
  PairingCode(this.code, this.expiresAt);
  final String code;
  final DateTime expiresAt;
}

/// Owns the API key and the one-time pairing codes.
///
/// The API key is the only credential. A phone obtains it by redeeming a
/// pairing code, so the key itself never has to appear in a URL.
class Auth {
  Auth(this.token, {DateTime Function()? clock}) : _now = clock ?? DateTime.now;

  /// Loads the key from [envToken], else from [dir]/auth.json, else creates
  /// a new one and saves it.
  factory Auth.load({String? dir, String? envToken, DateTime Function()? clock}) {
    if (envToken != null && envToken.isNotEmpty) {
      if (envToken.length < 16) {
        throw ArgumentError('THREATGUARD_TOKEN must be at least 16 characters.');
      }
      return Auth(envToken, clock: clock);
    }
    if (dir == null) return Auth(_randomToken(), clock: clock);
    final file = File('$dir/auth.json');
    if (file.existsSync()) {
      final saved = (jsonDecode(file.readAsStringSync()) as Map)['token'];
      if (saved is String && saved.length >= 16) {
        return Auth(saved, clock: clock);
      }
    }
    final auth = Auth(_randomToken(), clock: clock);
    file.parent.createSync(recursive: true);
    file.writeAsStringSync(jsonEncode({'token': auth.token}));
    return auth;
  }

  static const codeLifetime = Duration(minutes: 10);
  static const maxWrongAttempts = 5;

  final String token;
  final DateTime Function() _now;
  final Map<String, PairingCode> _codes = {};
  int _wrongAttempts = 0;

  static final _random = Random.secure();

  static String _randomToken() => base64Url
      .encode(List.generate(32, (_) => _random.nextInt(256)))
      .replaceAll('=', '');

  /// Comparison time does not depend on where the strings differ.
  static bool _safeEquals(String a, String b) {
    final x = utf8.encode(a), y = utf8.encode(b);
    var diff = x.length ^ y.length;
    for (var i = 0; i < max(x.length, y.length); i++) {
      diff |= (i < x.length ? x[i] : 0) ^ (i < y.length ? y[i] : 0);
    }
    return diff == 0;
  }

  bool isValidToken(String? candidate) =>
      candidate != null && candidate.isNotEmpty && _safeEquals(candidate, token);

  /// Creates a fresh single-use pairing code. Older unused codes stop
  /// working, so there is only ever one live code.
  PairingCode newPairingCode() {
    _codes.clear();
    _wrongAttempts = 0;
    final code = PairingCode(
      List.generate(
        8,
        (_) => _codeAlphabet[_random.nextInt(_codeAlphabet.length)],
      ).join(),
      _now().add(codeLifetime),
    );
    _codes[code.code] = code;
    return code;
  }

  /// Exchanges a pairing code for the API key. A code works once, expires
  /// after [codeLifetime], and is burned after [maxWrongAttempts] wrong tries
  /// so it cannot be guessed.
  String? redeem(String? candidate) {
    if (_codes.isEmpty || candidate == null) return null;
    final live = _codes.values.first;
    if (_now().isAfter(live.expiresAt) || _wrongAttempts >= maxWrongAttempts) {
      _codes.clear();
      return null;
    }
    final normalized = candidate.trim().toUpperCase().replaceAll(RegExp(r'[\s-]'), '');
    if (!_safeEquals(normalized, live.code)) {
      _wrongAttempts++;
      if (_wrongAttempts >= maxWrongAttempts) _codes.clear();
      return null;
    }
    _codes.clear();
    return token;
  }
}
