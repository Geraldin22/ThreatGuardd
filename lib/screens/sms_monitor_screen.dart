import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../models/sms_message.dart';
import '../state/guard_state.dart';
import '../theme/app_theme.dart';
import '../widgets/common.dart';
import '../widgets/floating_dock.dart';
import '../widgets/connection_sheets.dart';
import '../widgets/glass_card.dart';
import '../widgets/sheets.dart';
import 'analysis_summary_screen.dart';

class SmsMonitorScreen extends StatefulWidget {
  const SmsMonitorScreen({super.key});

  @override
  State<SmsMonitorScreen> createState() => _SmsMonitorScreenState();
}

class _SmsMonitorScreenState extends State<SmsMonitorScreen> {
  int _filter = 0;
  String _query = '';
  static const _filters = ['All', 'Threats', 'Flagged', 'Safe'];

  List<SmsMessage> _apply(List<SmsMessage> all) {
    final q = _query.trim().toLowerCase();
    return all.where((m) {
      final okFilter = switch (_filter) {
        1 => m.risk >= 60,
        2 => m.risk >= 25 && m.risk < 60,
        3 => m.risk < 25,
        _ => true,
      };
      final okQuery =
          q.isEmpty ||
          m.sender.toLowerCase().contains(q) ||
          m.body.toLowerCase().contains(q);
      return okFilter && okQuery;
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    final s = context.watch<GuardState>();
    final pad = MediaQuery.paddingOf(context);
    final list = _apply(s.messages);

    return RefreshIndicator(
      color: AppColors.primary,
      backgroundColor: AppColors.surface,
      onRefresh: () => context.read<GuardState>().refresh(),
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
        padding: EdgeInsets.fromLTRB(
          AppSpacing.screen,
          pad.top + 16,
          AppSpacing.screen,
          kDockClearance + pad.bottom,
        ),
        children: [
          ScreenHeader(
            title: 'SMS Monitor',
            subtitle: 'SMS threat analysis',
            trailing: StatusPill(
              label: s.status.shortLabel,
              color: s.status.color,
              dot: true,
            ),
          ),
          if (s.demoMode) const DemoBanner(),
          GlassCard(
            padding: const EdgeInsets.symmetric(vertical: 16),
            child: Row(
              children: [
                _Stat(value: s.messagesScanned, label: 'Scanned'),
                _Stat(
                  value: s.threatCount,
                  label: 'Threats',
                  color: AppColors.red,
                ),
                _Stat(value: s.safeCount, label: 'Safe', color: AppColors.green),
                // Only shown when real blocking exists on the device.
                if (s.blockingAvailable)
                  _Stat(
                    value: s.blockedSenders.length,
                    label: 'Blocked',
                    color: AppColors.orange,
                  ),
              ],
            ),
          ),
          const SizedBox(height: AppSpacing.gapLg),
          if (!s.hasMessages)
            _SmsEmptyState(state: s)
          else ...[
            Row(
              children: [
                Expanded(
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 14),
                    decoration: BoxDecoration(
                      color: AppColors.white(0.07),
                      borderRadius: BorderRadius.circular(AppRadius.pill),
                      border: Border.all(color: AppColors.white(0.12)),
                    ),
                    child: TextField(
                      onChanged: (v) => setState(() => _query = v),
                      textInputAction: TextInputAction.search,
                      autocorrect: false,
                      onTapOutside: (_) =>
                          FocusManager.instance.primaryFocus?.unfocus(),
                      style: const TextStyle(fontSize: 15),
                      cursorColor: AppColors.primary,
                      decoration: const InputDecoration(
                        border: InputBorder.none,
                        isDense: true,
                        hintText: 'Search messages',
                        hintStyle: TextStyle(color: AppColors.muted),
                        prefixIcon: Icon(
                          Icons.search_rounded,
                          color: AppColors.muted,
                        ),
                        contentPadding: EdgeInsets.symmetric(vertical: 14),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                _AddButton(onTap: () => showCheckMessageSheet(context)),
                const SizedBox(width: 10),
                _ScanButton(onTap: () => showScanSheet(context)),
              ],
            ),
            const SizedBox(height: 14),
            PillTabs(
              labels: _filters,
              index: _filter,
              expand: true,
              onChanged: (i) => setState(() => _filter = i),
            ),
            const SizedBox(height: 14),
            if (list.isEmpty)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 40),
                child: Center(
                  child: Text(
                    'No messages match.',
                    style: TextStyle(color: AppColors.muted),
                  ),
                ),
              ),
            for (final m in list)
              Padding(
                padding: const EdgeInsets.only(bottom: AppSpacing.gap),
                child: _SmsCard(
                  key: ValueKey(m.id),
                  message: m,
                  blocked: s.isBlocked(m.sender),
                ),
              ),
          ],
        ],
      ),
    );
  }
}

/// What the Monitor shows instead of a message list when there is no data.
class _SmsEmptyState extends StatelessWidget {
  const _SmsEmptyState({required this.state});
  final GuardState state;

