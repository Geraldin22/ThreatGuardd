import 'dart:math' as math;

import 'models.dart';

class _Rule {
  _Rule(this.label, String pattern, this.why, {this.cred = false})
    : re = RegExp(pattern, caseSensitive: false);
  final String label, why;
  final RegExp re;
  final bool cred;
}

class _Weighted {
  _Weighted(String pattern, this.weight)
    : re = RegExp(pattern, caseSensitive: false);
  final RegExp re;
  final int weight;
}

class ThreatEngine {
  ThreatEngine._();

  static final _rules = <_Rule>[
    _Rule('urgent', r'\burgent(ly)?\b', 'Creates false urgency'),
    _Rule('immediately', r'\bimmediate(ly)?\b', 'Pressures you to act fast'),
    _Rule('action required', r'action required', 'Pressures you to act fast'),
    _Rule(
      'deadline',
      r'within \d+ ?(hours?|minutes?|days?)|expires? (today|soon)|final notice',
      'Uses a deadline to rush you',
    ),
    _Rule(
      'suspended',
      r'\b(suspended|locked|deactivated|disabled|closed)\b',
      'Threatens loss of an account',
    ),
    _Rule(
      'verify / confirm',
      r'\b(verify|confirm|validate)\b',
      'Asks you to confirm details',
      cred: true,
    ),
    _Rule(
      'password',
      r'\b(password|passcode)\b',
      'Asks for login credentials',
      cred: true,
    ),
    _Rule(
      'OTP / code',
      r'\b(otp|one-time (code|password)|security code|pin)\b',
      'Asks for a one-time code',
      cred: true,
    ),
    _Rule(
      'login',
      r'\b(log ?in|sign ?in)\b',
      'Pushes you to a login page',
      cred: true,
    ),
    _Rule(
      'bank / account',
      r'\b(bank|account|credit card)\b',
      'Mentions financial or account details',
    ),
    _Rule(
      'prize / reward',
      r'\b(winner|you won|prize|lottery|gift card|reward)\b',
      'Offers an unexpected reward',
    ),
    _Rule('claim', r'\bclaim\b', 'Asks you to claim something'),
    _Rule('click here', r'click (here|below|the link)', 'Pushes you to click'),
  ];

  static const _ruleWeight = 15;
  static final _linkRe = RegExp(
    r'(https?:\/\/|www\.)\S+|\b(?:[a-z0-9-]+\.)+(com|net|org|io|ly|co|info|xyz|ru|top|click|link)\b(\/\S*)?',
    caseSensitive: false,
  );
  static final _shortRe = RegExp(
    r'\b(bit\.ly|tinyurl\.com|t\.co|goo\.gl|is\.gd|cutt\.ly)\b',
    caseSensitive: false,
  );
  static final _ipRe = RegExp(
    r'https?:\/\/\d{1,3}(\.\d{1,3}){3}',
    caseSensitive: false,
  );

  /// Words that point to a scam family. The family with the most weight wins.
  static final _kinds = <ThreatKind, List<_Weighted>>{
    ThreatKind.otp: [
      _Weighted(
        r'\b(otp|\d{4,8}-?digit code|verification code|security code|one-time (code|password)|pin)\b',
        3,
      ),
      _Weighted(r'\b(reply|share|send|read (it )?out|forward)\b', 2),
    ],
    ThreatKind.banking: [
      _Weighted(
        r'\b(bank|account|card|debit|credit|transaction|payment|transfer)\b',
        2,
      ),
      _Weighted(r'\b(suspended|unusual|unauthori[sz]ed)\b', 1),
    ],
    ThreatKind.delivery: [
      _Weighted(
        r'\b(parcel|package|delivery|courier|shipment|tracking|redeliver\w*|customs|dhl|fedex|ups|usps)\b',
        3,
      ),
    ],
    ThreatKind.crypto: [
      _Weighted(
        r'\b(crypto\w*|bitcoin|btc|ethereum|eth|wallet|seed phrase|airdrop|giveaway|nft|usdt)\b',
        3,
      ),
    ],
    ThreatKind.government: [
      _Weighted(
        r'\b(tax|irs|revenue|refund|government|gov|police|court|penalty|fine)\b',
        3,
      ),
    ],
    ThreatKind.recovery: [
      _Weighted(
        r'(password reset|reset (your |the )?password|recover(y)?|unlock|restore access|your identity|wasn.t you|was not you)',
        3,
      ),
    ],
    ThreatKind.impersonation: [
      _Weighted(
        r'\bthis is [a-z]+ (from|at|in) (it|hr|support|the)\b|\bthis is (hr|it)\b',
        4,
      ),
      _Weighted(
        r'\b(help ?desk|it support|hr department|payroll|mailbox|director|ceo)\b',
        3,
      ),
    ],
  };

