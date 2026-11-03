import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/sms_message.dart';
import '../screens/analysis_summary_screen.dart';
import '../state/guard_state.dart';
import '../theme/app_theme.dart';
import 'common.dart';
import 'connection_sheets.dart';
import 'shield_hero.dart';
import 'threat_gauge.dart';

Future<T?> showGlassSheet<T>(
  BuildContext context, {
  required WidgetBuilder builder,
}) {
  return showModalBottomSheet<T>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    barrierColor: const Color.fromRGBO(0, 0, 0, 0.55),
    constraints: const BoxConstraints(maxWidth: 520),
    builder: (ctx) => _SheetFrame(child: builder(ctx)),
  );
}

class _SheetFrame extends StatelessWidget {
  const _SheetFrame({required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: const BorderRadius.vertical(top: Radius.circular(32)),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 30, sigmaY: 30),
        child: Container(
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [Color(0xF2182238), Color(0xF20B1220)],
            ),
            border: Border(top: BorderSide(color: AppColors.white(0.18))),
          ),
          child: SafeArea(
            top: false,
            minimum: const EdgeInsets.only(bottom: 8),
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(22, 10, 22, 22),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 44,
                    height: 5,
                    decoration: BoxDecoration(
                      color: AppColors.white(0.25),
                      borderRadius: BorderRadius.circular(3),
                    ),
                  ),
                  const SizedBox(height: 18),
                  child,
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Messages are analyzed by the user's ThreatGuard server, so "access" means
/// linking this device to it.
Future<void> requestSmsAccess(BuildContext context) async =>
    showConnectSheet(context);

// ---------------------------------------------------------------- checklist

enum _CheckState { ok, attention, pending }

class _Check {
  const _Check(this.icon, this.title, this.subtitle, this.state);
  final IconData icon;
  final String title, subtitle;
  final _CheckState state;
}

class _CheckRow extends StatelessWidget {
  const _CheckRow(this.check);
  final _Check check;

  @override
  Widget build(BuildContext context) {
    final color = switch (check.state) {
      _CheckState.ok => AppColors.green,
      _CheckState.attention => AppColors.orange,
      _CheckState.pending => AppColors.muted,
    };
    final trailing = switch (check.state) {
      _CheckState.ok => Icons.check_circle_rounded,
      _CheckState.attention => Icons.error_rounded,
      _CheckState.pending => Icons.schedule_rounded,
    };
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      constraints: const BoxConstraints(minHeight: 72),
      decoration: BoxDecoration(
        color: AppColors.white(0.06),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppColors.white(0.1)),
      ),
      child: Row(
        children: [
          ThreatIcon(icon: check.icon, color: color, size: 42),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  check.title,
                  style: const TextStyle(
                    fontWeight: FontWeight.w700,
                    fontSize: 14.5,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  check.subtitle,
                  style: const TextStyle(
                    color: AppColors.muted,
                    fontSize: 12.5,
                  ),
                ),
              ],
            ),
          ),
          // Fixed gap so long titles can never touch the status icon.
          const SizedBox(width: 12),
          Icon(trailing, color: color, size: 22),
        ],
      ),
    );
  }
}

