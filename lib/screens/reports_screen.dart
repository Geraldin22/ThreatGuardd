import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../state/guard_state.dart';
import '../theme/app_theme.dart';
import '../widgets/charts.dart';
import '../widgets/common.dart';
import '../widgets/floating_dock.dart';
import '../widgets/glass_card.dart';

class ReportsScreen extends StatefulWidget {
  const ReportsScreen({super.key});

  @override
  State<ReportsScreen> createState() => _ReportsScreenState();
}

class _ReportsScreenState extends State<ReportsScreen> {
  int _period = 0;

  @override
  Widget build(BuildContext context) {
    final s = context.watch<GuardState>();
    final pad = MediaQuery.paddingOf(context);
    final demo = s.demoMode;

    // Real mode: every number comes from the analyzed messages. Today and the
    // last 7 days are computed from their timestamps. The 30-day view is
    // still labelled demo data only.
    final period = demo || _period < 2 ? _period : 1;
    final labels = switch (period) {
      0 => dayHourLabels(),
      1 => s.weekLabels,
      _ => const ['1-5', '6-10', '11-15', '16-20', '21-25', '26-30'],
    };
    final values = switch (period) {
      0 => s.dailyTrend,
      1 => s.weeklyTrend,
      _ => const [38, 52, 44, 61, 57, 70],
    };
    final scanned = !demo
        ? s.messagesScanned
        : switch (_period) {
            0 => s.messagesScanned,
            1 => 8420,
            _ => 36150,
          };
    final threats = !demo || _period == 0
        ? s.threatCount
        : values.fold<int>(0, (a, b) => a + b);
    final safe = scanned > threats ? scanned - threats : 0;
    final periodName = !demo
        ? 'All analyzed messages'
        : const ['Today', 'Last 7 days', 'Last 30 days'][_period];
    final top = s.categoryCounts.take(4).toList();
    final maxTop = top.isEmpty ? 1 : top.first.value;

    return ListView(
      padding: EdgeInsets.fromLTRB(
        AppSpacing.screen,
        pad.top + 16,
        AppSpacing.screen,
        kDockClearance + pad.bottom,
      ),
      children: [
        const ScreenHeader(
          title: 'Reports',
          subtitle: 'Your protection at a glance',
        ),
        if (demo) const DemoBanner(),
        if (demo || s.hasMessages) ...[
          PillTabs(
            labels: demo
                ? const ['Today', '7 Days', '30 Days']
                : const ['Today', '7 Days'],
            index: period,
            expand: true,
            onChanged: (i) => setState(() => _period = i),
          ),
          const SizedBox(height: 18),
        ],
        if (!s.hasMessages)
          const EmptyStateCard(
            icon: Icons.insights_rounded,
            color: AppColors.muted,
            title: 'No report data yet',
            message:
                'Reports appear after ThreatGuard has analyzed messages. Nothing has been scanned yet.',
          )
        else ...[
          GlassCard(
            glow: AppColors.primary,
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  periodName,
                  style: const TextStyle(color: AppColors.muted, fontSize: 13),
                ),
                const SizedBox(height: 6),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: _BigNumber(
                        value: '$threats',
                        label: 'Threats found',
                        color: AppColors.red,
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: _BigNumber(
                        value: '$scanned',
                        label: 'Messages scanned',
                        color: AppColors.primary,
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: _BigNumber(
                        value: '$safe',
                        label: 'Safe messages',
                        color: AppColors.green,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SectionHeader('Threat Activity'),
          GlassCard(
            padding: const EdgeInsets.all(18),
            child: SizedBox(
              height: 170,
              child: AnimatedSwitcher(
                duration: const Duration(milliseconds: 300),
                child: TrendBars(
                  key: ValueKey(period),
                  values: values,
                  labels: labels,
                ),
              ),
            ),
          ),
          const SectionHeader('Top Threat Types'),
          GlassCard(
            padding: const EdgeInsets.all(18),
            child: Column(
              children: [
                if (top.isEmpty)
                  const Text(
                    'No threats found in the analyzed messages.',
                    style: TextStyle(color: AppColors.muted),
                  ),
                for (final e in top)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    child: Column(
                      children: [
                        Row(
                          children: [
                            Expanded(
                              child: Text(
                                e.key.label,
                                style: const TextStyle(
                                  fontSize: 14,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                            Text(
                              '${e.value}',
                              style: const TextStyle(
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        ClipRRect(
                          borderRadius: BorderRadius.circular(5),
                          child: Stack(
                            children: [
                              Container(
                                height: 7,
                                color: AppColors.white(0.08),
                              ),
                              FractionallySizedBox(
                                widthFactor: e.value / maxTop,
                                child: Container(
                                  height: 7,
                                  decoration: const BoxDecoration(
                                    gradient: AppGradients.aurora,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 22),
          GradientButton(
            label: 'Export report',
            icon: Icons.ios_share_rounded,
            onPressed: () async {
              final text =
                  'ThreatGuard AI report ($periodName)'
                  '${demo ? ' - DEMO DATA, not from this device' : ''}\n'
                  'Threats found: $threats\n'
                  'Messages scanned: $scanned\n'
                  'Safe messages: $safe\n'
                  'Top threats: ${top.map((e) => '${e.key.label} (${e.value})').join(', ')}';
              await Clipboard.setData(ClipboardData(text: text));
              if (context.mounted) {
                showToast(context, 'Report copied to clipboard');
              }
            },
          ),
        ],
      ],
    );
  }
}

class _BigNumber extends StatelessWidget {
  const _BigNumber({
    required this.value,
    required this.label,
    required this.color,
  });
  final String value, label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        FittedBox(
          fit: BoxFit.scaleDown,
          alignment: Alignment.centerLeft,
          child: Text(
            value,
            style: TextStyle(
              fontSize: 26,
              fontWeight: FontWeight.w800,
              color: color,
            ),
          ),
        ),
        Text(
          label,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(
            fontSize: 12,
            height: 1.25,
            color: AppColors.muted,
          ),
        ),
      ],
    );
  }
}
