import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../screens/analysis_summary_screen.dart';
import '../state/guard_state.dart';
import '../theme/app_theme.dart';
import 'common.dart';
import 'sheets.dart';

/// Pill-shaped text field in the style of the Monitor search box.
class _Field extends StatelessWidget {
  const _Field({
    required this.controller,
    required this.hint,
    this.icon,
    this.lines = 1,
    this.maxLength,
    this.keyboard,
    this.onSubmitted,
    this.autofocus = false,
  });
  final TextEditingController controller;
  final String hint;
  final IconData? icon;
  final int lines;
  final int? maxLength;
  final TextInputType? keyboard;
  final VoidCallback? onSubmitted;
  final bool autofocus;

  @override
  Widget build(BuildContext context) {
    final multi = lines > 1;
    return Container(
      padding: EdgeInsets.symmetric(horizontal: 14, vertical: multi ? 6 : 0),
      decoration: BoxDecoration(
        color: AppColors.white(0.07),
        borderRadius: BorderRadius.circular(multi ? 22 : AppRadius.pill),
        border: Border.all(color: AppColors.white(0.12)),
      ),
      child: TextField(
        controller: controller,
        autofocus: autofocus,
        minLines: lines,
        maxLines: lines,
        maxLength: maxLength,
        keyboardType: keyboard ?? (multi ? TextInputType.multiline : null),
        textInputAction: multi ? TextInputAction.newline : TextInputAction.done,
        onSubmitted: onSubmitted == null ? null : (_) => onSubmitted!(),
        autocorrect: false,
        enableSuggestions: false,
        style: const TextStyle(fontSize: 15),
        cursorColor: AppColors.primary,
        onTapOutside: (_) => FocusManager.instance.primaryFocus?.unfocus(),
        decoration: InputDecoration(
          border: InputBorder.none,
          isDense: true,
          counterText: '',
          hintText: hint,
          hintStyle: const TextStyle(color: AppColors.muted),
          prefixIcon: icon == null ? null : Icon(icon, color: AppColors.muted),
          contentPadding: const EdgeInsets.symmetric(vertical: 14),
        ),
      ),
    );
  }
}

/// Lifts sheet content above the on-screen keyboard.
class _KeyboardPad extends StatelessWidget {
  const _KeyboardPad({required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) => Padding(
    padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
    child: child,
  );
}

class _Label extends StatelessWidget {
  const _Label(this.text);
  final String text;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(4, 0, 4, 6),
    child: Align(
      alignment: Alignment.centerLeft,
      child: Text(
        text,
        style: const TextStyle(
          color: AppColors.muted,
          fontSize: 12.5,
          fontWeight: FontWeight.w600,
        ),
      ),
    ),
  );
}

// ------------------------------------------------------------------ connect

/// Link this device to a ThreatGuard server, or manage the link.
void showConnectSheet(BuildContext context) => showGlassSheet<void>(
  context,
  builder: (_) => const _KeyboardPad(child: _ConnectSheet()),
);

class _ConnectSheet extends StatefulWidget {
  const _ConnectSheet();

  @override
  State<_ConnectSheet> createState() => _ConnectSheetState();
}

class _ConnectSheetState extends State<_ConnectSheet> {
  late final _url = TextEditingController(
    text: context.read<GuardState>().backendUrl ?? '',
  );
  final _secret = TextEditingController();
  bool _busy = false;
  String? _error;
  String? _link;

  @override
  void dispose() {
    _url.dispose();
    _secret.dispose();
    super.dispose();
  }

  Future<void> _connect() async {
    final state = context.read<GuardState>();
    final backend = state.backend;
    if (backend == null || _busy) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    final error = await backend.connect(_url.text, _secret.text);
    if (!mounted) return;
    setState(() {
      _busy = false;
      _error = error;
    });
    if (error == null) {
      Navigator.of(context).pop();
      showToast(context, 'Connected');
    }
  }

