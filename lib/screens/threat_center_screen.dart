import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../state/guard_state.dart';
import '../theme/app_theme.dart';
import '../widgets/common.dart';
import '../widgets/floating_dock.dart';
import '../widgets/glass_card.dart';

/// The 18 detection categories, grouped so the screen stays scannable.
/// Nothing was removed: every original category appears in exactly one group.
class _CoverageGroup {
  const _CoverageGroup(this.title, this.icon, this.items);
  final String title;
  final IconData icon;
  final List<String> items;
}

const _groups = <_CoverageGroup>[
  _CoverageGroup('Financial & Banking Threats', Icons.account_balance_rounded, [
    'Banking scams',
    'Account recovery scams',
    'Crypto scams',
    'Parcel delivery scams',
  ]),
  _CoverageGroup('Phishing & Malicious Links', Icons.link_rounded, [
    'Phishing',
    'Smishing',
    'Malicious links',
    'URL obfuscation',
    'Fake verification scams',
  ]),
  _CoverageGroup('Identity & Credential Threats', Icons.badge_rounded, [
    'Credential theft',
    'OTP theft',
    'Identity impersonation',
  ]),
  _CoverageGroup('Social Engineering & Impersonation', Icons.groups_rounded, [
    'Social engineering',
    'Business impersonation',
    'Government impersonation',
    'Psychological manipulation',
    'Urgency-based scams',
  ]),
  _CoverageGroup('Other Supported Categories', Icons.auto_awesome_rounded, [
    'AI-generated campaigns',
  ]),
];

class ThreatCenterScreen extends StatelessWidget {
  const ThreatCenterScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final s = context.watch<GuardState>();
    final pad = MediaQuery.paddingOf(context);
    final hasData = s.hasMessages;
    final elevated = hasData && s.highRisk >= 3;
    final levelColor = !hasData
        ? AppColors.muted
        : elevated
        ? AppColors.orange
        : AppColors.green;
    final senders = s.blockedSenders;

