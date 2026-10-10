// WriteRunner against a fake tag.

import 'dart:typed_data';

import 'package:niimbot_nfc_gen/core/generator.dart';
import 'package:niimbot_nfc_gen/core/nfc/tag_session.dart';
import 'package:niimbot_nfc_gen/core/nfc/write_plan.dart';
import 'package:niimbot_nfc_gen/core/nfc/write_runner.dart';
import 'package:test/test.dart';

Uint8List bytes(List<int> values) => Uint8List.fromList(values);

/// A tag that answers with whatever the test tells it to.
class FakeTag implements TagSession {
  /// Pages that reject a write, like the real password and pack pages.
  final Set<int> rejectWrites = {};

  /// Pages that answer a read with bytes that differ from the written value.
  final Map<int, List<int>> corruptOnRead = {};

  /// Pages whose read fails outright.
  final Set<int> unreadable = {};

  /// Password that PWD_AUTH accepts. Null means nothing is accepted.
  List<int>? password;

  /// Auth attempts seen, so the loop can be checked against the tag's counter.
  final List<List<int>> authAttempts = [];

  /// Pages that got a READ immediately before their WRITE.
  final List<int> readBeforeWrite = [];

  /// Commands issued as WRITE.
  final List<int> writes = [];

  /// The bytes each WRITE carried.
  final Map<int, List<int>> writtenBytes = {};

  /// Every command, in order, as `READ 41`, `WRITE 5`, `PWD_AUTH`.
  final List<String> commands = [];

  int revives = 0;
  int closed = 0;

  /// Set to have revive() fail.
  NfcException? reviveError;

  /// Set to have every transceive fail with this instead.
  NfcException? fatalError;

  /// The page the last command read, so a WRITE can tell whether it was a
  /// read-modify-write or a straight full-page write.
  int? _pendingRead;

  @override
  TagInfo tag = TagInfo(uid: bytes([1, 2, 3, 4, 5, 6, 7]), pageCount: 45);

  @override
  Future<Uint8List> transceive(Uint8List command, {Duration? timeout}) async {
    if (fatalError != null) throw fatalError!;

    switch (command[0]) {
      case 0x1b: // PWD_AUTH
        commands.add('PWD_AUTH');
        _pendingRead = null;
        final candidate = command.sublist(1, 5);
        authAttempts.add(candidate);
        if (password == null) throw _nak();
        if (!_same(candidate, password!)) throw _nak();
        return bytes([0x00, 0x00]); // PACK

      case 0x30: // READ
        final page = command[1];
        commands.add('READ $page');
        _pendingRead = page;
        if (unreadable.contains(page)) throw _nak();
        return bytes(corruptOnRead[page] ?? List.filled(16, 0x00));

      case 0xa2: // WRITE
        final page = command[1];
        commands.add('WRITE $page');
        if (_pendingRead == page) readBeforeWrite.add(page);
        _pendingRead = null;
        if (rejectWrites.contains(page)) throw _nak();
        writes.add(page);
        writtenBytes[page] = command.sublist(2, 6);
        return Uint8List(0); // Android swallows the ACK

      default:
        _pendingRead = null;
        return Uint8List(0);
    }
  }

  @override
  Future<void> revive() async {
    if (reviveError != null) throw reviveError!;
    revives++;
  }

  @override
  Future<void> close() async => closed++;

  static NfcException _nak() =>
      const NfcException(NfcErrorKind.comms, 'Tag not responded');

  static bool _same(List<int> a, List<int> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }
}

/// The real NTAG213 plan, so the tests exercise the production layout.
List<PagePlan> ntag213Plan() => buildWritePlan(Uint8List(180), TagType.ntag213);

/// Pages the tag is expected to reject on real NTAG213 hardware.
const hardwareRejected = {43, 44};

