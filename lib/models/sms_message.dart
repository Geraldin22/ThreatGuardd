import 'package:flutter/material.dart';

import 'risk_info.dart';

enum ThreatCategory {
  banking('Banking Scam', Icons.account_balance),
  delivery('Delivery Scam', Icons.local_shipping),
  otp('OTP Theft', Icons.password),
  crypto('Crypto Scam', Icons.currency_bitcoin),
  government('Government Impersonation', Icons.gavel),
  impersonation('Social Engineering', Icons.person_search),
  recovery('Account Recovery Scam', Icons.manage_accounts),
  safe('Safe', Icons.verified_user);

  const ThreatCategory(this.label, this.icon);
  final String label;
  final IconData icon;
}

enum MessageStatus {
  blocked('Blocked'),
  flagged('Flagged'),
  safe('Safe');

  const MessageStatus(this.label);
  final String label;
}

class SmsMessage {
  const SmsMessage({
    required this.id,
    required this.sender,
    required this.body,
    required this.receivedAt,
    required this.risk,
    required this.category,
    required this.confidence,
    this.url,
  });

  /// Reads a message as the server sends it (see `GET /api/state`).
  factory SmsMessage.fromJson(Map<String, Object?> json) {
    final name = json['category'];
    return SmsMessage(
      id: json['id'] as int,
      sender: json['sender'] as String,
      body: json['body'] as String,
      receivedAt: DateTime.parse(json['receivedAt'] as String).toLocal(),
      risk: (json['risk'] as num).round().clamp(0, 100),
      // An unknown category from a newer server is shown as a generic threat
      // rather than failing the whole list.
      category: ThreatCategory.values.asNameMap()[name] ??
          ThreatCategory.impersonation,
      confidence: (json['confidence'] as num).round().clamp(0, 100),
      url: json['url'] as String?,
    );
  }

  final int id;
  final String sender;
  final String body;
  final DateTime receivedAt;
  final int risk; // 0 - 100
  final ThreatCategory category;
  final int confidence; // 0 - 100
  final String? url;

  RiskLevel get level => risk >= 60
      ? RiskLevel.high
      : risk >= 25
      ? RiskLevel.medium
      : RiskLevel.low;

  MessageStatus get status => switch (level) {
    RiskLevel.high => MessageStatus.blocked,
    RiskLevel.medium => MessageStatus.flagged,
    RiskLevel.low => MessageStatus.safe,
  };

  bool get isThreat => risk >= 25;
  Color get color => level.color;
  int get behaviorMatch => (risk * 0.9).round();
  String get reportId => 'TG-${id.toString().padLeft(5, '0')}';

  String get timeLabel {
    final d = DateTime.now().difference(receivedAt);
    if (d.inSeconds < 45) return 'Just now';
    if (d.inMinutes < 60) return '${d.inMinutes < 1 ? 1 : d.inMinutes}m ago';
    if (d.inHours < 24) return '${d.inHours}h ago';
    return '${d.inDays}d ago';
  }

  String get clock {
    final h = receivedAt.hour % 12 == 0 ? 12 : receivedAt.hour % 12;
    final m = receivedAt.minute.toString().padLeft(2, '0');
    return '$h:$m ${receivedAt.hour >= 12 ? 'PM' : 'AM'}';
  }

  String get activityTitle => switch (category) {
    ThreatCategory.banking => 'Banking phishing attempt blocked',
    ThreatCategory.delivery => 'Suspicious delivery URL detected',
    ThreatCategory.otp => 'OTP theft attempt intercepted',
    ThreatCategory.crypto => 'Crypto wallet scam blocked',
    ThreatCategory.government => 'Government impersonation identified',
    ThreatCategory.impersonation => 'Social engineering campaign identified',
    ThreatCategory.recovery => 'Fake account recovery request flagged',
    ThreatCategory.safe => 'Safe message verified',
  };

  String get verdictSummary => switch (category) {
    ThreatCategory.banking =>
      'Fraudulent banking language and a spoofed login link were identified.',
    ThreatCategory.delivery =>
      'A fake courier notice is pushing you toward a tracking link.',
    ThreatCategory.otp =>
      'This message tries to trick you into sharing a one-time code.',
    ThreatCategory.crypto =>
      'A wallet-recovery lure aimed at stealing crypto credentials.',
    ThreatCategory.government =>
      'The sender poses as a government agency to demand payment.',
    ThreatCategory.impersonation =>
      'Social engineering from someone posing as trusted staff.',
    ThreatCategory.recovery =>
      'A fake account recovery request designed to steal credentials.',
    ThreatCategory.safe =>
      'No scam patterns, risky links or manipulation were detected.',
  };
}
