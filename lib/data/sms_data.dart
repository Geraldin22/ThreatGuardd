import '../models/sms_message.dart';

class _Seed {
  const _Seed(
    this.sender,
    this.body,
    this.risk,
    this.category,
    this.confidence, {
    this.url,
    this.minutesAgo = 0,
  });

  final String sender, body;
  final int risk, confidence, minutesAgo;
  final ThreatCategory category;
  final String? url;

  SmsMessage build(int id, DateTime at) => SmsMessage(
    id: id,
    sender: sender,
    body: body,
    receivedAt: at,
    risk: risk,
    category: category,
    confidence: confidence,
    url: url,
  );
}

const _initialSeeds = <_Seed>[
  _Seed(
    'BANK ALERT',
    'Your account has been suspended. Verify immediately at http://secure-bank-verify.example.com or access will be permanently closed.',
    97,
    ThreatCategory.banking,
    98,
    url: 'secure-bank-verify.example.com',
    minutesAgo: 2,
  ),
  _Seed(
    'COURIER SERVICE',
    'Delivery failed. Click here to reschedule: http://redeliver-parcel.example.net/track',
    84,
    ThreatCategory.delivery,
    91,
    url: 'redeliver-parcel.example.net',
    minutesAgo: 9,
  ),
  _Seed(
    'MOM',
    "I'll be home around 6.",
    2,
    ThreatCategory.safe,
    99,
    minutesAgo: 14,
  ),
  _Seed(
    'GOV-TAX OFFICE',
    'Final notice: you have an unpaid tax refund. Claim within 24 hours at www.tax-refund-claim.example.org',
    91,
    ThreatCategory.government,
    94,
    url: 'tax-refund-claim.example.org',
    minutesAgo: 27,
  ),
  _Seed(
    'CRYPTOVAULT',
    'Your wallet has been locked. Verify your seed phrase now at http://wallet-restore.example.io to avoid loss of funds.',
    88,
    ThreatCategory.crypto,
    90,
    url: 'wallet-restore.example.io',
    minutesAgo: 41,
  ),
  _Seed(
    'VERIFY-CODE',
    'We detected a login to your account. Reply with the 6-digit code you just received to cancel it.',
    79,
    ThreatCategory.otp,
    87,
    minutesAgo: 55,
  ),
  _Seed(
    'LUCAS',
    'Are we still on for lunch at 12:30?',
    3,
    ThreatCategory.safe,
    98,
    minutesAgo: 80,
  ),
  _Seed(
    'IT HELPDESK',
    'Hi, this is Mark from IT. Your mailbox is full. Please sign in at http://mail-reset.example.com to keep receiving email.',
    58,
    ThreatCategory.impersonation,
    82,
    url: 'mail-reset.example.com',
    minutesAgo: 112,
  ),
  _Seed(
    'ACCOUNT TEAM',
    "Someone requested a password reset. If this wasn't you, confirm your identity at bit.ly/secure-reset immediately.",
    72,
    ThreatCategory.recovery,
    85,
    url: 'bit.ly/secure-reset',
    minutesAgo: 150,
  ),
  _Seed(
    'TEAM CALENDAR',
    'Reminder: the project meeting moved to 3 PM on Thursday in Room B.',
    4,
    ThreatCategory.safe,
    97,
    minutesAgo: 210,
  ),
];

const _incomingSeeds = <_Seed>[
  _Seed(
    'SECURE-PAY',
    'Unusual payment of 480 USD detected. Confirm your card details now: http://pay-secure-check.example.com',
    94,
    ThreatCategory.banking,
    96,
    url: 'pay-secure-check.example.com',
  ),
  _Seed(
    'MAYA',
    'Just landed! Call you in 10 minutes.',
    2,
    ThreatCategory.safe,
    99,
  ),
  _Seed(
    'DHL-NOTICE',
    'Your parcel is held at customs. Pay a 2.99 fee to release it: bit.ly/release-parcel',
    81,
    ThreatCategory.delivery,
    89,
    url: 'bit.ly/release-parcel',
  ),
  _Seed(
    'CRYPTO-GIVEAWAY',
    'You won 0.5 BTC! Claim within 1 hour: www.btc-claim-reward.example.io',
    89,
    ThreatCategory.crypto,
    92,
    url: 'btc-claim-reward.example.io',
  ),
  _Seed(
    'PHARMACY',
    'Your prescription is ready for pickup until Friday.',
    5,
    ThreatCategory.safe,
    97,
  ),
  _Seed(
    'HR DEPARTMENT',
    'Hi, this is HR. Please sign in to confirm your payroll details today: http://hr-portal-login.example.net',
    63,
    ThreatCategory.impersonation,
    84,
    url: 'hr-portal-login.example.net',
  ),
];

List<SmsMessage> initialMessages() {
  final now = DateTime.now();
  var id = 0;
  return [
    for (final s in _initialSeeds)
      s.build(++id, now.subtract(Duration(minutes: s.minutesAgo))),
  ];
}

SmsMessage incomingMessage(int id, int poolIndex) {
  final s = _incomingSeeds[poolIndex % _incomingSeeds.length];
  return s.build(id, DateTime.now());
}
