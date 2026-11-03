import 'package:threatguard_core/threatguard_core.dart';

import '../models/inbox_message.dart';
import '../models/risk_info.dart';

export 'package:threatguard_core/threatguard_core.dart' show HighlightRange;

/// On-device view of the shared rule engine (`packages/threatguard_core`).
/// The server runs the same rules, so what the app explains here matches the
/// score the server stored.
class ThreatAnalyzer {
  ThreatAnalyzer._();

  static ScanResult analyze(String text) {
    final a = ThreatEngine.analyze(text);
    return ScanResult(
      score: a.score,
      level: RiskLevel.values.byName(a.band.name),
      hits: [for (final s in a.signals) SignalHit(s.label, s.why)],
    );
  }

  static List<HighlightRange> findRanges(String text) =>
      ThreatEngine.findRanges(text);
}