  @override
  Widget build(BuildContext context) {
    final demoButton = GhostButton(
      label: 'Load demo messages',
      icon: Icons.science_rounded,
      onPressed: () => state.setDemoMode(true),
    );
    return switch (state.smsPermission) {
      SmsPermission.unsupported => const EmptyStateCard(
        icon: Icons.block_rounded,
        color: AppColors.muted,
        title: 'Not supported',
        message: 'Scanning is not available on this device or platform.',
      ),
      SmsPermission.notGranted => EmptyStateCard(
        icon: state.backendStatus == BackendStatus.unreachable
            ? Icons.cloud_off_rounded
            : Icons.link_rounded,
        color: AppColors.orange,
        title: state.backendStatus == BackendStatus.unreachable
            ? 'Server not reachable'
            : 'Connect to your server',
        message: state.backendStatus == BackendStatus.unreachable
            ? 'ThreatGuard cannot reach your server right now. It keeps trying in the background.'
            : 'ThreatGuard analyzes your messages on your own server. Connect this device to it. No messages have been scanned.',
        actions: [
          GradientButton(
            label: 'Connect to server',
            icon: Icons.link_rounded,
            onPressed: () => requestSmsAccess(context),
          ),
          demoButton,
        ],
      ),
      SmsPermission.granted => EmptyStateCard(
        icon: Icons.mark_email_unread_rounded,
        title: 'No messages yet',
        message:
            'Paste a suspicious message to check it, or forward your texts to the server to have them analyzed as they arrive.',
        actions: [
          // On Android the natural next step is letting the app read texts.
          if (state.deviceSms == DeviceSmsAccess.notGranted)
            GradientButton(
              label: 'Allow SMS access',
              icon: Icons.sms_rounded,
              onPressed: () => showSmsAccessSheet(context),
            ),
          state.deviceSms == DeviceSmsAccess.notGranted
              ? GhostButton(
                  label: 'Check a message',
                  icon: Icons.add_comment_rounded,
                  onPressed: () => showCheckMessageSheet(context),
                )
              : GradientButton(
                  label: 'Check a message',
                  icon: Icons.add_comment_rounded,
                  onPressed: () => showCheckMessageSheet(context),
                ),
          GhostButton(
            label: 'Scan now',
            icon: Icons.radar_rounded,
            onPressed: () => showScanSheet(context),
          ),
          demoButton,
        ],
      ),
    };
  }
}

class _Stat extends StatelessWidget {
  const _Stat({required this.value, required this.label, this.color});
  final int value;
  final String label;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Column(
        children: [
          CountUp(
            value: value,
            style: TextStyle(
              fontSize: 24,
              fontWeight: FontWeight.w800,
              color: color ?? AppColors.text,
            ),
          ),
          Text(
            label,
            style: const TextStyle(fontSize: 12, color: AppColors.muted),
          ),
        ],
      ),
    );
  }
}