  Future<void> _makeLink() async {
    final backend = context.read<GuardState>().backend;
    if (backend == null || _busy) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final link = await backend.newPairingLink();
      if (mounted) setState(() => _link = link);
    } catch (e) {
      if (mounted) setState(() => _error = 'Could not create a link: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = context.watch<GuardState>();
    return s.connected ? _connected(s) : _form(s);
  }

  // ---- not linked yet
  Widget _form(GuardState s) {
    final unreachable = s.backendStatus == BackendStatus.unreachable;
    final connecting = _busy || s.backendStatus == BackendStatus.connecting;
    final message = _error ?? s.backendError;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            ThreatIcon(
              icon: unreachable
                  ? Icons.cloud_off_rounded
                  : Icons.link_rounded,
              color: unreachable ? AppColors.orange : AppColors.primary,
              size: 52,
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Text(
                unreachable ? 'Server not reachable' : 'Connect to your server',
                style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w800),
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),
        Text(
          unreachable
              ? 'ThreatGuard cannot reach the server right now. It keeps trying.'
              : 'Messages are analyzed by your own ThreatGuard server. Start it '
                    'on your computer and open the link it prints on this '
                    'phone, or enter its details below.',
          style: const TextStyle(color: AppColors.muted, fontSize: 13.5, height: 1.4),
        ),
        const SizedBox(height: 18),
        const _Label('Server address'),
        _Field(
          controller: _url,
          hint: 'e.g. 192.168.1.10:8080',
          icon: Icons.dns_rounded,
          keyboard: TextInputType.url,
        ),
        const SizedBox(height: 12),
        const _Label('Pairing code or API key'),
        _Field(
          controller: _secret,
          hint: 'Shown in the server window',
          icon: Icons.key_rounded,
          onSubmitted: _connect,
        ),
        if (message != null) ...[
          const SizedBox(height: 12),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Padding(
                padding: EdgeInsets.only(top: 1),
                child: Icon(Icons.error_rounded, size: 16, color: AppColors.orange),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  message,
                  style: const TextStyle(
                    color: AppColors.orange,
                    fontSize: 13,
                    height: 1.35,
                  ),
                ),
              ),
            ],
          ),
        ],
        const SizedBox(height: 20),
        SizedBox(
          width: double.infinity,
          child: GradientButton(
            label: connecting ? 'Connecting…' : 'Connect',
            icon: Icons.link_rounded,
            onPressed: connecting ? () {} : _connect,
          ),
        ),
        if (unreachable) ...[
          const SizedBox(height: 10),
          SizedBox(
            width: double.infinity,
            child: GhostButton(
              label: 'Try again now',
              icon: Icons.refresh_rounded,
              onPressed: () => s.backend?.retry(),
            ),
          ),
        ],
      ],
    );
  }

  // ---- linked
  Widget _connected(GuardState s) {
    final host = Uri.tryParse(s.backendUrl ?? '')?.host ?? '';
    final localOnly = host == 'localhost' || host == '127.0.0.1' || host == '::1';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const ThreatIcon(
              icon: Icons.cloud_done_rounded,
              color: AppColors.green,
              size: 52,
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Connected',
                    style: TextStyle(fontSize: 22, fontWeight: FontWeight.w800),
                  ),
                  Text(
                    s.backendUrl ?? '',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(color: AppColors.muted, fontSize: 13.5),
                  ),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: 16),
        Wrap(
          spacing: 8,
          runSpacing: 6,
          children: [
            StatusPill(
              label: 'Engine ${s.engineName ?? ''}'.trim(),
              color: AppColors.primary,
              dot: true,
            ),
            StatusPill(
              label: '${s.messagesScanned} messages',
              color: AppColors.muted,
            ),
          ],
        ),
        const SizedBox(height: 20),
        if (_link == null) ...[
          SizedBox(
            width: double.infinity,
            child: GradientButton(
              label: _busy ? 'Creating link…' : 'Link another phone',
              icon: Icons.phonelink_setup_rounded,
              onPressed: _busy ? () {} : _makeLink,
            ),
          ),
        ] else ...[
          const _Label('Open this on the other phone'),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: AppColors.white(0.07),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: AppColors.white(0.12)),
            ),
            child: SelectableText(
              _link!,
              style: const TextStyle(
                fontSize: 13.5,
                height: 1.4,
                fontWeight: FontWeight.w600,
                color: AppColors.primary,
              ),
            ),
          ),
          const SizedBox(height: 8),
          Text(
            localOnly
                ? 'This address only works on the computer running the server. '
                      'To link a phone, open ThreatGuard using the network '
                      'address the server printed (like 192.168.x.x), then '
                      'create the link again.'
                : 'The link works once and expires in 10 minutes. The other '
                      'phone must be able to reach the same server address.',
            style: TextStyle(
              color: localOnly ? AppColors.orange : AppColors.muted,
              fontSize: 12.5,
              height: 1.4,
            ),
          ),
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            child: GhostButton(
              label: 'Copy link',
              icon: Icons.copy_rounded,
              onPressed: () async {
                await Clipboard.setData(ClipboardData(text: _link!));
                if (mounted) showToast(context, 'Link copied');
              },
            ),
          ),
        ],
        if (_error != null) ...[
          const SizedBox(height: 10),
          Text(
            _error!,
            style: const TextStyle(color: AppColors.orange, fontSize: 13),
          ),
        ],
        const SizedBox(height: 10),
        SizedBox(
          width: double.infinity,
          child: GhostButton(
            label: 'Disconnect this device',
            icon: Icons.link_off_rounded,
            onPressed: () async {
              final nav = Navigator.of(context);
              await s.backend?.disconnect();
              nav.pop();
            },
          ),
        ),
        const SizedBox(height: 8),
        const Text(
          'Disconnecting removes the saved key and the message history from '
          'this device. The server keeps its copy.',
          style: TextStyle(color: AppColors.muted, fontSize: 12, height: 1.4),
        ),
      ],
    );
  }
}

