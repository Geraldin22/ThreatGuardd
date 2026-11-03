/// How aggressively messages are flagged. Scales the raw rule score.
enum Sensitivity {
  relaxed(0.8),
  balanced(1.0),
  strict(1.25);

  const Sensitivity(this.scale);
  final double scale;

  static Sensitivity? parse(Object? value) {
    for (final s in values) {
      if (s.name == value) return s;
    }
    return null;
  }
}

/// Risk band. Thresholds match the app: 25 = flagged, 60 = blocked.
enum RiskBand {
  low,
  medium,
  high;

  static RiskBand fromScore(int score) => score >= 60
      ? high
      : score >= 25
      ? medium
      : low;
}

/// Scam family. Names match the app's `ThreatCategory` enum one-to-one.
enum ThreatKind {
  banking,
  delivery,
  otp,
  crypto,
  government,
  impersonation,
  recovery,
  safe,
}

class Signal {
  const Signal(this.label, this.why);
  final String label, why;

  Map<String, Object?> toJson() => {'label': label, 'why': why};

  factory Signal.fromJson(Map<String, Object?> json) =>
      Signal(json['label'] as String, json['why'] as String);
}

class Analysis {
  const Analysis({
    required this.score,
    required this.band,
    required this.kind,
    required this.confidence,
    required this.signals,
    this.url,
  });

  /// 0 – 100, already adjusted for sensitivity.
  final int score;
  final RiskBand band;
  final ThreatKind kind;

  /// 0 – 100. How strong the evidence is. A rule-signal heuristic, not a
  /// statistical probability.
  final int confidence;
  final List<Signal> signals;

  /// First link found in the message, without scheme or `www.`.
  final String? url;

  bool get isThreat => score >= 25;

  Map<String, Object?> toJson() => {
    'risk': score,
    'band': band.name,
    'category': kind.name,
    'confidence': confidence,
    'url': url,
    'signals': [for (final s in signals) s.toJson()],
  };
}

/// A span of text worth highlighting in the UI.
class HighlightRange {
  HighlightRange(this.start, this.end, this.isLink);
  int start, end;
  bool isLink;
}