/// Every row reflects real state. Anything not running is shown as "pending"
/// or "attention", never as working.
List<_Check> _checks(GuardState s) {
  final access = switch (s.smsPermission) {
    SmsPermission.granted => const _Check(
      Icons.cloud_done_rounded,
      'Server connection',
      'Connected',
      _CheckState.ok,
    ),
    SmsPermission.notGranted => _Check(
      Icons.cloud_off_rounded,
      'Server connection',
      s.backendStatus == BackendStatus.unreachable
          ? 'Server not reachable'
          : 'Not connected',
      _CheckState.attention,
    ),
    SmsPermission.unsupported => const _Check(
      Icons.cloud_off_rounded,
      'Server connection',
      'Not supported on this device',
      _CheckState.pending,
    ),
  };
  final scan = s.scanning
      ? const _Check(
          Icons.radar_rounded,
          'Message scanning',
          'Scan in progress',
          _CheckState.pending,
        )
      : s.lastScan != null
      ? const _Check(
          Icons.radar_rounded,
          'Message scanning',
          'Last scan completed',
          _CheckState.ok,
        )
      : _Check(
          Icons.radar_rounded,
          'Message scanning',
          s.smsPermission == SmsPermission.granted
              ? 'Ready to scan'
              : 'Waiting for a server connection',
          _CheckState.pending,
        );
  // Android only: whether the phone's own texts can be read.
  final phone = switch (s.deviceSms) {
    DeviceSmsAccess.unsupported => null,
    DeviceSmsAccess.granted => const _Check(
      Icons.sms_rounded,
      'Phone messages',
      'SMS access allowed',
      _CheckState.ok,
    ),
    DeviceSmsAccess.notGranted => const _Check(
      Icons.sms_rounded,
      'Phone messages',
      'Allow SMS access in Settings',
      _CheckState.attention,
    ),
  };
  return [
    access,
    ?phone,
    scan,
    _Check(
      Icons.sensors_rounded,
      'Real-time monitoring',
      s.monitoringRunning
          ? 'Analyzing messages as they arrive'
          : s.connected
          ? 'Turned off in Settings'
          : 'Not running',
      s.monitoringRunning ? _CheckState.ok : _CheckState.pending,
    ),
    _Check(
      Icons.psychology,
      'Threat detection',
      s.engineConnected
          ? 'Engine ${s.engineName ?? 'connected'}'
          : 'Not connected',
      s.engineConnected ? _CheckState.ok : _CheckState.pending,
    ),
    // Alerts show inside the app. Push notifications are not built yet, so
    // this row never claims more than that.
    _Check(
      Icons.notifications_active,
      'Threat alerts',
      s.alerts
          ? 'Shown in the app · push not available yet'
          : 'Turned off',
      s.alerts ? _CheckState.ok : _CheckState.pending,
    ),
  ];
}

// ---------------------------------------------------------------- protection

void showProtectionSheet(BuildContext context) =>
    showGlassSheet<void>(context, builder: (_) => const _ProtectionSheet());

class _ProtectionSheet extends StatelessWidget {
  const _ProtectionSheet();

  @override
  Widget build(BuildContext context) {
    final s = context.watch<GuardState>();
    final score = s.protectionScore;
    return Column(
      children: [
        if (s.demoMode) const DemoBanner(),
        const ShieldHero(size: 190),
        Text(
          s.status.label,
          textAlign: TextAlign.center,
          style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w800),
        ),
        const SizedBox(height: 4),
        Text(
          score == null
              ? 'Protection score not available yet'
              : 'Protection score $score%',
          textAlign: TextAlign.center,
          style: const TextStyle(color: AppColors.muted),
        ),
        const SizedBox(height: 18),
        for (final c in _checks(s)) _CheckRow(c),
      ],
    );
  }
}

// ---------------------------------------------------------------- security check

void showSecurityCheckSheet(BuildContext context) =>
    showGlassSheet<void>(context, builder: (_) => const _SecuritySheet());

class _SecuritySheet extends StatelessWidget {
  const _SecuritySheet();