// --------------------------------------------------------- phone messages

/// Asks to read the phone's own text messages (Android). Says plainly where
/// they go before the system permission dialog appears.
void showSmsAccessSheet(BuildContext context) {
  final state = context.read<GuardState>();
  if (!state.connected) {
    showConnectSheet(context);
    return;
  }
  showGlassSheet<void>(context, builder: (_) => const _SmsAccessSheet());
}

class _SmsAccessSheet extends StatefulWidget {
  const _SmsAccessSheet();

  @override
  State<_SmsAccessSheet> createState() => _SmsAccessSheetState();
}

class _SmsAccessSheetState extends State<_SmsAccessSheet> {
  bool _busy = false;
  bool _asked = false;

  Future<void> _allow() async {
    final backend = context.read<GuardState>().backend;
    if (backend == null || _busy) return;
    setState(() => _busy = true);
    await backend.requestDeviceSms();
    if (!mounted) return;
    setState(() {
      _busy = false;
      _asked = true;
    });
  }

  @override
  Widget build(BuildContext context) {
    final s = context.watch<GuardState>();
    final granted = s.deviceSms == DeviceSmsAccess.granted;
    final denied = _asked && !granted;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            ThreatIcon(
              icon: granted ? Icons.mark_email_read_rounded : Icons.sms_rounded,
              color: granted ? AppColors.green : AppColors.primary,
              size: 52,
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Text(
                granted ? 'Texts are being checked' : 'Check your texts',
                style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w800),
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        Text(
          granted
              ? 'ThreatGuard reads your recent text messages and checks each new '
                    'one as it arrives, even when the app is closed.'
              : 'Allow ThreatGuard to read your text messages so it can check '
                    'them for scams, including new ones as they arrive.',
          style: const TextStyle(color: AppColors.muted, fontSize: 13.5, height: 1.4),
        ),
        const SizedBox(height: 14),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: AppColors.white(0.07),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: AppColors.white(0.12)),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Icon(Icons.lock_outline_rounded, size: 18, color: AppColors.primary),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  'Your messages are sent only to your own server '
                  '(${s.backendUrl ?? 'your server'}) and nowhere else. '
                  'The server keeps a copy so you can see your history. You can '
                  'delete messages in the app, or turn this off in Android settings.',
                  style: const TextStyle(fontSize: 13, height: 1.4),
                ),
              ),
            ],
          ),
        ),
        if (denied) ...[
          const SizedBox(height: 12),
          const Text(
            'Android did not allow it. If you chose "Don\'t allow", Android will '
            'not ask again. Turn on SMS for ThreatGuard in Android settings.',
            style: TextStyle(color: AppColors.orange, fontSize: 13, height: 1.4),
          ),
        ],
        const SizedBox(height: 20),
        if (granted)
          SizedBox(
            width: double.infinity,
            child: GradientButton(
              label: 'Done',
              icon: Icons.check_rounded,
              onPressed: () => Navigator.of(context).pop(),
            ),
          )
        else ...[
          SizedBox(
            width: double.infinity,
            child: GradientButton(
              label: _busy ? 'Waiting…' : 'Allow SMS access',
              icon: Icons.sms_rounded,
              onPressed: _busy ? () {} : _allow,
            ),
          ),
          if (denied) ...[
            const SizedBox(height: 10),
            SizedBox(
              width: double.infinity,
              child: GhostButton(
                label: 'Open Android settings',
                icon: Icons.settings_rounded,
                onPressed: () => s.backend?.openDeviceSmsSettings(),
              ),
            ),
          ],
        ],
      ],
    );
  }
}