void main() {
  group('happy path', () {
    test('every page is written and verified, no warnings', () async {
      final tag = FakeTag();
      final plan = ntag213Plan();

      final report = await WriteRunner.run(tag, plan, autoTryKnownPasswords: false);

      expect(report.isSuccess, isTrue);
      expect(report.fatalError, isNull);
      expect(report.warnings, isEmpty);
      expect(report.outcomes.length, 34);
      expect(report.writtenCount, 34);
      expect(report.failedCount, 0);
      expect(report.mismatchedCount, 0);
      expect(tag.writes, plan.map((p) => p.page).toList());
    });

    test('full pages are written without a read first', () async {
      final tag = FakeTag();
      final plan = ntag213Plan();
      await WriteRunner.run(tag, plan, autoTryKnownPasswords: false);

      // Only the three partial pages (41, 42, 44) get a read-modify-write.
      expect(tag.readBeforeWrite, [41, 42, 44]);
    });

    test('page 43 is written with the generator password bytes', () async {
      // For an NTAG213, write-mask offsets 172..177 are physical bytes
      // 172..177, so this is the password and pack pair from the image.
      final memory = Uint8List(180);
      memory.setRange(172, 178, [0x12, 0x34, 0x56, 0x78, 0x55, 0x55]);

      final tag = FakeTag();
      await WriteRunner.run(
        tag,
        buildWritePlan(memory, TagType.ntag213),
        autoTryKnownPasswords: false,
      );

      expect(tag.writtenBytes[43], [0x12, 0x34, 0x56, 0x78]);
      expect(tag.writtenBytes[44], [0x55, 0x55, 0x00, 0x00]);
    });
  });

  group('the real hardware rejects pages 43 and 44', () {
    late FakeTag tag;
    late WriteReport report;

    setUp(() async {
      tag = FakeTag()..rejectWrites.addAll(hardwareRejected);
      report = await WriteRunner.run(
        tag,
        ntag213Plan(),
        autoTryKnownPasswords: false,
      );
    });

    test('it is still a success', () {
      expect(report.isSuccess, isTrue);
      expect(report.fatalError, isNull);
    });

    test('exactly two pages fail, with exactly the two warnings', () {
      expect(report.failedCount, 2);
      expect(report.warnings, [
        'block 43 could not be written (protected)',
        'block 44 could not be written (protected)',
      ]);
    });

    test('the thirty-two payload pages are unaffected', () {
      expect(report.writtenCount, 32);
      expect(tag.writes, isNot(contains(43)));
      expect(tag.writes, isNot(contains(44)));
    });

    test('one revive is spent between the two rejections', () {
      expect(tag.revives, 1);
    });

    test('no warning is ever escalated to an error', () {
      expect(report.warnings, isNotEmpty);
      expect(report.isSuccess, isTrue);
    });
  });

  group('early abort', () {
    test('the first page failing means the tag never accepted us', () async {
      final tag = FakeTag()..rejectWrites.add(5);
      final report = await WriteRunner.run(
        tag,
        ntag213Plan(),
        autoTryKnownPasswords: false,
      );

      expect(report.isSuccess, isFalse);
      expect(report.fatalError, contains('password protected'));
      expect(report.writtenCount, 0);
      expect(tag.writes, isEmpty, reason: 'nothing should be attempted after');
    });

    test('the remaining pages are reported as not written', () async {
      final tag = FakeTag()..rejectWrites.add(5);
      final report = await WriteRunner.run(
        tag,
        ntag213Plan(),
        autoTryKnownPasswords: false,
      );

      expect(report.outcomes.length, 34);
      expect(report.outcomes.first.status, PageStatus.failed);
      expect(
        report.outcomes.skip(1).every((o) => o.status == PageStatus.notWritten),
        isTrue,
      );
      expect(report.warnings.first, 'block 5 could not be written (protected)');
    });
  });

  group('revive budget', () {
    test('a dead session is revived at most twice', () async {
      // Page 5 is left out on purpose: rejecting it is the early-abort path.
      final tag = FakeTag()
        ..rejectWrites.addAll({6, 7, 8, 9, 10, 11, 12, 13});
      final report = await WriteRunner.run(
        tag,
        ntag213Plan(),
        autoTryKnownPasswords: false,
      );

      expect(tag.revives, WriteRunner.maxRevives);
      expect(report.isSuccess, isFalse);
      expect(report.fatalError, contains('stopped responding'));
    });

    test('pages left over after the budget is spent are not written', () async {
      final tag = FakeTag()..rejectWrites.addAll({6, 7, 8, 9, 10, 11, 12, 13});
      final report = await WriteRunner.run(
        tag,
        ntag213Plan(),
        autoTryKnownPasswords: false,
      );

      final notWritten =
          report.outcomes.where((o) => o.status == PageStatus.notWritten).length;
      expect(notWritten, greaterThan(0));
    });

    test('no revive is spent when only the last pages fail', () async {
      final tag = FakeTag()..rejectWrites.add(44);
      final report = await WriteRunner.run(
        tag,
        ntag213Plan(),
        autoTryKnownPasswords: false,
      );

      expect(tag.revives, 0, reason: 'nothing left to save');
      expect(report.isSuccess, isTrue);
    });

    test('a failing revive stops the run honestly', () async {
      final tag = FakeTag()
        ..rejectWrites.add(7)
        ..reviveError = const NfcException(NfcErrorKind.removed, 'gone');
      final report = await WriteRunner.run(
        tag,
        ntag213Plan(),
        autoTryKnownPasswords: false,
      );

      expect(report.isSuccess, isFalse);
      expect(report.fatalError, contains('Lost contact'));
    });

    test('a removed tag is fatal, with no revive attempted', () async {
      final tag = FakeTag()
        ..fatalError = const NfcException(NfcErrorKind.removed, 'tag removed');
      final report = await WriteRunner.run(
        tag,
        ntag213Plan(),
        autoTryKnownPasswords: false,
      );

      expect(report.isSuccess, isFalse);
      expect(report.fatalError, 'The tag was removed from the phone.');
      expect(tag.revives, 0);
    });
  });

  group('verification', () {
    test('bytes outside the mask are not compared', () async {
      final tag = FakeTag();
      final plan = [
        const PagePlan(
          page: 41,
          mask: [0xc0, 0x00, 0x00, 0xff],
          value: [0x80, 0x00, 0x00, 0x11],
        ),
      ];
      // Bytes 1 and 2 differ on the tag, but the mask does not claim them.
      tag.corruptOnRead[41] = [0x80, 0xaa, 0xbb, 0x11, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0];

      final report = await WriteRunner.run(tag, plan, autoTryKnownPasswords: false);

      expect(report.writtenCount, 1);
      expect(report.warnings, isEmpty);
    });

    test('a byte the mask only partly covers is still compared', () async {
      final tag = FakeTag();
      final plan = [
        const PagePlan(
          page: 41,
          mask: [0xc0, 0x0f, 0x00, 0xff],
          value: [0x80, 0x00, 0x00, 0x11],
        ),
      ];
      // The low nibble of byte 1 is ours and it is wrong; byte 2 is not ours.
      tag.corruptOnRead[41] = [0x80, 0x0a, 0xbb, 0x11, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0];

      final report = await WriteRunner.run(tag, plan, autoTryKnownPasswords: false);

      expect(report.mismatchedCount, 1);
      expect(report.warnings, ['data mismatch in block 41']);
    });

    test('a differing masked byte is reported as a mismatch', () async {
      final tag = FakeTag();
      final plan = [
        const PagePlan(page: 5, mask: [0xff, 0xff, 0xff, 0xff], value: [1, 2, 3, 4]),
      ];
      tag.corruptOnRead[5] = List.filled(16, 0);

      final report = await WriteRunner.run(tag, plan, autoTryKnownPasswords: false);

      expect(report.mismatchedCount, 1);
      expect(report.warnings, ['data mismatch in block 5']);
      expect(report.isSuccess, isTrue, reason: 'a mismatch is not an error');
    });

    test('a page that cannot be read back is reported as unverified', () async {
      final tag = FakeTag();
      final plan = [
        const PagePlan(page: 5, mask: [0xff, 0xff, 0xff, 0xff], value: [1, 2, 3, 4]),
      ];
      tag.unreadable.add(5);

      final report = await WriteRunner.run(tag, plan, autoTryKnownPasswords: false);

      expect(report.mismatchedCount, 1);
      expect(report.warnings, ['block 5 could not be verified']);
      expect(report.isSuccess, isTrue);
    });
  });

  group('password handling', () {
    test('no auto-try means exactly one auth attempt', () async {
      final tag = FakeTag();
      await WriteRunner.run(
        tag,
        ntag213Plan(),
        password: bytes([0xaa, 0xbb, 0xcc, 0xdd]),
        autoTryKnownPasswords: false,
      );
      expect(tag.authAttempts.length, 1);
      expect(tag.authAttempts.single, [0xaa, 0xbb, 0xcc, 0xdd]);
    });

    test('a rejected password falls through to the known ones, in order', () async {
      final tag = FakeTag()..password = hexToBytes('00000000');
      await WriteRunner.run(
        tag,
        ntag213Plan(),
        password: bytes([0xde, 0xad, 0xbe, 0xef]),
        autoTryKnownPasswords: true,
      );

      expect(tag.authAttempts, [
        [0xde, 0xad, 0xbe, 0xef],
        [0x12, 0x34, 0x56, 0x78],
        [0x00, 0x00, 0x00, 0x00],
      ]);
    });

    test('it stops as soon as one candidate works', () async {
      final tag = FakeTag()..password = hexToBytes('12345678');
      await WriteRunner.run(
        tag,
        ntag213Plan(),
        password: hexToBytes('DEADBEEF'),
        autoTryKnownPasswords: true,
      );

      expect(tag.authAttempts, [
        [0xde, 0xad, 0xbe, 0xef],
        [0x12, 0x34, 0x56, 0x78],
      ]);
      expect(tag.authAttempts, isNot(contains([0x00, 0x00, 0x00, 0x00])));
    });

    test('each candidate is tried at most once, even on a second run', () async {
      final tag = FakeTag();
      final plan = ntag213Plan();

      await WriteRunner.run(tag, plan, autoTryKnownPasswords: true);
      final firstRun = tag.authAttempts.length;

      await WriteRunner.run(tag, plan, autoTryKnownPasswords: true);
      final secondRun = tag.authAttempts.length;

      expect(firstRun, lessThanOrEqualTo(knownPasswordHex.length));
      expect(secondRun - firstRun, lessThanOrEqualTo(knownPasswordHex.length));
    });

    test('an unprotected tag writes anyway after every candidate fails', () async {
      final tag = FakeTag(); // password stays null, so nothing authenticates
      final report = await WriteRunner.run(
        tag,
        ntag213Plan(),
        password: bytes([1, 2, 3, 4]),
        autoTryKnownPasswords: true,
      );

      expect(tag.authAttempts.length, 4, reason: 'entered plus three known');
      expect(report.isSuccess, isTrue);
      expect(report.writtenCount, 34);
    });

    test('a blank password is not sent to the tag', () async {
      final tag = FakeTag();
      await WriteRunner.run(
        tag,
        ntag213Plan(),
        password: bytes([1, 2]),
        autoTryKnownPasswords: false,
      );
      expect(tag.authAttempts, isEmpty);
    });

    test('the cached password is re-sent after a revive', () async {
      final tag = FakeTag()
        ..password = hexToBytes('12345678')
        ..rejectWrites.addAll({43, 44});
      await WriteRunner.run(
        tag,
        ntag213Plan(),
        password: hexToBytes('12345678'),
        autoTryKnownPasswords: true,
      );

      // One attempt up front, one after the revive between 43 and 44.
      expect(tag.authAttempts.length, 2);
      expect(tag.authAttempts, everyElement([0x12, 0x34, 0x56, 0x78]));
    });
  });

  test('an empty plan is a no-op success', () async {
    final report = await WriteRunner.run(FakeTag(), const []);
    expect(report.isSuccess, isTrue);
    expect(report.outcomes, isEmpty);
    expect(report.warnings, isEmpty);
  });
}