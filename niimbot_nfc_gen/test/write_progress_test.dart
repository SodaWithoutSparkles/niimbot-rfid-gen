// Progress reporting during a write.

import 'dart:typed_data';

import 'package:niimbot_nfc_gen/core/generator.dart';
import 'package:niimbot_nfc_gen/core/nfc/tag_session.dart';
import 'package:niimbot_nfc_gen/core/nfc/write_plan.dart';
import 'package:niimbot_nfc_gen/core/nfc/write_progress.dart';
import 'package:niimbot_nfc_gen/core/nfc/write_runner.dart';
import 'package:test/test.dart';

/// A tag that accepts everything, with optional per-page refusals.
class ScriptedTag implements TagSession {
  final Set<int> rejectWrites;
  List<int>? password;

  ScriptedTag({this.rejectWrites = const {}, this.password});

  @override
  final TagInfo tag =
      TagInfo(uid: Uint8List.fromList([1, 2, 3, 4, 5, 6, 7]), pageCount: 45);

  int revives = 0;
  bool _unlocked = false;

  @override
  Future<Uint8List> transceive(Uint8List command, {Duration? timeout}) async {
    switch (command[0]) {
      case 0x1b:
        final candidate = command.sublist(1, 5);
        if (password == null || candidate.join() != password!.join()) {
          throw const NfcException(NfcErrorKind.comms, 'Tag not responded');
        }
        _unlocked = true;
        return Uint8List.fromList([0, 0]);

      case 0x30:
        return Uint8List(16);

      case 0xa2:
        final page = command[1];
        if (password != null && !_unlocked) {
          throw const NfcException(NfcErrorKind.comms, 'Tag not responded');
        }
        if (rejectWrites.contains(page)) {
          throw const NfcException(NfcErrorKind.comms, 'Tag not responded');
        }
        return Uint8List(0);

      default:
        return Uint8List(0);
    }
  }

  @override
  Future<void> revive() async {
    revives++;
    _unlocked = false;
  }

  @override
  Future<void> close() async {}
}

List<PagePlan> plan() => buildWritePlan(Uint8List(180), TagType.ntag213);

void main() {
  test('a write reports every phase', () async {
    final seen = <WriteProgress>[];
    await WriteRunner.run(
      ScriptedTag(),
      plan(),
      onProgress: seen.add,
    );

    final phases = seen.map((p) => p.phase).toSet();
    expect(
      phases,
      containsAll(<WritePhase>[
        WritePhase.probing,
        WritePhase.writing,
        WritePhase.verifying,
        WritePhase.done,
      ]),
    );
  });

  test('progress starts near zero and ends at one', () async {
    final seen = <WriteProgress>[];
    await WriteRunner.run(ScriptedTag(), plan(), onProgress: seen.add);

    expect(seen.first.fraction, lessThan(0.05));
    expect(seen.last.phase, WritePhase.done);
    expect(seen.last.fraction, 1);
  });

  test('the fraction only ever moves forwards', () async {
    final seen = <WriteProgress>[];
    await WriteRunner.run(
      ScriptedTag(rejectWrites: const {43, 44}),
      plan(),
      onProgress: seen.add,
    );

    for (var i = 1; i < seen.length; i++) {
      expect(
        seen[i].fraction,
        greaterThanOrEqualTo(seen[i - 1].fraction - 0.0001),
        reason: 'went backwards at tick $i',
      );
    }
  });

  test('writing reports a page counter that reaches the total', () async {
    final seen = <WriteProgress>[];
    await WriteRunner.run(ScriptedTag(), plan(), onProgress: seen.add);

    final writing = seen.where((p) => p.phase == WritePhase.writing).toList();
    expect(writing, isNotEmpty);
    expect(writing.first.message, contains('page 2 of 34'));
    expect(writing.last.message, contains('page 34 of 34'));
  });

  test('verifying reports its own counter', () async {
    final seen = <WriteProgress>[];
    await WriteRunner.run(ScriptedTag(), plan(), onProgress: seen.add);

    final verifying = seen.where((p) => p.phase == WritePhase.verifying).toList();
    expect(verifying, isNotEmpty);
    expect(verifying.first.message, contains('1 of 34'));
    expect(verifying.last.message, contains('34 of 34'));
    // Verify steps advance the global counter monotonically.
    for (var i = 1; i < verifying.length; i++) {
      expect(verifying[i].done, greaterThanOrEqualTo(verifying[i - 1].done));
    }
  });

  test('a revive is reported, because that is where the wait happens',
      () async {
    final seen = <WriteProgress>[];
    await WriteRunner.run(
      ScriptedTag(rejectWrites: const {43, 44}),
      plan(),
      onProgress: seen.add,
    );

    final reviving = seen.where((p) => p.phase == WritePhase.reviving);
    expect(reviving, isNotEmpty);
    expect(reviving.first.message, contains('hold it against the phone'));
  });

  test('authenticating is reported with a counter', () async {
    final seen = <WriteProgress>[];
    await WriteRunner.run(
      ScriptedTag(password: Uint8List.fromList([0x12, 0x34, 0x56, 0x78])),
      plan(),
      password: Uint8List.fromList([0xde, 0xad, 0xbe, 0xef]),
      onProgress: seen.add,
    );

    final auth = seen.where((p) => p.phase == WritePhase.authenticating);
    expect(auth, isNotEmpty);
    expect(auth.first.message, contains('Trying passwords'));
  });

  test('every emitted tick carries a non-empty message', () async {
    final seen = <WriteProgress>[];
    await WriteRunner.run(
      ScriptedTag(
        rejectWrites: const {43, 44},
        password: Uint8List.fromList([0x12, 0x34, 0x56, 0x78]),
      ),
      plan(),
      password: Uint8List.fromList([0xde, 0xad, 0xbe, 0xef]),
      onProgress: seen.add,
    );

    expect(seen, isNotEmpty);
    for (final tick in seen) {
      expect(tick.message, isNotEmpty, reason: tick.phase.name);
    }
    // The phases a user actually sees on a run with auth and a revive.
    expect(
      seen.map((p) => p.phase).toSet(),
      containsAll(<WritePhase>[
        WritePhase.probing,
        WritePhase.authenticating,
        WritePhase.writing,
        WritePhase.reviving,
        WritePhase.verifying,
        WritePhase.done,
      ]),
    );
  });

  test('a callback that throws does not break the write', () async {
    // A UI bug in a progress listener must not abort a tag write.
    final report = await WriteRunner.run(
      ScriptedTag(),
      plan(),
      onProgress: (_) => throw StateError('listener blew up'),
    );
    expect(report.isSuccess, isTrue);
    expect(report.writtenCount, 34);
  });

  test('no callback is fine', () async {
    final report = await WriteRunner.run(ScriptedTag(), plan());
    expect(report.isSuccess, isTrue);
  });
}