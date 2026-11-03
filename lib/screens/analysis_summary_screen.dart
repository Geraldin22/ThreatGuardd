import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../models/risk_info.dart';
import '../models/sms_message.dart';
import '../services/threat_analyzer.dart';
import '../state/guard_state.dart';
import '../theme/app_theme.dart';
import '../widgets/aurora_background.dart';
import '../widgets/common.dart';
import '../widgets/glass_card.dart';
import '../widgets/sheets.dart';
import '../widgets/threat_gauge.dart';

void openAnalysis(BuildContext context, SmsMessage m) {
  Navigator.of(context)
      .push(slideUpRoute<void>(AnalysisSummaryScreen(message: m)));
}

class AnalysisSummaryScreen extends StatefulWidget {
  const AnalysisSummaryScreen({super.key, required this.message});
  final SmsMessage message;

  @override
  State<AnalysisSummaryScreen> createState() => _AnalysisSummaryScreenState();
}

class _AnalysisSummaryScreenState extends State<AnalysisSummaryScreen> {
  int _tab = 0;
  static const _tabs = ['Summary', 'Signals', 'Protection', 'Report'];

  Widget _body(SmsMessage m) => switch (_tab) {
    0 => _SummaryTab(message: m),
    1 => _SignalsTab(message: m),
    2 => _ProtectionTab(message: m),
    _ => _ReportTab(message: m),
  };

