// Bounded in-memory transaction log.
//
// Everything the app wants to show in the log screen lands here. Debug-level
// messages only exist in debug builds, so release builds stay silent even when
// the call sites are in a hot loop.

import 'dart:async';
import 'dart:collection';

import 'package:flutter/foundation.dart';

enum LogLevel {
  debug('DEBUG'),
  info('INFO'),
  warn('WARN'),
  error('ERROR');

  const LogLevel(this.label);

  final String label;
}

class LogEntry {
  final LogLevel level;
  final String message;

  /// Wall clock, for the human reading the log screen.
  final DateTime time;

  /// Milliseconds since the log was created. Monotonic, so elapsed times never
  /// jump when the device clock is adjusted.
  final int elapsedMs;

  const LogEntry({
    required this.level,
    required this.message,
    required this.time,
    required this.elapsedMs,
  });

  @override
  String toString() =>
      '[${elapsedMs.toString().padLeft(8)}ms] ${level.label} $message';
}

class Log {
  /// Oldest entries are dropped past this count.
  static const int maxEntries = 5000;

  static final Log _instance = Log._();

  /// The process-wide log.
  static Log get instance => _instance;

  final Stopwatch _stopwatch = Stopwatch()..start();
  final Queue<LogEntry> _entries = Queue<LogEntry>();
  final StreamController<LogEntry> _controller =
      StreamController<LogEntry>.broadcast();

  Log._();

  /// Whether debug messages are worth building. Gate hot call sites on this so
  /// the message string is never interpolated in a release build.
  bool get debugEnabled => kDebugMode;

  /// Fires for every entry as it is recorded.
  Stream<LogEntry> get stream => _controller.stream;

  /// Snapshot of the retained entries, oldest first.
  List<LogEntry> get entries => List<LogEntry>.unmodifiable(_entries);

  /// Snapshot of the retained entries at [level] or above.
  List<LogEntry> entriesAtLeast(LogLevel level) =>
      _entries.where((e) => e.level.index >= level.index).toList();

  void clear() => _entries.clear();

  void d(String message) => _add(LogLevel.debug, message);

  void i(String message) => _add(LogLevel.info, message);

  void w(String message) => _add(LogLevel.warn, message);

  void e(String message) => _add(LogLevel.error, message);

  /// Records a debug message, building [message] only in debug builds. Use
  /// this instead of [d] when building the message costs something.
  void debug(String Function() message) {
    if (!kDebugMode) return;
    _add(LogLevel.debug, message());
  }

  void _add(LogLevel level, String message) {
    final entry = LogEntry(
      level: level,
      message: message,
      time: DateTime.now(),
      elapsedMs: _stopwatch.elapsedMilliseconds,
    );
    _entries.addLast(entry);
    while (_entries.length > maxEntries) {
      _entries.removeFirst();
    }
    _controller.add(entry);
    if (level == LogLevel.debug && kDebugMode) {
      debugPrint(entry.toString());
    }
  }
}

final Log log = Log.instance;

/// Records a debug-level message that is only built in debug builds.
///
/// Prefer this over [Log.d] at call sites inside hot loops: the interpolated
/// string is never constructed in a release build.
void debugLog(String Function() message) => Log.instance.debug(message);