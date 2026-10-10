// Tests for the bounded transaction log.

import 'package:niimbot_nfc_gen/core/log.dart';
import 'package:test/test.dart';

void main() {
  setUp(log.clear);

  test('keeps every entry until the cap, then drops the oldest', () {
    for (var i = 0; i < Log.maxEntries; i++) {
      log.i('entry $i');
    }
    expect(log.entries.length, Log.maxEntries);

    log.i('one too many');
    expect(log.entries.length, Log.maxEntries);
    expect(log.entries.first.message, 'entry 1');
    expect(log.entries.last.message, 'one too many');
  });

  test('entries are readable at a given level or above', () {
    log.d('d');
    log.i('i');
    log.w('w');
    log.e('e');

    expect(
      log.entriesAtLeast(LogLevel.warn).map((e) => e.message),
      ['w', 'e'],
    );
    expect(log.entriesAtLeast(LogLevel.debug).length, 4);
    expect(log.entriesAtLeast(LogLevel.error).length, 1);
  });

  test('every level is emitted on the stream', () async {
    final seen = <LogEntry>[];
    final sub = log.stream.listen(seen.add);

    log.d('d');
    log.i('i');
    log.w('w');
    log.e('e');
    await Future<void>.delayed(Duration.zero);

    expect(seen.map((e) => e.level), LogLevel.values);
    expect(seen.map((e) => e.message), ['d', 'i', 'w', 'e']);
    await sub.cancel();
  });

  test('entries carry a timestamp and a monotonic offset', () {
    final before = DateTime.now();
    log.i('first');
    final after = DateTime.now();

    final entry = log.entries.single;
    expect(entry.time.isBefore(before), isFalse);
    expect(entry.time.isAfter(after), isFalse);
    expect(entry.elapsedMs, greaterThanOrEqualTo(0));
  });

  test('clear empties the buffer', () {
    log.i('a');
    log.clear();
    expect(log.entries, isEmpty);
  });
}