    return ListView(
      padding: EdgeInsets.fromLTRB(
        AppSpacing.screen,
        pad.top + 16,
        AppSpacing.screen,
        kDockClearance + pad.bottom,
      ),
      children: [
        const ScreenHeader(
          title: 'Threat Center',
          subtitle: 'What ThreatGuard found',
        ),
        if (s.demoMode) const DemoBanner(),
        GlassCard(
          glow: levelColor,
          padding: const EdgeInsets.all(20),
          child: Row(
            children: [
              ThreatIcon(
                icon: Icons.public_rounded,
                color: levelColor,
                size: 52,
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Current threat level',
                      style: TextStyle(color: AppColors.muted, fontSize: 13),
                    ),
                    Text(
                      !hasData
                          ? 'No data yet'
                          : elevated
                          ? 'Elevated'
                          : 'Low',
                      style: TextStyle(
                        fontSize: 26,
                        fontWeight: FontWeight.w800,
                        color: levelColor,
                      ),
                    ),
                    Text(
                      !hasData
                          ? 'Scan your messages to see your threat level.'
                          : elevated
                          ? 'Several high-risk messages were found.'
                          : 'Few high-risk messages were found.',
                      style: const TextStyle(
                        color: AppColors.muted,
                        fontSize: 13,
                        height: 1.3,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        const SectionHeader('Detection Coverage'),
        const Padding(
          padding: EdgeInsets.fromLTRB(4, 0, 4, 10),
          child: Text(
            'Categories ThreatGuard is designed to recognise. The engine is rule-based: it is strongest on banking, delivery, one-time-code, crypto, government, account-recovery and impersonation scams.',
            style: TextStyle(color: AppColors.muted, fontSize: 12, height: 1.35),
          ),
        ),
        GlassCard(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
          child: Column(
            children: [
              for (var i = 0; i < _groups.length; i++) ...[
                if (i > 0) Container(height: 1, color: AppColors.white(0.08)),
                _CoverageGroupTile(group: _groups[i], initiallyOpen: i == 0),
              ],
            ],
          ),
        ),
        // Only shown when real blocking exists on the device.
        if (s.blockingAvailable) ...[
          SectionHeader('Blocked Senders  ·  ${senders.length}'),
          if (senders.isEmpty)
            const GlassCard(
              child: Center(
                child: Text(
                  'No blocked senders yet.',
                  style: TextStyle(color: AppColors.muted),
                ),
              ),
            ),
          for (final name in senders)
            Padding(
              padding: const EdgeInsets.only(bottom: AppSpacing.gap),
              child: GlassCard(
                radius: AppRadius.tile,
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                child: ConstrainedBox(
                  // Same row height whether it ends in a pill or "Unblock".
                  constraints: const BoxConstraints(minHeight: 34),
                  child: Row(
                    children: [
                      const Icon(
                        Icons.block_rounded,
                        size: 20,
                        color: AppColors.red,
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontWeight: FontWeight.w700,
                            fontSize: 14.5,
                          ),
                        ),
                      ),
                      const SizedBox(width: 10),
                      if (s.isManuallyBlocked(name))
                        InkWell(
                          borderRadius: BorderRadius.circular(12),
                          onTap: () {
                            context.read<GuardState>().unblockSender(name);
                            showToast(context, '$name unblocked');
                          },
                          child: const Padding(
                            // Padding only enlarges the touch target.
                            padding: EdgeInsets.symmetric(
                              horizontal: 10,
                              vertical: 8,
                            ),
                            child: Text(
                              'Unblock',
                              style: TextStyle(
                                color: AppColors.primary,
                                fontWeight: FontWeight.w700,
                                fontSize: 13,
                              ),
                            ),
                          ),
                        )
                      else
                        const StatusPill(
                          label: 'Auto-blocked',
                          color: AppColors.muted,
                        ),
                    ],
                  ),
                ),
              ),
            ),
        ],
      ],
    );
  }
}

/// One expandable group of detection categories.
class _CoverageGroupTile extends StatefulWidget {
  const _CoverageGroupTile({required this.group, this.initiallyOpen = false});
  final _CoverageGroup group;
  final bool initiallyOpen;

  @override
  State<_CoverageGroupTile> createState() => _CoverageGroupTileState();
}

class _CoverageGroupTileState extends State<_CoverageGroupTile> {
  late bool _open = widget.initiallyOpen;

  @override
  Widget build(BuildContext context) {
    final g = widget.group;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: () => setState(() => _open = !_open),
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 60),
            child: Row(
              children: [
                ThreatIcon(icon: g.icon, color: AppColors.primary, size: 36),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    g.title,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontWeight: FontWeight.w700,
                      fontSize: 14.5,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  '${g.items.length}',
                  style: const TextStyle(
                    color: AppColors.muted,
                    fontWeight: FontWeight.w700,
                    fontSize: 13,
                  ),
                ),
                const SizedBox(width: 4),
                AnimatedRotation(
                  turns: _open ? 0.5 : 0,
                  duration: const Duration(milliseconds: 220),
                  child: const Icon(
                    Icons.keyboard_arrow_down_rounded,
                    color: AppColors.muted,
                  ),
                ),
              ],
            ),
          ),
        ),
        AnimatedSize(
          duration: const Duration(milliseconds: 240),
          curve: Curves.easeOutCubic,
          alignment: Alignment.topCenter,
          child: _open
              ? Padding(
                  padding: const EdgeInsets.only(top: 2, bottom: 14),
                  child: Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      for (final label in g.items)
                        StatusPill(
                          label: label,
                          color: AppColors.primary,
                          icon: Icons.check_rounded,
                        ),
                    ],
                  ),
                )
              : const SizedBox(width: double.infinity),
        ),
      ],
    );
  }
}
