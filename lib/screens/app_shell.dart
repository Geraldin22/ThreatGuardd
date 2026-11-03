import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../state/guard_state.dart';
import '../theme/app_theme.dart';
import '../widgets/aurora_background.dart';
import '../widgets/common.dart';
import '../widgets/floating_dock.dart';
import 'dashboard_screen.dart';
import 'reports_screen.dart';
import 'settings_screen.dart';
import 'sms_monitor_screen.dart';
import 'threat_center_screen.dart';

class AppShell extends StatefulWidget {
  const AppShell({super.key});

  @override
  State<AppShell> createState() => _AppShellState();
}

class _AppShellState extends State<AppShell> {
  int _index = 0;

  static const _items = [
    DockItem(Icons.dashboard_rounded, 'Dashboard'),
    DockItem(Icons.sms_rounded, 'Monitor'),
    DockItem(Icons.shield_rounded, 'Threats'),
    DockItem(Icons.insights_rounded, 'Reports'),
    DockItem(Icons.tune_rounded, 'Settings'),
  ];

  void _go(int i) => setState(() => _index = i);

  Widget _page() => switch (_index) {
    0 => DashboardScreen(onNavigate: _go),
    1 => const SmsMonitorScreen(),
    2 => const ThreatCenterScreen(),
    3 => const ReportsScreen(),
    _ => const SettingsScreen(),
  };

  @override
  Widget build(BuildContext context) {
    final pad = MediaQuery.paddingOf(context);
    // Read here, above the Scaffold: inside the body the Scaffold has already
    // consumed the keyboard inset.
    final keyboardOpen = MediaQuery.viewInsetsOf(context).bottom > 0;

    // A change that could not be saved to the server is said out loud once,
    // never silently dropped.
    final syncError = context.select<GuardState, String?>((s) => s.syncError);
    if (syncError != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        final state = context.read<GuardState>();
        final message = state.syncError;
        if (message == null) return;
        state.clearSyncError();
        showToast(context, message);
      });
    }

    return Scaffold(
      body: AuroraBackground(
        child: Material(
          type: MaterialType.transparency,
          textStyle: AppTheme.baseText,
          child: Align(
            alignment: Alignment.topCenter,
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 520),
              child: Stack(
                children: [
                  Positioned.fill(
                    child: AnimatedSwitcher(
                      duration: const Duration(milliseconds: 320),
                      transitionBuilder: (child, animation) => FadeTransition(
                        opacity: animation,
                        child: SlideTransition(
                          position: Tween<Offset>(
                            begin: const Offset(0, 0.02),
                            end: Offset.zero,
                          ).animate(animation),
                          child: child,
                        ),
                      ),
                      child: KeyedSubtree(
                        key: ValueKey(_index),
                        child: _page(),
                      ),
                    ),
                  ),
                  // Soft fade under the status bar so scrolled content never
                  // collides with the clock and icons.
                  Positioned(
                    top: 0,
                    left: 0,
                    right: 0,
                    height: pad.top + 10,
                    child: IgnorePointer(
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            begin: Alignment.topCenter,
                            end: Alignment.bottomCenter,
                            colors: [
                              AppColors.background.withAlpha(217),
                              AppColors.background.withAlpha(0),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                  // Matching fade behind the floating dock.
                  if (!keyboardOpen)
                    Positioned(
                      left: 0,
                      right: 0,
                      bottom: 0,
                      height: kDockClearance + pad.bottom,
                      child: IgnorePointer(
                        child: DecoratedBox(
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              begin: Alignment.topCenter,
                              end: Alignment.bottomCenter,
                              colors: [
                                AppColors.background.withAlpha(0),
                                AppColors.background.withAlpha(190),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                  Positioned(
                    left: 0,
                    right: 0,
                    bottom: 0,
                    // Slides away while the keyboard is open so it never
                    // rides up over the content being typed into.
                    child: AnimatedSlide(
                      duration: const Duration(milliseconds: 220),
                      curve: Curves.easeOutCubic,
                      offset: keyboardOpen ? const Offset(0, 1.4) : Offset.zero,
                      child: AnimatedOpacity(
                        duration: const Duration(milliseconds: 180),
                        opacity: keyboardOpen ? 0 : 1,
                        child: IgnorePointer(
                          ignoring: keyboardOpen,
                          child: FloatingDock(
                            items: _items,
                            index: _index,
                            onChanged: _go,
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