  static Analysis analyze(
    String text, {
    Sensitivity sensitivity = Sensitivity.balanced,
    bool scanLinks = true,
  }) {
    final signals = <Signal>[];
    var raw = 0;
    var asksForDetails = false;

    for (final rule in _rules) {
      if (!rule.re.hasMatch(text)) continue;
      signals.add(Signal(rule.label, rule.why));
      raw += _ruleWeight;
      if (rule.cred) asksForDetails = true;
    }

    final linkMatch = scanLinks ? _linkRe.firstMatch(text) : null;
    if (linkMatch != null) {
      signals.add(
        const Signal(
          'link',
          'Contains a link. Check the real address before clicking',
        ),
      );
      raw += 20;
      if (_shortRe.hasMatch(text)) {
        signals.add(
          const Signal(
            'short link',
            'Shortened links hide the real destination',
          ),
        );
        raw += 15;
      }
      if (_ipRe.hasMatch(text)) {
        signals.add(
          const Signal(
            'IP address link',
            'Real services rarely link to a raw IP address',
          ),
        );
        raw += 20;
      }
      if (asksForDetails) {
        signals.add(
          const Signal(
            'link + login request',
            'A link combined with a request for details is a classic phishing pattern',
          ),
        );
        raw += 15;
      }
    }

    final score = (math.min(raw, 100) * sensitivity.scale)
        .round()
        .clamp(0, 100);
    final band = RiskBand.fromScore(score);
    final kind = band == RiskBand.low ? ThreatKind.safe : _classify(text);

    return Analysis(
      score: score,
      band: band,
      kind: kind,
      confidence: _confidence(score, band, signals.length),
      signals: signals,
      url: linkMatch == null ? null : _cleanUrl(linkMatch.group(0)!),
    );
  }

  static ThreatKind _classify(String text) {
    var best = ThreatKind.impersonation; // generic social-engineering bucket
    var bestWeight = 0;
    for (final entry in _kinds.entries) {
      var weight = 0;
      for (final w in entry.value) {
        if (w.re.hasMatch(text)) weight += w.weight;
      }
      if (weight > bestWeight) {
        best = entry.key;
        bestWeight = weight;
      }
    }
    return best;
  }

  static int _confidence(int score, RiskBand band, int signalCount) {
    if (band == RiskBand.low) return (99 - score ~/ 4).clamp(60, 99);
    return (55 + signalCount * 6 + (score >= 60 ? 8 : 0)).clamp(55, 99);
  }

  static String _cleanUrl(String raw) {
    var url = raw.replaceFirst(RegExp(r'^https?:\/\/', caseSensitive: false), '');
    url = url.replaceFirst(RegExp(r'^www\.', caseSensitive: false), '');
    return url.replaceFirst(RegExp(r'''[.,;:!?)"']+$'''), '');
  }

  static List<HighlightRange> findRanges(String text) {
    final ranges = <HighlightRange>[];
    void collect(RegExp re, bool isLink) {
      for (final m in re.allMatches(text)) {
        if (m.end == m.start) continue;
        ranges.add(HighlightRange(m.start, m.end, isLink));
      }
    }

    for (final rule in _rules) {
      collect(rule.re, false);
    }
    collect(_linkRe, true);

    ranges.sort(
      (a, b) => a.start != b.start ? a.start - b.start : b.end - a.end,
    );
    final merged = <HighlightRange>[];
    for (final r in ranges) {
      if (merged.isNotEmpty && r.start < merged.last.end) {
        final last = merged.last;
        last.end = math.max(last.end, r.end);
        if (r.isLink) last.isLink = true;
      } else {
        merged.add(HighlightRange(r.start, r.end, r.isLink));
      }
    }
    return merged;
  }
}
