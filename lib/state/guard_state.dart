import 'package:flutter/foundation.dart';
import 'package:threatguard_core/threatguard_core.dart' show Sensitivity;

import '../data/sms_data.dart';
import '../models/protection_status.dart';
import '../models/sms_message.dart';

export '../models/protection_status.dart';
export 'package:threatguard_core/threatguard_core.dart' show Sensitivity;

/// Backend hook: analyze the messages. The backend implementation reports
/// progress with [GuardState.setScanProgress] and delivers results with
/// [GuardState.setDeviceMessages]. Null until the backend is connected.
typedef ScanHandler = Future<void> Function(GuardState state);

/// Backend hook: ask Android for SMS access and return the outcome.
typedef PermissionHandler = Future<SmsPermission> Function();

/// Where the app stands with its ThreatGuard server.
enum BackendStatus {
  /// No server address known yet.
  notConfigured,
  connecting,
  connected,

  /// The server answered but this device has not been linked to it.
  needsPairing,

  /// A server address is saved but it did not answer.
  unreachable,
}

/// Everything the UI can ask the server to do. Implemented by
/// `BackendConnector`; null until it is installed.
abstract interface class BackendActions {
  /// Links this device. [secret] is a pairing code or the API key. Returns
  /// an error message, or null on success.
  Future<String?> connect(String url, String secret);

  Future<void> disconnect();

  /// Sends one message to be analyzed and stored.
  Future<SmsMessage> checkMessage(String sender, String body);

  Future<void> setBlocked(String sender, bool blocked);
  Future<void> deleteMessage(int id);
  Future<void> clearMessages();

  /// Saves the current preferences to the server.
  void preferencesChanged();

  /// A link (with a fresh one-time code) that links another phone.
  Future<String> newPairingLink();

  /// Tries the saved connection again.
  Future<void> retry();

  /// Asks Android for access to the phone's text messages. Afterwards
  /// [GuardState.deviceSms] says what the user decided.
  Future<void> requestDeviceSms();

  /// Opens this app's page in Android settings.
  Future<void> openDeviceSmsSettings();
}

/// Frontend state for ThreatGuard AI.
///
/// There are three clearly separate groups:
///  * **Preferences**: what the user switched on in Settings. Saved to the
///    server, which applies them.
///  * **Real state**: connection, scan progress, messages from the server.
///    Only the backend sets these (see "backend entry points" below).
///  * **Demo state**: sample messages, shown only while [demoMode] is on.
///
/// Nothing here pretends a feature works. Status text is derived from the
/// real-state fields only.
class GuardState extends ChangeNotifier {
  // ---------------------------------------------------------- preferences
  bool monitoring = true;
  bool autoBlock = true;
  bool linkScanning = true;
  bool alerts = true;
  bool shareIntel = false;
  Sensitivity sensitivity = Sensitivity.balanced;

  // ----------------------------------------------------------- real state
  SmsPermission smsPermission = SmsPermission.notGranted;
  bool engineConnected = false; // detection engine reachable
  bool monitoringRunning = false; // server is analyzing incoming messages
  bool blockingAvailable = false; // the server keeps a block list

  /// Null until a real calculation exists (shown as a neutral placeholder).
  int? protectionScore;

  ScanHandler? scanHandler;
  PermissionHandler? permissionHandler;
  BackendActions? backend;

  /// Whether this phone's own text inbox can be read (Android only). This is
  /// separate from the server connection: both are needed to protect texts
  /// automatically.
  DeviceSmsAccess deviceSms = DeviceSmsAccess.unsupported;

  // -------------------------------------------------------------- backend
  BackendStatus backendStatus = BackendStatus.notConfigured;
  String? backendUrl;
  String? backendError;
  String? engineName;

  /// A problem saving a change to the server. The UI shows it once and
  /// clears it with [clearSyncError].
  String? syncError;

  List<SmsMessage> _deviceMessages = const [];

  // ----------------------------------------------------------- demo state
  bool demoMode = false;
  List<SmsMessage> _demoMessages = const [];

  // ----------------------------------------------------------------- scan
  bool scanning = false;
  double scanProgress = 0; // 0 – 1
  DateTime? lastScan;
  String? scanError;

  // ---------------------------------------------------------- local flags
  final Set<String> _blocked = {};
  bool _disposed = false;

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  // -------------------------------------------------------------- getters
  /// The message list currently shown: demo samples in demo mode, otherwise
  /// the messages delivered by the backend (empty until then).
  List<SmsMessage> get messages =>
      List.unmodifiable(demoMode ? _demoMessages : _deviceMessages);

