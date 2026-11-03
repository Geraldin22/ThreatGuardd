import 'risk_info.dart';

class SignalHit {
  const SignalHit(this.label, this.why);
  final String label, why;
}

class ScanResult {
  const ScanResult({
    required this.score,
    required this.level,
    required this.hits,
  });
  final int score;
  final RiskLevel level;
  final List<SignalHit> hits;
}

class InboxMessage {
  const InboxMessage({
    required this.id,
    required this.sender,
    required this.channel,
    required this.body,
    required this.time,
    required this.result,
  });

  final int id;
  final String sender, channel, body, time;
  final ScanResult result;

  String get threatType => result.level == RiskLevel.high && channel == 'SMS'
      ? 'Smishing'
      : result.level.info.dash;

  String get excerpt {
    final flat = body.replaceAll(RegExp(r'\s+'), ' ').trim();
    return flat.length > 48 ? '"${flat.substring(0, 45)}..."' : '"$flat"';
  }
}
