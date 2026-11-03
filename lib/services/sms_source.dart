import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import '../models/protection_status.dart';

/// One text message read from the phone's inbox.
class InboxSms {
  const InboxSms({required this.sender, required this.body, required this.at});
  final String sender, body;
  final DateTime at;

  Map<String, Object?> toJson() => {
    'sender': sender,
    'body': body,
    'receivedAt': at.toUtc().toIso8601String(),
  };
}

/// The phone's own SMS inbox. Real on Android; everywhere else it reports
/// [DeviceSmsAccess.unsupported] and never returns messages.
abstract interface class SmsSource {
  Future<DeviceSmsAccess> status();

  /// Shows the Android permission dialog. Returns the resulting state.
  Future<DeviceSmsAccess> request();

  /// The newest [limit] messages, newest first.
  Future<List<InboxSms>> readRecent(int limit);

  /// Gives the background receiver the server address and key it needs to
  /// pass new texts on while the app is closed.
  Future<void> linkServer(String url, String token);
  Future<void> unlinkServer();

  /// Opens this app's page in Android settings (for a permission the user
  /// has said no to, which Android will not ask about again).
  Future<void> openSettings();

  static SmsSource forPlatform() =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.android
      ? AndroidSmsSource()
      : const NoSmsSource();
}

class NoSmsSource implements SmsSource {
  const NoSmsSource();

  @override
  Future<DeviceSmsAccess> status() async => DeviceSmsAccess.unsupported;
  @override
  Future<DeviceSmsAccess> request() async => DeviceSmsAccess.unsupported;
  @override
  Future<List<InboxSms>> readRecent(int limit) async => const [];
  @override
  Future<void> linkServer(String url, String token) async {}
  @override
  Future<void> unlinkServer() async {}
  @override
  Future<void> openSettings() async {}
}

/// Talks to `MainActivity.kt` over the `threatguard/sms` channel.
class AndroidSmsSource implements SmsSource {
  AndroidSmsSource([MethodChannel? channel])
    : _channel = channel ?? const MethodChannel('threatguard/sms');

  final MethodChannel _channel;

  DeviceSmsAccess _access(bool? granted) =>
      granted == true ? DeviceSmsAccess.granted : DeviceSmsAccess.notGranted;

  @override
  Future<DeviceSmsAccess> status() async {
    try {
      return _access(await _channel.invokeMethod<bool>('status'));
    } on MissingPluginException {
      return DeviceSmsAccess.unsupported;
    }
  }

  @override
  Future<DeviceSmsAccess> request() async =>
      _access(await _channel.invokeMethod<bool>('request'));

  @override
  Future<List<InboxSms>> readRecent(int limit) async {
    final rows =
        await _channel.invokeListMethod<Map<Object?, Object?>>('read', {
          'limit': limit,
        }) ??
        const [];
    return [
      for (final r in rows)
        if ((r['body'] as String?)?.trim().isNotEmpty ?? false)
          InboxSms(
            sender: ((r['sender'] as String?)?.trim().isNotEmpty ?? false)
                ? (r['sender'] as String).trim()
                : 'Unknown',
            body: r['body'] as String,
            at: DateTime.fromMillisecondsSinceEpoch(
              (r['date'] as num).toInt(),
              isUtc: true,
            ),
          ),
    ];
  }

  @override
  Future<void> linkServer(String url, String token) async {
    try {
      await _channel.invokeMethod<void>('saveServer', {
        'url': url,
        'token': token,
      });
    } on MissingPluginException {
      // Not running inside the Android app.
    }
  }

  @override
  Future<void> unlinkServer() async {
    try {
      await _channel.invokeMethod<void>('clearServer');
    } on MissingPluginException {
      // Not running inside the Android app.
    }
  }

  @override
  Future<void> openSettings() async {
    try {
      await _channel.invokeMethod<void>('openSettings');
    } on MissingPluginException {
      // Not running inside the Android app.
    }
  }
}