  bool get hasMessages => messages.isNotEmpty;

  // All statistics are derived from [messages], so they always agree.
  int get messagesScanned => messages.length;
  int get threatCount => messages.where((m) => m.isThreat).length;
  int get totalThreats => threatCount;
  int get safeCount => messagesScanned - threatCount;
  int get highRisk => messages.where((m) => m.risk >= 80).length;

  bool get connected => backendStatus == BackendStatus.connected;

  bool get canScan =>
      !demoMode &&
      smsPermission == SmsPermission.granted &&
      scanHandler != null;

  ProtectionStatus get status {
    if (smsPermission == SmsPermission.unsupported) {
      return ProtectionStatus.notSupported;
    }
    if (smsPermission == SmsPermission.notGranted) {
      return ProtectionStatus.permissionRequired;
    }
    if (scanning) return ProtectionStatus.scanning;
    if (monitoringRunning) return ProtectionStatus.monitoringActive;
    if (lastScan != null) return ProtectionStatus.lastScanCompleted;
    return ProtectionStatus.readyToScan;
  }

  /// Senders blocked by the user. Automatic blocking is only included when
  /// the server keeps a block list ([blockingAvailable]).
  List<String> get blockedSenders {
    final set = <String>{..._blocked};
    if (blockingAvailable && autoBlock) {
      set.addAll(messages.where((m) => m.risk >= 60).map((m) => m.sender));
    }
    return set.toList()..sort();
  }

  bool isBlocked(String sender) => blockedSenders.contains(sender);
  bool isManuallyBlocked(String sender) => _blocked.contains(sender);

  List<SmsMessage> get activity =>
      messages.where((m) => m.isThreat).take(6).toList();

  /// Threats per four-hour block of today (00–04, 04–08 …). Demo mode shows
  /// labelled sample data instead.
  List<int> get dailyTrend {
    if (demoMode) return const [1, 0, 2, 5, 3, 8];
    final now = DateTime.now();
    final start = DateTime(now.year, now.month, now.day);
    final out = List.filled(6, 0);
    for (final m in _deviceMessages) {
      final t = m.receivedAt.toLocal();
      if (m.isThreat && !t.isBefore(start)) out[(t.hour ~/ 4).clamp(0, 5)]++;
    }
    return out;
  }

  /// Threats per day for the last seven days, oldest first.
  List<int> get weeklyTrend {
    if (demoMode) return const [14, 19, 11, 23, 17, 26, 12];
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final out = List.filled(7, 0);
    for (final m in _deviceMessages) {
      if (!m.isThreat) continue;
      final t = m.receivedAt.toLocal();
      final day = DateTime(t.year, t.month, t.day);
      final ago = today.difference(day).inDays;
      if (ago >= 0 && ago < 7) out[6 - ago]++;
    }
    return out;
  }

  List<String> get weekLabels {
    const names = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
    final now = DateTime.now();
    return [
      for (var i = 6; i >= 0; i--)
        names[now.subtract(Duration(days: i)).weekday - 1],
    ];
  }

  List<MapEntry<ThreatCategory, int>> get categoryCounts {
    final map = <ThreatCategory, int>{};
    for (final m in messages) {
      if (m.category == ThreatCategory.safe) continue;
      map[m.category] = (map[m.category] ?? 0) + 1;
    }
    final list = map.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    return list;
  }

  // ------------------------------------------------------ user actions (UI)
  /// Changes a preference and saves it to the server.
  void update(VoidCallback change) {
    change();
    _notify();
    backend?.preferencesChanged();
  }

  void blockSender(String sender) => _setBlocked(sender, true);
  void unblockSender(String sender) => _setBlocked(sender, false);

  void _setBlocked(String sender, bool blocked) {
    if (blocked ? !_blocked.add(sender) : !_blocked.remove(sender)) return;
    _notify();
    final b = backend;
    if (b == null || demoMode) return;
    b.setBlocked(sender, blocked).catchError((Object _) {
      // The server did not take it: undo, so the screen tells the truth.
      if (blocked) {
        _blocked.remove(sender);
      } else {
        _blocked.add(sender);
      }
      reportSyncError('Could not save that change. Check your connection.');
    });
  }

  /// Removes one message from history. Local only in demo mode.
  Future<void> deleteMessage(SmsMessage m) async {
    if (demoMode) {
      _demoMessages = _demoMessages.where((x) => x.id != m.id).toList();
      _notify();
      return;
    }
    final b = backend;
    if (b == null) return;
    try {
      await b.deleteMessage(m.id);
    } catch (_) {
      reportSyncError('Could not delete the message. Check your connection.');
    }
  }

