import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:threat_guard/main.dart';
import 'package:threat_guard/state/guard_state.dart';

void main() {
  testWidgets('ThreatGuard dashboard loads', (tester) async {
    await tester.pumpWidget(
      ChangeNotifierProvider(
        create: (_) => GuardState(),
        child: const ThreatGuardApp(),
      ),
    );
    await tester.pump();

    expect(find.text('ThreatGuard AI'), findsOneWidget);

    // Unmount so the app's timers are cancelled before the test ends.
    await tester.pumpWidget(const SizedBox());
  });
}