  @override
  Widget build(BuildContext context) {
    final s = context.watch<GuardState>();
    final checks = _checks(s);
    final attention = checks
        .where((c) => c.state == _CheckState.attention)
        .length;
    final pending = checks.where((c) => c.state == _CheckState.pending).length;
    final score = s.protectionScore;
    final summary = attention > 0
        ? '$attention item${attention == 1 ? '' : 's'} need your attention.'
        : pending > 0
        ? '$pending check${pending == 1 ? ' is' : 's are'} waiting on setup or the backend.'
        : 'All checks passed.';
    return Column(
      children: [
        if (s.demoMode) const DemoBanner(),
        Row(
          children: [
            MiniRing(
              value: score?.toDouble() ?? 0,
              text: score == null ? '—' : null,
              size: 76,
              color: attention > 0 ? AppColors.orange : AppColors.green,
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Security Check',
                    style: TextStyle(fontSize: 22, fontWeight: FontWeight.w800),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    summary,
                    style: const TextStyle(
                      color: AppColors.muted,
                      fontSize: 13.5,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: 18),
        for (final c in checks) _CheckRow(c),
      ],
    );
  }
}

// ---------------------------------------------------------------- scan

void showScanSheet(BuildContext context) =>
    showGlassSheet<void>(context, builder: (_) => const _ScanSheet());

class _ScanSheet extends StatefulWidget {
  const _ScanSheet();

  @override
  State<_ScanSheet> createState() => _ScanSheetState();
}

class _ScanSheetState extends State<_ScanSheet> {
  bool _started = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final s = context.read<GuardState>();
      // Starts the real scan only when the backend has provided one.
      if (s.canScan && !s.scanning) {
        s.runScan();
        setState(() => _started = true);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final s = context.watch<GuardState>();
    void close() => Navigator.of(context).pop();

    if (s.demoMode) {
      return _ScanInfo(
        icon: Icons.science_rounded,
        color: AppColors.orange,
        title: 'Demo mode',
        message:
            'Sample messages are shown, so there is nothing to scan. Turn off demo mode in Settings to use your real messages.',
        actions: [GhostButton(label: 'Close', onPressed: close)],
      );
    }
    switch (s.smsPermission) {
      case SmsPermission.unsupported:
        return _ScanInfo(
          icon: Icons.block_rounded,
          color: AppColors.muted,
          title: 'Not supported',
          message: 'Scanning is not available on this device or platform.',
          actions: [GhostButton(label: 'Close', onPressed: close)],
        );
      case SmsPermission.notGranted:
        return _ScanInfo(
          icon: Icons.cloud_off_rounded,
          color: AppColors.orange,
          title: 'Not connected',
          message:
              'Connect this device to your ThreatGuard server so it can analyze your messages.',
          actions: [
            GradientButton(
              label: 'Connect to server',
              icon: Icons.link_rounded,
              onPressed: () => requestSmsAccess(context),
            ),
            GhostButton(label: 'Close', onPressed: close),
          ],
        );
      case SmsPermission.granted:
        break;
    }
    if (s.scanHandler == null) {
      return _ScanInfo(
        icon: Icons.hourglass_empty_rounded,
        color: AppColors.primary,
        title: 'Scanning is not available',
        message: 'This build has no server connection installed.',
        actions: [GhostButton(label: 'Close', onPressed: close)],
      );
    }

    final done = _started && !s.scanning && s.lastScan != null;
    if (s.scanError != null && !s.scanning) {
      return _ScanInfo(
        icon: Icons.error_rounded,
        color: AppColors.orange,
        title: 'Scan failed',
        message: s.scanError!,
        actions: [
          GradientButton(
            label: 'Try again',
            icon: Icons.refresh_rounded,
            onPressed: () => s.runScan(),
          ),
          GhostButton(label: 'Close', onPressed: close),
        ],
      );
    }
    return Column(
      children: [
        MiniRing(
          value: done ? 100 : s.scanProgress * 100,
          size: 120,
          color: done ? AppColors.green : AppColors.primary,
        ),
        const SizedBox(height: 18),
        Text(
          done ? 'Scan complete' : 'Scanning your messages…',
          style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w800),
        ),
        const SizedBox(height: 6),
        Text(
          done
              ? '${s.messagesScanned} messages analyzed · ${s.threatCount} threats found'
              : '${(s.scanProgress * 100).round()}% complete',
          textAlign: TextAlign.center,
          style: const TextStyle(color: AppColors.muted),
        ),
        const SizedBox(height: 22),
        SizedBox(
          width: double.infinity,
          child: done
              ? GradientButton(
                  label: 'Done',
                  icon: Icons.check_rounded,
                  onPressed: close,
                )
              : GhostButton(label: 'Hide', onPressed: close),
        ),
      ],
    );
  }
}

class _ScanInfo extends StatelessWidget {
  const _ScanInfo({
    required this.icon,
    required this.color,
    required this.title,
    required this.message,
    required this.actions,
  });
  final IconData icon;
  final Color color;
  final String title, message;
  final List<Widget> actions;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        ThreatIcon(icon: icon, color: color, size: 72),
        const SizedBox(height: 18),
        Text(
          title,
          textAlign: TextAlign.center,
          style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w800),
        ),
        const SizedBox(height: 6),
        Text(
          message,
          textAlign: TextAlign.center,
          style: const TextStyle(color: AppColors.muted, height: 1.4),
        ),
        const SizedBox(height: 22),
        for (var i = 0; i < actions.length; i++) ...[
          if (i > 0) const SizedBox(height: 10),
          SizedBox(width: double.infinity, child: actions[i]),
        ],
      ],
    );
  }
}

