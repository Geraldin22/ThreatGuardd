import 'dart:convert';
import 'dart:io';

import 'package:threatguard_core/threatguard_core.dart';

const maxMessages = 5000;
const maxBodyLength = 2000;
const maxSenderLength = 100;

class Settings {
  Settings({
    this.monitoring = true,
    this.autoBlock = true,
    this.linkScanning = true,
    this.alerts = true,
    this.shareIntel = false,
    this.sensitivity = Sensitivity.balanced,
  });

  bool monitoring, autoBlock, linkScanning, alerts, shareIntel;
  Sensitivity sensitivity;

  static const boolKeys = [
    'monitoring',
    'autoBlock',
    'linkScanning',
    'alerts',
    'shareIntel',
  ];

  bool _bool(String key) => switch (key) {
    'monitoring' => monitoring,
    'autoBlock' => autoBlock,
    'linkScanning' => linkScanning,
    'alerts' => alerts,
    _ => shareIntel,
  };

  void _setBool(String key, bool v) {
    switch (key) {
      case 'monitoring':
        monitoring = v;
      case 'autoBlock':
        autoBlock = v;
      case 'linkScanning':
        linkScanning = v;
      case 'alerts':
        alerts = v;
      default:
        shareIntel = v;
    }
  }

  Map<String, Object?> toJson() => {
    for (final k in boolKeys) k: _bool(k),
    'sensitivity': sensitivity.name,
  };

  factory Settings.fromJson(Map<String, Object?> json) {
    final s = Settings();
    for (final k in boolKeys) {
      if (json[k] is bool) s._setBool(k, json[k] as bool);
    }
    s.sensitivity = Sensitivity.parse(json['sensitivity']) ?? s.sensitivity;
    return s;
  }

  /// Applies a partial update. Returns an error message if any field is of
  /// the wrong type; nothing is changed in that case.
  String? validate(Map<String, Object?> patch) {
    for (final k in boolKeys) {
      if (patch.containsKey(k) && patch[k] is! bool) return '$k must be true or false';
    }
    if (patch.containsKey('sensitivity') &&
        Sensitivity.parse(patch['sensitivity']) == null) {
      return 'sensitivity must be relaxed, balanced or strict';
    }
    return null;
  }

  /// True when the engine's output could change (so history must be
  /// re-analyzed).
  bool apply(Map<String, Object?> patch) {
    final before = (sensitivity, linkScanning);
    for (final k in boolKeys) {
      if (patch[k] is bool) _setBool(k, patch[k] as bool);
    }
    sensitivity = Sensitivity.parse(patch['sensitivity']) ?? sensitivity;
    return before != (sensitivity, linkScanning);
  }

  /// How much of the available protection is switched on. Derived from the
  /// settings, so it is always explainable.
  int get protectionScore =>
      40 + // engine online (we are answering)
      (monitoring ? 25 : 0) +
      (autoBlock ? 15 : 0) +
      (linkScanning ? 10 : 0) +
      switch (sensitivity) {
        Sensitivity.strict => 10,
        Sensitivity.balanced => 8,
        Sensitivity.relaxed => 4,
      };
}

class StoredMessage {
  StoredMessage({
    required this.id,
    required this.sender,
    required this.body,
    required this.receivedAt,
    required this.source,
    required this.analysis,
    required this.action,
  });

  final int id;
  final String sender, body, source;
  final DateTime receivedAt;
  Analysis analysis;

  /// What the sender-side client should do with it: allow, flag or block.
  String action;

  Map<String, Object?> toJson() => {
    'id': id,
    'sender': sender,
    'body': body,
    'receivedAt': receivedAt.toUtc().toIso8601String(),
    'source': source,
    'action': action,
    ...analysis.toJson(),
  };

  factory StoredMessage.fromJson(Map<String, Object?> j) {
    final text = j['body'] as String;
    return StoredMessage(
      id: j['id'] as int,
      sender: j['sender'] as String,
      body: text,
      receivedAt: DateTime.parse(j['receivedAt'] as String),
      source: (j['source'] as String?) ?? 'forward',
      action: (j['action'] as String?) ?? 'allow',
      // The analysis is re-derived on load so an engine upgrade takes effect
      // without migrating data.
      analysis: ThreatEngine.analyze(text),
    );
  }
}

/// All persistent state. One owner, one file; every change is written to disk
/// before the call returns.
class Store {
  Store._(this._file);

  /// Opens (or creates) the store at [dir]/store.json. Pass null for a
  /// memory-only store (used by tests).
  static Store open(String? dir) {
    final file = dir == null ? null : File('$dir/store.json');
    final store = Store._(file);
    if (file != null && file.existsSync()) store._load();
    return store;
  }

  final File? _file;
  final String _boot = DateTime.now().millisecondsSinceEpoch.toRadixString(36);
  int _rev = 0;

  /// Changes whenever anything stored changes. Clients send the last value
  /// they saw so an unchanged store costs a few bytes, not the whole history.
  String get revision => '$_boot.$_rev';

  final Settings settings = Settings();
  final Set<String> _blocked = {};
  final List<StoredMessage> _messages = []; // newest first
  int _nextId = 1;