  @override
  Widget build(BuildContext context) {
    final m = widget.message;
    return Scaffold(
      body: AuroraBackground(
        child: Material(
          type: MaterialType.transparency,
          textStyle: AppTheme.baseText,
          child: Align(
            alignment: Alignment.topCenter,
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 520),
              child: SafeArea(
                child: Column(
                  children: [
                    Padding(
                      padding: const EdgeInsets.fromLTRB(20, 8, 20, 0),
                      child: Row(
                        children: [
                          GlassIconButton(
                            icon: Icons.arrow_back_rounded,
                            onTap: () => Navigator.of(context).pop(),
                          ),
                          const Expanded(
                            child: Center(
                              child: Text(
                                'Analysis Summary',
                                style: TextStyle(
                                  fontSize: 17,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ),
                          ),
                          GlassIconButton(
                            icon: Icons.more_horiz_rounded,
                            onTap: () => showMessageActions(context, m),
                          ),
                        ],
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(20, 16, 20, 14),
                      child: PillTabs(
                        labels: _tabs,
                        index: _tab,
                        onChanged: (i) => setState(() => _tab = i),
                      ),
                    ),
                    Expanded(
                      child: AnimatedSwitcher(
                        duration: const Duration(milliseconds: 280),
                        child: KeyedSubtree(
                          key: ValueKey(_tab),
                          child: _body(m),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// ================================================================ SUMMARY

class _SummaryTab extends StatelessWidget {
  const _SummaryTab({required this.message});
  final SmsMessage message;

  @override
  Widget build(BuildContext context) {
    final m = message;
    final color = m.color;
    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 4, 20, 32),
      children: [
        _MessageCard(message: m),
        const SectionHeader('Threat Analysis'),
        GlassCard(
          padding: const EdgeInsets.all(20),
          glow: AppColors.primary,
          child: Column(
            children: [
              Center(child: ThreatGauge(value: m.risk.toDouble(), width: 290)),
              const SizedBox(height: 10),
              StatusPill(
                label: '${m.level.name.toUpperCase()} RISK',
                color: color,
                dot: true,
              ),
              const SizedBox(height: 18),
              Row(
                children: [
                  Expanded(
                    child: _RingTile(
                      label: 'Threat Confidence',
                      value: m.confidence,
                      color: AppColors.green,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: _RingTile(
                      label: 'Behavior Match',
                      value: m.behaviorMatch,
                      color: AppColors.blue,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
        const SectionHeader('Detection Summary'),
        _VerdictCard(message: m),
        const SizedBox(height: 12),
        _RecommendationCard(message: m),
      ],
    );
  }
}

class _MessageCard extends StatelessWidget {
  const _MessageCard({required this.message});
  final SmsMessage message;

  List<InlineSpan> _spans() {
    final text = message.body;
    if (!message.isThreat) return [TextSpan(text: text)];
    final spans = <InlineSpan>[];
    var pos = 0;
    for (final r in ThreatAnalyzer.findRanges(text)) {
      if (r.start > pos) {
        spans.add(TextSpan(text: text.substring(pos, r.start)));
      }
      spans.add(
        TextSpan(
          text: text.substring(r.start, r.end),
          style: TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.w700,
            backgroundColor: (r.isLink ? AppColors.orange : AppColors.primary)
                .withAlpha(60),
          ),
        ),
      );
      pos = r.end;
    }
    if (pos < text.length) spans.add(TextSpan(text: text.substring(pos)));
    return spans;
  }

  @override
  Widget build(BuildContext context) {
    final m = message;
    return GlassCard(
      padding: const EdgeInsets.all(18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              ThreatIcon(icon: m.category.icon, color: m.color, size: 42),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      m.sender,
                      style: const TextStyle(
                        fontWeight: FontWeight.w700,
                        fontSize: 16,
                      ),
                    ),
                    Text(
                      'Received ${m.clock}',
                      style: const TextStyle(
                        color: AppColors.muted,
                        fontSize: 12.5,
                      ),
                    ),
                  ],
                ),
              ),
              StatusPill(label: m.status.label, color: m.color, dot: true),
            ],
          ),
          const SizedBox(height: 14),
          Text.rich(
            TextSpan(children: _spans()),
            style: TextStyle(
              fontSize: 17,
              height: 1.5,
              color: Colors.white.withAlpha(220),
            ),
          ),
          if (m.url != null && m.isThreat) ...[
            const SizedBox(height: 14),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              decoration: BoxDecoration(
                color: AppColors.white(0.06),
                borderRadius: BorderRadius.circular(14),
              ),
              child: Row(
                children: [
                  const Icon(
                    Icons.link_off_rounded,
                    size: 18,
                    color: AppColors.orange,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      m.url!,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 13,
                        color: AppColors.muted,
                        decoration: TextDecoration.lineThrough,
                      ),
                    ),
                  ),
                  const Text(
                    'Do not open',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      color: AppColors.orange,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _RingTile extends StatelessWidget {
  const _RingTile({
    required this.label,
    required this.value,
    required this.color,
  });
  final String label;
  final int value;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 8),
      decoration: BoxDecoration(
        color: AppColors.white(0.06),
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: AppColors.white(0.1)),
      ),
      child: Column(
        children: [
          MiniRing(value: value.toDouble(), color: color, size: 70),
          const SizedBox(height: 10),
          Text(
            label,
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 12, color: AppColors.muted),
          ),
        ],
      ),
    );
  }
}

class _VerdictCard extends StatelessWidget {
  const _VerdictCard({required this.message});
  final SmsMessage message;

  @override
  Widget build(BuildContext context) {
    final m = message;
    final safe = !m.isThreat;
    final color = safe ? AppColors.green : m.color;
    return GlassCard(
      padding: const EdgeInsets.all(18),
      glow: color,
      child: Column(
        children: [
          Row(
            children: [
              ThreatIcon(
                icon: safe ? Icons.verified_user : Icons.warning_rounded,
                color: color,
                size: 46,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      safe
                          ? 'Message Verified Safe'
                          : '${m.category.label} Detected',
                      style: const TextStyle(
                        fontWeight: FontWeight.w700,
                        fontSize: 16,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      m.verdictSummary,
                      style: const TextStyle(
                        color: AppColors.muted,
                        fontSize: 13,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Text(
                '${m.confidence}% confidence',
                style: const TextStyle(
                  fontSize: 12.5,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const Spacer(),
              const Text(
                'AI Match Level',
                style: TextStyle(fontSize: 12, color: AppColors.muted),
              ),
            ],
          ),
          const SizedBox(height: 8),
          ClipRRect(
            borderRadius: BorderRadius.circular(6),
            child: Stack(
              children: [
                Container(height: 8, color: AppColors.white(0.08)),
                TweenAnimationBuilder<double>(
                  tween: Tween(begin: 0, end: m.confidence / 100),
                  duration: const Duration(milliseconds: 1100),
                  curve: Curves.easeOutCubic,
                  builder: (context, v, _) => FractionallySizedBox(
                    widthFactor: v,
                    child: Container(
                      height: 8,
                      decoration: const BoxDecoration(
                        gradient: AppGradients.safe,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _RecommendationCard extends StatelessWidget {
  const _RecommendationCard({required this.message});
  final SmsMessage message;

  @override
  Widget build(BuildContext context) {
    final m = message;
    final s = context.watch<GuardState>();
    final (title, body) = switch (m.level) {
      RiskLevel.high => (
        'Do not respond or click',
        'This message shows strong scam signals. Do not reply or tap any link. Delete it and contact the company only through its official app or website.',
      ),
      RiskLevel.medium => (
        'Verify before you act',
        'This message shows some scam signals. Do not tap the link. Check with the sender using a number or website you already trust.',
      ),
      RiskLevel.low => (
        'You are all set',
        'No suspicious phrases, links or manipulation were found in this message.',
      ),
    };
    final blocked = s.isBlocked(m.sender);
    return GlassCard(
      padding: const EdgeInsets.all(18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(
                Icons.auto_awesome_rounded,
                size: 18,
                color: AppColors.primary,
              ),
              const SizedBox(width: 8),
              const Text(
                'ThreatGuard recommends',
                style: TextStyle(
                  fontSize: 12.5,
                  fontWeight: FontWeight.w700,
                  color: AppColors.primary,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            title,
            style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 6),
          Text(
            body,
            style: const TextStyle(
              color: AppColors.muted,
              fontSize: 14,
              height: 1.45,
            ),
          ),
          if (m.isThreat && s.blockingAvailable) ...[
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              child: blocked
                  ? const Center(
                      child: StatusPill(
                        label: 'Sender blocked',
                        color: AppColors.green,
                        icon: Icons.check_circle_rounded,
                      ),
                    )
                  : GradientButton(
                      label: 'Block sender',
                      icon: Icons.block_rounded,
                      onPressed: () {
                        context.read<GuardState>().blockSender(m.sender);
                        showToast(context, '${m.sender} blocked', bottom: 24);
                      },
                    ),
            ),
          ],
        ],
      ),
    );
  }
}

// ================================================================ SIGNALS

class _SignalsTab extends StatelessWidget {
  const _SignalsTab({required this.message});
  final SmsMessage message;

  List<(String, String)> _signals() {
    final m = message;
    final list = <(String, String)>[
      for (final h in ThreatAnalyzer.analyze(m.body).hits) (h.label, h.why),
    ];
    final extra = switch (m.category) {
      ThreatCategory.banking => (
        'Brand impersonation',
        'The sender mimics a financial institution.',
      ),
      ThreatCategory.delivery => (
        'Fake logistics notice',
        'Courier wording is used to create a reason to click.',
      ),
      ThreatCategory.otp => (
        'Code harvesting',
        'The message asks you to hand over a one-time code.',
      ),
      ThreatCategory.crypto => (
        'Wallet phishing lure',
        'Targets recovery phrases and wallet credentials.',
      ),
      ThreatCategory.government => (
        'Authority pressure',
        'Poses as an official body to demand fast payment.',
      ),
      ThreatCategory.impersonation => (
        'Role impersonation',
        'Claims to be a trusted colleague or department.',
      ),
      ThreatCategory.recovery => (
        'Fake recovery request',
        'Triggers fear of account loss to steal credentials.',
      ),
      ThreatCategory.safe => null,
    };
    if (extra != null) list.add(extra);
    if (m.url != null && m.isThreat) {
      list.add((
        'URL obfuscation',
        'The domain imitates a trusted brand and was registered very recently.',
      ));
    }
    return list;
  }

  @override
  Widget build(BuildContext context) {
    final m = message;
    final signals = _signals();
    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 4, 20, 32),
      children: [
        if (!m.isThreat)
          GlassCard(
            padding: const EdgeInsets.all(22),
            glow: AppColors.green,
            child: const Column(
              children: [
                Icon(
                  Icons.verified_user_rounded,
                  size: 44,
                  color: AppColors.green,
                ),
                SizedBox(height: 10),
                Text(
                  'No suspicious signals',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
                ),
                SizedBox(height: 4),
                Text(
                  'ThreatGuard found no scam language, risky links or manipulation in this message.',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: AppColors.muted),
                ),
              ],
            ),
          )
        else ...[
          SectionHeader('${signals.length} signals detected'),
          for (var i = 0; i < signals.length; i++)
            Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: GlassCard(
                padding: const EdgeInsets.all(14),
                radius: 22,
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      width: 30,
                      height: 30,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: m.color.withAlpha(40),
                      ),
                      child: Text(
                        '${i + 1}',
                        style: TextStyle(
                          fontWeight: FontWeight.w800,
                          fontSize: 13,
                          color: m.color,
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            signals[i].$1,
                            style: const TextStyle(
                              fontWeight: FontWeight.w700,
                              fontSize: 15,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            signals[i].$2,
                            style: const TextStyle(
                              color: AppColors.muted,
                              fontSize: 13,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          if (m.url != null) ...[
            const SectionHeader('Link analysis'),
            GlassCard(
              padding: const EdgeInsets.all(18),
              child: Column(
                children: [
                  _KeyValue('Domain', m.url!),
                  _KeyValue(
                    'Reputation',
                    m.level == RiskLevel.high ? 'Malicious' : 'Suspicious',
                    color: m.color,
                  ),
                  const _KeyValue('Domain age', 'Registered 2 days ago'),
                  const _KeyValue(
                    'Redirects',
                    '3 hops to a login page',
                    last: true,
                  ),
                ],
              ),
            ),
          ],
        ],
      ],
    );
  }
}

class _KeyValue extends StatelessWidget {
  const _KeyValue(this.label, this.value, {this.color, this.last = false});
  final String label, value;
  final Color? color;
  final bool last;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 12),
      decoration: BoxDecoration(
        border: last
            ? null
            : Border(bottom: BorderSide(color: AppColors.white(0.08))),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: const TextStyle(color: AppColors.muted, fontSize: 14),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Text(
              value,
              textAlign: TextAlign.end,
              style: TextStyle(
                fontWeight: FontWeight.w600,
                fontSize: 14,
                color: color ?? AppColors.text,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ================================================================ PROTECTION

class _ProtectionTab extends StatefulWidget {
  const _ProtectionTab({required this.message});
  final SmsMessage message;

  @override
  State<_ProtectionTab> createState() => _ProtectionTabState();
}

class _ProtectionTabState extends State<_ProtectionTab> {
  final Set<int> _done = {};

  @override
  Widget build(BuildContext context) {
    final m = widget.message;
    final actions = switch (m.level) {
      RiskLevel.high => const [
        'Message flagged as high risk',
        'No automatic action was taken. Blocking needs backend integration.',
      ],
      RiskLevel.medium => const ['Message flagged with a warning'],
      RiskLevel.low => const ['No threat signals found'],
    };
    final todo = switch (m.level) {
      RiskLevel.high => const [
        'Do not reply or tap any link',
        'Delete the message',
        "Report it via the company's official app or website",
        'If you shared a code or password, change it now',
      ],
      RiskLevel.medium => const [
        'Do not tap the link yet',
        'Contact the sender through a trusted number',
        'Delete it if you cannot verify it',
      ],
      RiskLevel.low => const ['Nothing to do. Enjoy your day.'],
    };

    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 4, 20, 32),
      children: [
        const SectionHeader('Analysis result'),
        GlassCard(
          padding: const EdgeInsets.all(18),
          glow: AppColors.green,
          child: Column(
            children: [
              for (var i = 0; i < actions.length; i++)
                Padding(
                  padding: EdgeInsets.only(
                    bottom: i == actions.length - 1 ? 0 : 14,
                  ),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Icon(
                        Icons.check_circle_rounded,
                        size: 20,
                        color: AppColors.green,
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          actions[i],
                          style: const TextStyle(fontSize: 14.5),
                        ),
                      ),
                    ],
                  ),
                ),
            ],
          ),
        ),
        SectionHeader('What you should do  ·  ${_done.length}/${todo.length}'),
        for (var i = 0; i < todo.length; i++)
          Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: GlassCard(
              radius: 22,
              padding: const EdgeInsets.all(16),
              onTap: () {
                HapticFeedback.selectionClick();
                setState(() {
                  if (!_done.add(i)) _done.remove(i);
                });
              },
              child: Row(
                children: [
                  AnimatedContainer(
                    duration: const Duration(milliseconds: 220),
                    width: 24,
                    height: 24,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      gradient: _done.contains(i) ? AppGradients.safe : null,
                      border: Border.all(
                        color: _done.contains(i)
                            ? Colors.transparent
                            : AppColors.white(0.3),
                        width: 1.5,
                      ),
                    ),
                    child: _done.contains(i)
                        ? const Icon(
                            Icons.check_rounded,
                            size: 16,
                            color: Color(0xFF03121C),
                          )
                        : null,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      todo[i],
                      style: TextStyle(
                        fontSize: 14.5,
                        color: _done.contains(i)
                            ? AppColors.muted
                            : AppColors.text,
                        decoration: _done.contains(i)
                            ? TextDecoration.lineThrough
                            : null,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
      ],
    );
  }
}

// ================================================================ REPORT

class _ReportTab extends StatelessWidget {
  const _ReportTab({required this.message});
  final SmsMessage message;

  String _text() {
    final m = message;
    return 'ThreatGuard AI report ${m.reportId}\n'
        'Sender: ${m.sender}\n'
        'Received: ${m.clock}\n'
        'Category: ${m.category.label}\n'
        'Risk: ${m.risk}%\n'
        'Confidence: ${m.confidence}%\n'
        'Status: ${m.status.label}\n'
        'Message: ${m.body}';
  }

  @override
  Widget build(BuildContext context) {
    final m = message;
    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 4, 20, 32),
      children: [
        const SectionHeader('Incident report'),
        GlassCard(
          padding: const EdgeInsets.all(18),
          child: Column(
            children: [
              _KeyValue('Report ID', m.reportId),
              _KeyValue('Sender', m.sender),
              _KeyValue('Received', m.clock),
              _KeyValue('Category', m.category.label),
              _KeyValue('Risk score', '${m.risk}%', color: m.color),
              _KeyValue('Confidence', '${m.confidence}%'),
              _KeyValue('Status', m.status.label, color: m.color, last: true),
            ],
          ),
        ),
        const SizedBox(height: 18),
        SizedBox(
          width: double.infinity,
          child: GradientButton(
            label: 'Copy report',
            icon: Icons.copy_rounded,
            onPressed: () async {
              await Clipboard.setData(ClipboardData(text: _text()));
              if (context.mounted) {
                showToast(context, 'Report copied to clipboard', bottom: 24);
              }
            },
          ),
        ),
      ],
    );
  }
}