// ---------------------------------------------------------------- alerts

void showAlertsSheet(BuildContext context) {
  showGlassSheet<void>(
    context,
    builder: (ctx) {
      final state = context.read<GuardState>();
      final items = state.activity.take(4).toList();
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (state.demoMode) const DemoBanner(),
          const Text(
            'Recent alerts',
            style: TextStyle(fontSize: 22, fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 4),
          const Text(
            'Threats found in analyzed messages',
            style: TextStyle(color: AppColors.muted),
          ),
          const SizedBox(height: 16),
          if (items.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 24),
              child: Center(
                child: Text(
                  'No alerts yet.',
                  style: TextStyle(color: AppColors.muted),
                ),
              ),
            ),
          for (final m in items)
            _SheetAction(
              icon: m.category.icon,
              color: m.color,
              label: m.activityTitle,
              caption: '${m.sender} · ${m.timeLabel}',
              onTap: () {
                Navigator.of(ctx).pop();
                openAnalysis(context, m);
              },
            ),
        ],
      );
    },
  );
}

// ---------------------------------------------------------------- message actions

void showMessageActions(BuildContext context, SmsMessage m) {
  final state = context.read<GuardState>();
  showGlassSheet<void>(
    context,
    builder: (ctx) {
      final blocked = state.isManuallyBlocked(m.sender);
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            m.sender,
            style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 4),
          Text(
            '${m.category.label} · ${m.risk}% risk',
            style: const TextStyle(color: AppColors.muted),
          ),
          const SizedBox(height: 16),
          _SheetAction(
            icon: Icons.analytics,
            color: AppColors.primary,
            label: 'View AI analysis',
            caption: 'See why this message was flagged',
            onTap: () {
              Navigator.of(ctx).pop();
              openAnalysis(context, m);
            },
          ),
          // Only offered when the server keeps a block list.
          if (state.blockingAvailable)
            _SheetAction(
              icon: blocked ? Icons.lock_open : Icons.block,
              color: blocked ? AppColors.green : AppColors.red,
              label: blocked ? 'Unblock sender' : 'Block sender',
              caption: blocked
                  ? 'Allow messages from this sender again'
                  : 'Mark future messages from this sender as blocked',
              onTap: () {
                Navigator.of(ctx).pop();
                if (blocked) {
                  state.unblockSender(m.sender);
                  showToast(context, '${m.sender} unblocked');
                } else {
                  state.blockSender(m.sender);
                  showToast(context, '${m.sender} blocked');
                }
              },
            ),
          _SheetAction(
            icon: Icons.delete_outline_rounded,
            color: AppColors.muted,
            label: 'Delete from history',
            caption: state.demoMode
                ? 'Remove this sample message'
                : 'Remove this message from your server',
            onTap: () {
              Navigator.of(ctx).pop();
              state.deleteMessage(m);
              showToast(context, 'Message deleted');
            },
          ),
        ],
      );
    },
  );
}

class _SheetAction extends StatelessWidget {
  const _SheetAction({
    required this.icon,
    required this.color,
    required this.label,
    required this.caption,
    required this.onTap,
  });
  final IconData icon;
  final Color color;
  final String label, caption;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Material(
        color: AppColors.white(0.06),
        borderRadius: BorderRadius.circular(20),
        child: InkWell(
          borderRadius: BorderRadius.circular(20),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Row(
              children: [
                ThreatIcon(icon: icon, color: color, size: 42),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        label,
                        style: const TextStyle(
                          fontWeight: FontWeight.w700,
                          fontSize: 14.5,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        caption,
                        style: const TextStyle(
                          color: AppColors.muted,
                          fontSize: 12.5,
                        ),
                      ),
                    ],
                  ),
                ),
                const Icon(Icons.chevron_right_rounded, color: AppColors.muted),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