  List<StoredMessage> get messages => List.unmodifiable(_messages);
  List<String> get blocked => (_blocked.toList()..sort());
  bool isBlocked(String sender) => _blocked.contains(sender);

  Analysis _analyze(String text) => ThreatEngine.analyze(
    text,
    sensitivity: settings.sensitivity,
    scanLinks: settings.linkScanning,
  );

  String _actionFor(Analysis a, String sender) {
    if (_blocked.contains(sender) ||
        (settings.autoBlock && a.band == RiskBand.high)) {
      return 'block';
    }
    return a.band == RiskBand.low ? 'allow' : 'flag';
  }

  Analysis analyze(String text) => _analyze(text);

  /// Messages from a phone's inbox are identified by who sent them, when,
  /// and what they said, so importing the same inbox twice adds nothing.
  static String _dedupeKey(String sender, DateTime at, String body) =>
      '$sender\u0000${at.toUtc().millisecondsSinceEpoch}\u0000$body';

  /// The stored copy of a message, if this exact one was already added.
  StoredMessage? findDuplicate(String sender, DateTime at, String body) {
    final key = _dedupeKey(sender, at, body);
    for (final m in _messages) {
      if (m.receivedAt.millisecondsSinceEpoch == at.millisecondsSinceEpoch &&
          _dedupeKey(m.sender, m.receivedAt, m.body) == key) {
        return m;
      }
    }
    return null;
  }

  StoredMessage _insert({
    required String sender,
    required String body,
    required String source,
    DateTime? receivedAt,
  }) {
    final analysis = _analyze(body);
    final msg = StoredMessage(
      id: _nextId++,
      sender: sender,
      body: body,
      receivedAt: receivedAt ?? DateTime.now().toUtc(),
      source: source,
      analysis: analysis,
      action: _actionFor(analysis, sender),
    );
    // Newest first by the time the message was received, not the time it
    // reached the server, so an imported old message sits where it belongs.
    var i = 0;
    while (i < _messages.length && _messages[i].receivedAt.isAfter(msg.receivedAt)) {
      i++;
    }
    _messages.insert(i, msg);
    if (_messages.length > maxMessages) {
      _messages.removeRange(maxMessages, _messages.length);
    }
    return msg;
  }

  /// Adds a message. When [receivedAt] is given and the same message is
  /// already stored, that copy is returned and nothing is added.
  (StoredMessage, {bool created}) add({
    required String sender,
    required String body,
    required String source,
    DateTime? receivedAt,
  }) {
    if (receivedAt != null) {
      final existing = findDuplicate(sender, receivedAt, body);
      if (existing != null) return (existing, created: false);
    }
    final msg = _insert(
      sender: sender,
      body: body,
      source: source,
      receivedAt: receivedAt,
    );
    _save();
    return (msg, created: true);
  }

  /// Adds many messages with one write to disk. Returns how many were new.
  int addAll(List<({String sender, String body, DateTime at})> items, {required String source}) {
    var added = 0;
    for (final it in items) {
      if (findDuplicate(it.sender, it.at, it.body) != null) continue;
      _insert(sender: it.sender, body: it.body, source: source, receivedAt: it.at);
      added++;
    }
    if (added > 0) _save();
    return added;
  }

  bool delete(int id) {
    final before = _messages.length;
    _messages.removeWhere((m) => m.id == id);
    if (_messages.length == before) return false;
    _save();
    return true;
  }

  int clear() {
    final n = _messages.length;
    _messages.clear();
    _save();
    return n;
  }

  void setBlocked(String sender, bool blocked) {
    if (blocked ? _blocked.add(sender) : _blocked.remove(sender)) _save();
  }

  /// Applies a settings patch (already validated). Re-analyzes history when
  /// the change affects scoring.
  void updateSettings(Map<String, Object?> patch) {
    if (settings.apply(patch)) reanalyze(save: false);
    _save();
  }

  /// Re-runs the engine over every stored message with the current settings.
  void reanalyze({bool save = true}) {
    for (final m in _messages) {
      m.analysis = _analyze(m.body);
      m.action = _actionFor(m.analysis, m.sender);
    }
    if (save) _save();
  }

  // ------------------------------------------------------------ persistence
  void _load() {
    final json = jsonDecode(_file!.readAsStringSync()) as Map<String, Object?>;
    settings.apply(
      Map<String, Object?>.from(json['settings'] as Map? ?? const {}),
    );
    _blocked.addAll((json['blocked'] as List? ?? const []).cast<String>());
    _nextId = (json['nextId'] as int?) ?? 1;
    for (final m in (json['messages'] as List? ?? const [])) {
      final msg = StoredMessage.fromJson(Map<String, Object?>.from(m as Map));
      msg.analysis = _analyze(msg.body);
      msg.action = _actionFor(msg.analysis, msg.sender);
      _messages.add(msg);
    }
  }

  void _save() {
    _rev++;
    final file = _file;
    if (file == null) return;
    file.parent.createSync(recursive: true);
    final tmp = File('${file.path}.tmp');
    tmp.writeAsStringSync(
      jsonEncode({
        'nextId': _nextId,
        'settings': settings.toJson(),
        'blocked': blocked,
        'messages': [for (final m in _messages) m.toJson()],
      }),
    );
    tmp.renameSync(file.path); // atomic replace: never a half-written file
  }
}
