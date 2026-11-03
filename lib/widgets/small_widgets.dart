import 'package:flutter/material.dart';

import '../models/risk_info.dart';

class RiskPill extends StatelessWidget {
  const RiskPill({super.key, required this.level, required this.label});
  final RiskLevel level;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      decoration: BoxDecoration(
        color: level.color,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        label,
        maxLines: 1,
        style: TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w700,
          color: level.pillText,
        ),
      ),
    );
  }
}

class UserAvatar extends StatelessWidget {
  const UserAvatar({super.key, required this.name, this.size = 44});
  final String name;
  final double size;

  static const _colors = [
    Color(0xFFE48A2C),
    Color(0xFF4AA3F5),
    Color(0xFF8A6CF0),
    Color(0xFFE0527F),
    Color(0xFF2FB8A0),
    Color(0xFFD9A21B),
  ];

  @override
  Widget build(BuildContext context) {
    var hash = 0;
    for (final ch in name.runes) {
      hash = (hash * 31 + ch) % 997;
    }
    return Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: _colors[hash % _colors.length],
        border: Border.all(
          color: const Color.fromRGBO(255, 255, 255, 0.25),
          width: 3,
        ),
      ),
      child: Text(
        name.isEmpty ? '?' : name.substring(0, 1).toUpperCase(),
        style: const TextStyle(
          fontSize: 18,
          fontWeight: FontWeight.w700,
          color: Colors.white,
        ),
      ),
    );
  }
}