// ------------------------------------------------------------ check message

/// Paste a message to have the server analyze it and add it to history.
void showCheckMessageSheet(BuildContext context) {
  final state = context.read<GuardState>();
  if (state.demoMode) {
    showToast(context, 'Turn off demo mode in Settings to check a message.');
    return;
  }
  if (!state.connected) {
    showConnectSheet(context);
    return;
  }
  showGlassSheet<void>(
    context,
    builder: (_) => _KeyboardPad(child: _CheckSheet(screen: context)),
  );
}

class _CheckSheet extends StatefulWidget {
  /// The screen that opened the sheet. It outlives the sheet, so the
  /// analysis page can be opened from it once the sheet closes.
  const _CheckSheet({required this.screen});
  final BuildContext screen;

  @override
  State<_CheckSheet> createState() => _CheckSheetState();
}

class _CheckSheetState extends State<_CheckSheet> {
  final _sender = TextEditingController();
  final _body = TextEditingController();
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _sender.dispose();
    _body.dispose();
    super.dispose();
  }

  Future<void> _paste() async {
    final data = await Clipboard.getData(Clipboard.kTextPlain);
    final text = data?.text;
    if (text != null && text.trim().isNotEmpty) {
      setState(() => _body.text = text.trim());
    }
  }

  Future<void> _analyze() async {
    final backend = context.read<GuardState>().backend;
    final text = _body.text.trim();
    if (backend == null || _busy) return;
    if (text.isEmpty) {
      setState(() => _error = 'Paste or type the message first.');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final message = await backend.checkMessage(_sender.text.trim(), text);
      if (!mounted) return;
      final screen = widget.screen;
      Navigator.of(context).pop();
      if (screen.mounted) openAnalysis(screen, message);
    } catch (e) {
      if (mounted) {
        setState(() {
          _busy = false;
          _error = e.toString();
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Check a message',
          style: TextStyle(fontSize: 22, fontWeight: FontWeight.w800),
        ),
        const SizedBox(height: 4),
        const Text(
          'Got something suspicious? Paste it here. ThreatGuard explains the '
          'risk and keeps it in your history.',
          style: TextStyle(color: AppColors.muted, fontSize: 13.5, height: 1.4),
        ),
        const SizedBox(height: 18),
        const _Label('Sender (optional)'),
        _Field(
          controller: _sender,
          hint: 'Name or number',
          icon: Icons.person_rounded,
          maxLength: 100,
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            const Expanded(child: _Label('Message')),
            GestureDetector(
              onTap: _paste,
              behavior: HitTestBehavior.opaque,
              child: const Padding(
                padding: EdgeInsets.fromLTRB(12, 4, 4, 10),
                child: Text(
                  'Paste',
                  style: TextStyle(
                    color: AppColors.primary,
                    fontWeight: FontWeight.w700,
                    fontSize: 13,
                  ),
                ),
              ),
            ),
          ],
        ),
        _Field(
          controller: _body,
          hint: 'Paste the message text',
          lines: 5,
          maxLength: 2000,
          autofocus: true,
        ),
        if (_error != null) ...[
          const SizedBox(height: 10),
          Text(
            _error!,
            style: const TextStyle(color: AppColors.orange, fontSize: 13),
          ),
        ],
        const SizedBox(height: 18),
        SizedBox(
          width: double.infinity,
          child: GradientButton(
            label: _busy ? 'Analyzing…' : 'Analyze message',
            icon: Icons.radar_rounded,
            onPressed: _busy ? () {} : _analyze,
          ),
        ),
      ],
    );
  }
}
