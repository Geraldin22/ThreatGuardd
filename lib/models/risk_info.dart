import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

enum RiskLevel { low, medium, high }

extension RiskLevelX on RiskLevel {
  Color get color => switch (this) {
    RiskLevel.low => AppColors.green,
    RiskLevel.medium => AppColors.orange,
    RiskLevel.high => AppColors.red,
  };
  Color get pillText =>
      this == RiskLevel.high ? Colors.white : const Color(0xFF0B1230);
  RiskInfo get info => switch (this) {
    RiskLevel.high => _high,
    RiskLevel.medium => _medium,
    RiskLevel.low => _low,
  };
}

class RiskInfo {
  const RiskInfo({
    required this.badge,
    required this.status,
    required this.title,
    required this.dash,
    required this.advice,
    required this.dashColor,
    required this.statusColor,
  });
  final String badge, status, title, dash, advice;
  final Color dashColor;
  final Color statusColor;
}

const _high = RiskInfo(
  badge: 'Blocked',
  status: 'Blocked',
  title: 'High Risk',
  dash: 'Phishing',
  advice: "I blocked this message and disabled its link. Do not reply or share any codes. Delete it, and report it through the real company's official app or website.",
  dashColor: Color(0xFFFFC3C9),
  statusColor: Color(0xFFD93A4B),
);
const _medium = RiskInfo(
  badge: 'Flagged',
  status: 'Flagged',
  title: 'Medium Risk',
  dash: 'Suspicious',
  advice: 'I flagged this message. Do not click anything. Check with the sender using a phone number or website you already trust.',
  dashColor: Color(0xFFFFD9A8),
  statusColor: Color(0xFFC97712),
);
const _low = RiskInfo(
  badge: 'Safe',
  status: 'Allowed',
  title: 'Low Risk',
  dash: 'Safe',
  advice: 'I found no suspicious phrases or links, so this message was delivered normally.',
  dashColor: Color(0xFFB8F0D6),
  statusColor: Color(0xFF1F9D68),
);
