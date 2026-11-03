import 'package:test/test.dart';
import 'package:threatguard_core/threatguard_core.dart';

/// The sample messages from the app's demo data, with the category and
/// threat/safe verdict the app's designers intended for each.
const _samples = <(String, ThreatKind, bool)>[
  (
    'Your account has been suspended. Verify immediately at http://secure-bank-verify.example.com or access will be permanently closed.',
    ThreatKind.banking,
    true,
  ),
  (
    'Delivery failed. Click here to reschedule: http://redeliver-parcel.example.net/track',
    ThreatKind.delivery,
    true,
  ),
  ("I'll be home around 6.", ThreatKind.safe, false),
  (
    'Final notice: you have an unpaid tax refund. Claim within 24 hours at www.tax-refund-claim.example.org',
    ThreatKind.government,
    true,
  ),
  (
    'Your wallet has been locked. Verify your seed phrase now at http://wallet-restore.example.io to avoid loss of funds.',
    ThreatKind.crypto,
    true,
  ),
  (
    'We detected a login to your account. Reply with the 6-digit code you just received to cancel it.',
    ThreatKind.otp,
    true,
  ),
  ('Are we still on for lunch at 12:30?', ThreatKind.safe, false),
  (
    'Hi, this is Mark from IT. Your mailbox is full. Please sign in at http://mail-reset.example.com to keep receiving email.',
    ThreatKind.impersonation,
    true,
  ),
  (
    "Someone requested a password reset. If this wasn't you, confirm your identity at bit.ly/secure-reset immediately.",
    ThreatKind.recovery,
    true,
  ),
  (
    'Reminder: the project meeting moved to 3 PM on Thursday in Room B.',
    ThreatKind.safe,
    false,
  ),
  (
    'Unusual payment of 480 USD detected. Confirm your card details now: http://pay-secure-check.example.com',
    ThreatKind.banking,
    true,
  ),
  ('Just landed! Call you in 10 minutes.', ThreatKind.safe, false),
  (
    'Your parcel is held at customs. Pay a 2.99 fee to release it: bit.ly/release-parcel',
    ThreatKind.delivery,
    true,
  ),
  (
    'You won 0.5 BTC! Claim within 1 hour: www.btc-claim-reward.example.io',
    ThreatKind.crypto,
    true,
  ),
  (
    'Your prescription is ready for pickup until Friday.',
    ThreatKind.safe,
    false,
  ),
  (
    'Hi, this is HR. Please sign in to confirm your payroll details today: http://hr-portal-login.example.net',
    ThreatKind.impersonation,
    true,
  ),
];

void main() {
  group('sample messages', () {
    for (final (text, kind, threat) in _samples) {
      test(text, () {
        final a = ThreatEngine.analyze(text);
        expect(a.isThreat, threat, reason: 'score ${a.score}');
        expect(a.kind, kind);
      });
    }
  });

  test('plain text with no signals scores zero and is safe', () {
    final a = ThreatEngine.analyze('See you at the park at five');
    expect(a.score, 0);
    expect(a.band, RiskBand.low);
    expect(a.kind, ThreatKind.safe);
    expect(a.signals, isEmpty);
    expect(a.url, isNull);
  });

  test('score is capped at 100', () {
    final a = ThreatEngine.analyze(
      'URGENT immediately verify your password OTP login at http://1.2.3.4/x '
      'or bit.ly/x account suspended, claim your prize, click here',
      sensitivity: Sensitivity.strict,
    );
    expect(a.score, 100);
    expect(a.band, RiskBand.high);
  });

  test('sensitivity scales the score', () {
    const text = 'Please verify your account now: http://example.com/check';
    final relaxed = ThreatEngine.analyze(text, sensitivity: Sensitivity.relaxed);
    final balanced = ThreatEngine.analyze(text);
    final strict = ThreatEngine.analyze(text, sensitivity: Sensitivity.strict);
    expect(relaxed.score, lessThan(balanced.score));
    expect(balanced.score, lessThan(strict.score));
  });

  test('turning link scanning off ignores links', () {
    const text = 'Your parcel is waiting: http://example.com/track';
    expect(ThreatEngine.analyze(text).url, 'example.com/track');
    final off = ThreatEngine.analyze(text, scanLinks: false);
    expect(off.url, isNull);
    expect(off.signals.any((s) => s.label == 'link'), isFalse);
  });

  test('url extraction strips scheme, www and trailing punctuation', () {
    expect(
      ThreatEngine.analyze('Go to https://www.evil.example.com/a?b=1.').url,
      'evil.example.com/a?b=1',
    );
    expect(
      ThreatEngine.analyze('Visit bit.ly/secure-reset!').url,
      'bit.ly/secure-reset',
    );
  });

  test('findRanges merges overlapping matches and marks links', () {
    const text = 'Verify now at http://x.example.com';
    final ranges = ThreatEngine.findRanges(text);
    expect(ranges.any((r) => r.isLink), isTrue);
    for (var i = 1; i < ranges.length; i++) {
      expect(ranges[i].start, greaterThanOrEqualTo(ranges[i - 1].end));
    }
  });

  test('analysis serialises to the wire format', () {
    final json = ThreatEngine.analyze('Verify at bit.ly/x now').toJson();
    expect(json.keys, containsAll(['risk', 'band', 'category', 'confidence', 'url', 'signals']));
  });
}