class _SmsCard extends StatelessWidget {
  const _SmsCard({super.key, required this.message, required this.blocked});
  final SmsMessage message;
  final bool blocked;

  @override
  Widget build(BuildContext context) {
    final m = message;
    return GestureDetector(
      onLongPress: () => showMessageActions(context, m),
      child: GlassCard(
        glow: m.isThreat ? m.color : null,
        padding: const EdgeInsets.all(16),
        onTap: () => openAnalysis(context, m),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                ThreatIcon(icon: m.category.icon, color: m.color),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              m.sender,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                fontWeight: FontWeight.w800,
                                fontSize: 15.5,
                              ),
                            ),
                          ),
                          if (blocked && m.isThreat)
                            const Padding(
                              padding: EdgeInsets.only(right: 6),
                              child: Icon(
                                Icons.block_rounded,
                                size: 14,
                                color: AppColors.muted,
                              ),
                            ),
                          Text(
                            m.timeLabel,
                            style: const TextStyle(
                              fontSize: 12,
                              color: AppColors.muted,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 3),
                      Text(
                        m.body,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 13.5,
                          height: 1.35,
                          color: Colors.white.withAlpha(180),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            // Risk bar with the percentage beside it (one compact row).
            Row(
              children: [
                Expanded(
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(4),
                    child: Stack(
                      children: [
                        Container(height: 5, color: AppColors.white(0.08)),
                        FractionallySizedBox(
                          widthFactor: m.risk / 100,
                          child: Container(
                            height: 5,
                            decoration: BoxDecoration(
                              gradient: LinearGradient(
                                colors: [m.color.withAlpha(140), m.color],
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Text.rich(
                  TextSpan(
                    children: [
                      TextSpan(
                        text: '${m.risk}%',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w800,
                          color: m.color,
                        ),
                      ),
                      const TextSpan(
                        text: ' RISK',
                        style: TextStyle(
                          fontSize: 10,
                          letterSpacing: 1,
                          color: AppColors.muted,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                // "Safe" messages would otherwise show "Safe" twice.
                if (m.category.label != m.status.label)
                  StatusPill(label: m.category.label, color: m.color),
                StatusPill(label: m.status.label, color: m.color, dot: true),
                StatusPill(
                  label: '${m.confidence}% confidence',
                  color: AppColors.muted,
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// Glass circle next to the scan button: paste a message to check it.
class _AddButton extends StatelessWidget {
  const _AddButton({required this.onTap});
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: 'Check a message',
      child: DecoratedBox(
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: AppColors.white(0.07),
          border: Border.all(color: AppColors.white(0.2)),
        ),
        child: Material(
          type: MaterialType.transparency,
          child: InkWell(
            customBorder: const CircleBorder(),
            onTap: () {
              HapticFeedback.lightImpact();
              onTap();
            },
            child: const SizedBox.square(
              dimension: 52,
              child: Icon(Icons.add_comment_rounded, size: 22),
            ),
          ),
        ),
      ),
    );
  }
}

class _ScanButton extends StatelessWidget {
  const _ScanButton({required this.onTap});
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: 'Scan now',
      child: DecoratedBox(
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          gradient: AppGradients.safe,
          boxShadow: [
            BoxShadow(
              color: AppColors.primary.withAlpha(110),
              blurRadius: 22,
              offset: const Offset(0, 8),
              spreadRadius: -4,
            ),
          ],
        ),
        child: Material(
          type: MaterialType.transparency,
          child: InkWell(
            customBorder: const CircleBorder(),
            onTap: () {
              HapticFeedback.lightImpact();
              onTap();
            },
            child: const SizedBox.square(
              dimension: 52,
              child: Icon(
                Icons.radar_rounded,
                size: 24,
                color: Color(0xFF03121C),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