  /// Turns the labelled sample data on or off.
  void setDemoMode(bool on) {
    demoMode = on;
    _demoMessages = on ? initialMessages() : const [];
    _notify();
  }

  /// Reloads the sample data (demo mode only).
  void reset() {
    _blocked.clear();
    if (demoMode) _demoMessages = initialMessages();
    _notify();
  }

  /// True once the backend has provided a permission handler.
  bool get canRequestPermission => permissionHandler != null;

  Future<void> requestSmsPermission() async {
    final handler = permissionHandler;
    if (handler == null) return;
    smsPermission = await handler();
    _notify();
  }

  /// Runs the backend scan. Does nothing until a [scanHandler] is connected.
  Future<void> runScan() async {
    final handler = scanHandler;
    if (scanning || !canScan || handler == null) return;
    scanning = true;
    scanProgress = 0;
    scanError = null;
    _notify();
    try {
      await handler(this);
      scanProgress = 1;
      lastScan = DateTime.now();
    } catch (_) {
      scanError = 'The scan could not be completed. Check your connection.';
    } finally {
      scanning = false;
      _notify();
    }
  }

  Future<void> refresh() async {
    if (canScan) await runScan();
  }

  void clearSyncError() => syncError = null;

  // ------------------------------------------------ backend entry points
  // The backend calls these. The UI rebuilds automatically.

  void reportSyncError(String message) {
    syncError = message;
    _notify();
  }

  void setBackendStatus(
    BackendStatus status, {
    String? url,
    String? error,
  }) {
    backendStatus = status;
    backendUrl = url ?? backendUrl;
    backendError = error;
    if (status != BackendStatus.connected) {
      // Without a server there is no engine, monitoring or block list.
      smsPermission = SmsPermission.notGranted;
      engineConnected = false;
      monitoringRunning = false;
      blockingAvailable = false;
      protectionScore = null;
    }
    _notify();
  }

  /// Applies a snapshot from the server: preferences, block list, messages
  /// and the derived flags, in one rebuild.
  void applyServerState({
    required Map<String, Object?> settings,
    required List<String> blocked,
    required List<SmsMessage> messages,
    required int protectionScore,
    required String engine,
    bool includeSettings = true,
  }) {
    if (includeSettings) {
      monitoring = settings['monitoring'] as bool? ?? monitoring;
      autoBlock = settings['autoBlock'] as bool? ?? autoBlock;
      linkScanning = settings['linkScanning'] as bool? ?? linkScanning;
      alerts = settings['alerts'] as bool? ?? alerts;
      shareIntel = settings['shareIntel'] as bool? ?? shareIntel;
      sensitivity =
          Sensitivity.parse(settings['sensitivity']) ?? sensitivity;
    }
    _blocked
      ..clear()
      ..addAll(blocked);
    _deviceMessages = List.of(messages);
    this.protectionScore = protectionScore;
    engineName = engine;
    smsPermission = SmsPermission.granted;
    engineConnected = true;
    blockingAvailable = true;
    monitoringRunning = (settings['monitoring'] as bool?) ?? monitoring;
    backendStatus = BackendStatus.connected;
    backendError = null;
    _notify();
  }

  void setDeviceSms(DeviceSmsAccess value) {
    if (deviceSms == value) return;
    deviceSms = value;
    _notify();
  }

  void setSmsPermission(SmsPermission value) {
    smsPermission = value;
    _notify();
  }

  void setEngineConnected(bool value) {
    engineConnected = value;
    _notify();
  }

  void setMonitoringRunning(bool value) {
    monitoringRunning = value;
    _notify();
  }

  void setBlockingAvailable(bool value) {
    blockingAvailable = value;
    _notify();
  }

  void setProtectionScore(int? value) {
    protectionScore = value;
    _notify();
  }

  void setScanProgress(double value) {
    scanning = true;
    scanProgress = value.clamp(0.0, 1.0).toDouble();
    _notify();
  }

  /// Replaces the real message list with the latest analyzed messages.
  void setDeviceMessages(List<SmsMessage> value) {
    _deviceMessages = List.of(value);
    _notify();
  }

  /// Adds one newly analyzed message at the top of the real list.
  void addDeviceMessage(SmsMessage message) {
    _deviceMessages = [message, ..._deviceMessages];
    _notify();
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}
