import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../state/guard_state.dart';
import '../theme/app_theme.dart';
import '../widgets/common.dart';
import '../widgets/connection_sheets.dart';
import '../widgets/floating_dock.dart';
import '../widgets/glass_card.dart';
import '../widgets/shield_hero.dart';
import '../widgets/sheets.dart';

class DashboardScreen extends StatelessWidget {
  const DashboardScreen({super.key, required this.onNavigate});
  final ValueChanged<int> onNavigate;

  @override
  Widget build(BuildContext context) {
    final s = context.watch<GuardState>();
    final pad = MediaQuery.paddingOf(context);
    // The shield scales with screen height (about 17% smaller than before on
    // a typical phone) so the dashboard needs less scrolling.
    final heroSize = (MediaQuery.sizeOf(context).height * 0.28)
        .clamp(200.0, 225.0)
        .toDouble();
    return RefreshIndicator(
      color: AppColors.primary,
      backgroundColor: AppColors.surface,
      onRefresh: () => context.read<GuardState>().refresh(),
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: EdgeInsets.fromLTRB(
          AppSpacing.screen,
          pad.top + 12,
          AppSpacing.screen,
          kDockClearance + pad.bottom,
        ),
        children: [
          _TopBar(state: s),
          if (s.demoMode) ...[
            const SizedBox(height: 12),
            const DemoBanner(),
          ],
          const SizedBox(height: 4),
          Center(child: ShieldHero(size: heroSize)),
          _HeroText(state: s),
          const SectionHeader('Scan Results'),
          EqualRow(
            children: [
              _MetricCard(
                icon: Icons.mark_email_read_rounded,
                color: AppColors.primary,
                value: s.messagesScanned,
                label: 'Messages Scanned',
              ),
              _MetricCard(
                icon: Icons.warning_amber_rounded,
                color: AppColors.red,
                value: s.threatCount,
                label: 'Threats Found',
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.gap),
          EqualRow(
            children: [
              _MetricCard(
                icon: Icons.warning_rounded,
                color: AppColors.orange,
                value: s.highRisk,
                label: 'High Risk Messages',
              ),
              _MetricCard(
                icon: Icons.verified_user_rounded,
                color: AppColors.green,
                value: s.safeCount,
                label: 'Safe Messages',
              ),
            ],
          ),
          const SectionHeader('Quick Actions'),
          EqualRow(
            children: [
              _QuickAction(
                icon: Icons.radar_rounded,
                label: 'Run Scan',
                onTap: () => showScanSheet(context),
              ),
              _QuickAction(
                icon: Icons.add_comment_rounded,
                label: 'Check Message',
                onTap: () => showCheckMessageSheet(context),
              ),
              _QuickAction(
                icon: Icons.fact_check_rounded,
                label: 'Security Check',
                onTap: () => showSecurityCheckSheet(context),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _TopBar extends StatelessWidget {
  const _TopBar({required this.state});
  final GuardState state;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(
          width: 42,
          height: 42,
          decoration: const BoxDecoration(
            shape: BoxShape.circle,
            gradient: AppGradients.aurora,
          ),
          child: const Icon(Icons.shield_rounded, size: 22),
        ),
        const SizedBox(width: 12),
        const Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'ThreatGuard AI',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
              ),
              Text(
                'SMS threat protection',
                style: TextStyle(fontSize: 12, color: AppColors.muted),
              ),
            ],
          ),
        ),
        GlassIconButton(
          icon: Icons.notifications_rounded,
          badge: state.activity.isNotEmpty,
          onTap: () => showAlertsSheet(context),
        ),
      ],
    );
  }
}

class _HeroText extends StatelessWidget {
  const _HeroText({required this.state});
  final GuardState state;

  @override
  Widget build(BuildContext context) {
    final status = state.status;
    final score = state.protectionScore;
    return Column(
      children: [
        ShaderMask(
          shaderCallback: (r) => status.gradient.createShader(r),
          child: FittedBox(
            fit: BoxFit.scaleDown,
            child: Text(
              status.label.toUpperCase(),
              maxLines: 1,
              style: const TextStyle(
                fontSize: 34,
                fontWeight: FontWeight.w800,
                letterSpacing: 3,
                color: Colors.white,
              ),
            ),
          ),
        ),
        const SizedBox(height: 10),
        Text(
          status.description,
          textAlign: TextAlign.center,
          style: const TextStyle(
            color: AppColors.muted,
            fontSize: 15,
            height: 1.45,
          ),
        ),
        const SizedBox(height: 16),
        EqualRow(
          gap: 10,
          children: [
            _HeroStat(
              value: score == null ? '—' : '$score%',
              label: 'Protection Score',
              color: score == null ? AppColors.muted : AppColors.green,
            ),
            _HeroStat(
              value: state.engineConnected ? 'ONLINE' : 'OFFLINE',
              label: 'AI Engine',
              color: state.engineConnected ? AppColors.primary : AppColors.muted,
            ),
            _HeroStat(
              value: state.monitoringRunning ? 'ACTIVE' : 'INACTIVE',
              label: 'SMS Monitoring',
              color: state.monitoringRunning
                  ? AppColors.green
                  : AppColors.muted,
            ),
          ],
        ),
        const SizedBox(height: 16),
        SizedBox(
          width: double.infinity,
          child: GradientButton(
            label: 'View Protection Status',
            icon: Icons.verified_user_rounded,
            onPressed: () => showProtectionSheet(context),
          ),
        ),
      ],
    );
  }
}

class _HeroStat extends StatelessWidget {
  const _HeroStat({
    required this.value,
    required this.label,
    required this.color,
  });
  final String value, label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return GlassCard(
      radius: AppRadius.tile,
      padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 10),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          FittedBox(
            fit: BoxFit.scaleDown,
            child: Text(
              value,
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w800,
                color: color,
              ),
            ),
          ),
          const SizedBox(height: 4),
          // Two lines are always reserved so all three cards match.
          SizedBox(
            height: textBlockHeight(context, 11.5),
            child: Align(
              alignment: Alignment.topCenter,
              child: Text(
                label,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontSize: 11.5,
                  height: 1.25,
                  color: AppColors.muted,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _MetricCard extends StatelessWidget {
  const _MetricCard({
    required this.icon,
    required this.color,
    required this.value,
    required this.label,
  });
  final IconData icon;
  final Color color;
  final int value;
  final String label;

  @override
  Widget build(BuildContext context) {
    return GlassCard(
      glow: color,
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ThreatIcon(icon: icon, color: color, size: 40),
          const SizedBox(height: 14),
          CountUp(
            value: value,
            style: const TextStyle(
              fontSize: 30,
              fontWeight: FontWeight.w800,
              height: 1,
            ),
          ),
          const SizedBox(height: 4),
          SizedBox(
            height: textBlockHeight(context, 12),
            child: Text(
              label,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                fontSize: 12,
                height: 1.25,
                color: AppColors.muted,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _QuickAction extends StatelessWidget {
  const _QuickAction({
    required this.icon,
    required this.label,
    required this.onTap,
  });
  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GlassCard(
      radius: AppRadius.tile,
      padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 8),
      onTap: onTap,
      child: Column(
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: const BoxDecoration(
              shape: BoxShape.circle,
              gradient: AppGradients.aurora,
            ),
            child: Icon(icon, size: 22),
          ),
          const SizedBox(height: 10),
          // Fixed two-line slot keeps icons aligned and labels centred.
          SizedBox(
            height: textBlockHeight(context, 12.5),
            child: Center(
              child: Text(
                label,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontSize: 12.5,
                  height: 1.25,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
