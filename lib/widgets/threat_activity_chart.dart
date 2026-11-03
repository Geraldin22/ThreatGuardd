import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

/// Threat Activity bar chart (Reports screen).
///
/// WHY THIS CANNOT OVERFLOW: no height is ever calculated or estimated here.
/// Every column is a Flutter flex layout. The two text lines (value and time
/// label) take whatever height the font really needs, and the bar and the
/// empty space above it share the remaining room by flex. The children can
/// never add up to more than the space they are given, at any font, display
/// size or text scale.
///
/// Same inputs as the old `TrendBars`: [values] and [labels] (equal length).
class ThreatActivityChart extends StatelessWidget {
  const ThreatActivityChart({
    super.key,
    required this.values,
    required this.labels,
  });

  final List<int> values;
  final List<String> labels;

  @override
  Widget build(BuildContext context) {
    var maxV = 1;
    for (final v in values) {
      if (v > maxV) maxV = v;
    }
    final last = values.length - 1;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (var i = 0; i < values.length; i++)
          Expanded(
            child: _ActivityColumn(
              value: values[i],
              label: i < labels.length ? labels[i] : '',
              fraction: (values[i] / maxV).clamp(0.04, 1.0).toDouble(),
              highlighted: i == last,
            ),
          ),
      ],
    );
  }
}

class _ActivityColumn extends StatelessWidget {
  const _ActivityColumn({
    required this.value,
    required this.label,
    required this.fraction,
    required this.highlighted,
  });

  final int value;
  final String label;
  final double fraction; // 0.04 – 1.0
  final bool highlighted;

  @override
  Widget build(BuildContext context) {
    final barFlex = (fraction * 1000).round().clamp(1, 1000).toInt();
    final emptyFlex = 1000 - barFlex;
    return Column(
      children: [
        // Everything above the label shares exactly the leftover height.
        Expanded(
          child: Column(
            children: [
              if (emptyFlex > 0)
                Expanded(flex: emptyFlex, child: const SizedBox.shrink()),
              Text(
                '$value',
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  color: highlighted ? AppColors.text : AppColors.muted,
                ),
              ),
              const SizedBox(height: 4),
              Expanded(
                flex: barFlex,
                child: Container(
                  width: 16,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(8),
                    gradient: highlighted ? AppGradients.aurora : null,
                    color: highlighted ? null : AppColors.white(0.14),
                  ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 8),
        Text(
          label,
          maxLines: 1,
          style: const TextStyle(fontSize: 11, color: AppColors.muted),
        ),
      ],
    );
  }
}
