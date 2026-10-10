// Authenticate, write, verify. The only file that drives a live tag.
//
// Two rules shape everything here:
//
//   * A NAK is not a failure. Pages 43 and 44 reject writes on real NTAG21x
//     hardware by design, so a rejected page becomes a warning and the run
//     continues. Only [WriteReport.fatalError] makes a write unsuccessful.
//   * A wrong password is the one way to brick a tag, because NTAG21x counts
//     failed authentications against a finite limit. Every candidate is tried
//     at most once per tag, and the loop never runs twice for the same tag.

import 'dart:typed_data';

import '../generator/bytes.dart';
import '../log.dart';
import 'commands.dart';
import 'tag_session.dart';
import 'write_plan.dart';

/// Tried after the entered password when auto-try is on, in this order.
const List<String> knownPasswordHex = ['12345678', '00000000', 'FFFFFFFF'];

enum PageStatus {
  /// Written and confirmed by a read-back.
  written,

  /// The tag rejected the write. Expected for the password and pack pages.
  failed,

  /// Never attempted, because the run stopped first.
  notWritten,

  /// Written, but the read-back did not confirm it.
  mismatched,
}

class PageOutcome {
  final int page;
  final PageStatus status;

  /// The user-facing warning for this page, verbatim. Null when there is none.
  final String? warning;

  const PageOutcome({required this.page, required this.status, this.warning});
}

class WriteReport {
  final List<PageOutcome> outcomes;
  final List<String> warnings;

  /// Set only when the run could not continue at all. A report with warnings
  /// and no fatal error is a success.
  final String? fatalError;

  const WriteReport({
    required this.outcomes,
    required this.warnings,
    this.fatalError,
  });

  bool get isSuccess => fatalError == null;

  int get writtenCount =>
      outcomes.where((o) => o.status == PageStatus.written).length;

  int get failedCount => outcomes
      .where((o) =>
          o.status == PageStatus.failed || o.status == PageStatus.notWritten)
      .length;

  int get mismatchedCount =>
      outcomes.where((o) => o.status == PageStatus.mismatched).length;
}

class WriteRunner {
  /// How many times a dead session may be brought back before the run stops.
  static const int maxRevives = 2;

  /// The message used when the very first page is rejected, which means the
  /// tag never accepted us at all rather than protecting one page.
  static const earlyAbortMessage =
      'The tag rejected the write - it is probably password protected.';

  static Future<WriteReport> run(
    TagSession session,
    List<PagePlan> plan, {
    List<int> password = const [],
    bool autoTryKnownPasswords = true,
  }) async {
    if (plan.isEmpty) {
      return const WriteReport(outcomes: [], warnings: []);
    }

    // The password that worked, kept for any revive later on.
    final unlocked = await _authenticate(session, password, autoTryKnownPasswords);

    final outcomes = <PageOutcome>[];
    var revivesLeft = maxRevives;
    String? fatal;

    for (var index = 0; index < plan.length; index++) {
      final entry = plan[index];

      if (fatal != null) {
        outcomes.add(PageOutcome(
          page: entry.page,
          status: PageStatus.notWritten,
          warning: 'page ${entry.page} was not written',
        ));
        continue;
      }

      final failure = await _tryWrite(session, entry);

      if (failure == null) {
        outcomes.add(PageOutcome(page: entry.page, status: PageStatus.written));
        continue;
      }

      if (failure.kind != NfcErrorKind.comms) {
        // The tag is gone, or the hardware cannot do this. Nothing to continue.
        fatal = _fatalFor(failure);
        outcomes.add(PageOutcome(
          page: entry.page,
          status: PageStatus.failed,
          warning: 'page ${entry.page} could not be written (${failure.kind.name})',
        ));
        continue;
      }

      // A NAK. The very first page failing means the tag never accepted us.
      if (index == 0) {
        fatal = earlyAbortMessage;
        outcomes.add(_rejected(entry, failure));
        continue;
      }

      outcomes.add(_rejected(entry, failure));

      if (index + 1 >= plan.length) break; // nothing left to save, do not revive
      if (revivesLeft <= 0) {
        fatal = 'The tag stopped responding and could not be revived.';
        continue;
      }

      // A NAK leaves the tag IDLE; the session has to come back before the
      // remaining pages can be attempted at all.
      revivesLeft--;
      log.i('reviving before the remaining pages (${maxRevives - revivesLeft}/$maxRevives)');
      try {
        await session.revive();
        if (unlocked != null && !await _pwdAuth(session, unlocked)) {
          log.w('re-auth after revive failed; continuing anyway');
        }
      } on NfcException catch (e) {
        log.w('revive failed: $e');
        fatal = 'Lost contact with the tag: ${e.message}';
      }
    }

    final verified = await _verify(session, plan, outcomes);
    final warnings = verified.map((o) => o.warning).whereType<String>().toList();

    log.i('write result: ${verified.length} pages, '
        '${verified.where((o) => o.status == PageStatus.written).length} written, '
        '${warnings.length} warning(s), fatal=${fatal ?? 'none'}');

    return WriteReport(outcomes: verified, warnings: warnings, fatalError: fatal);
  }

  static PageOutcome _rejected(PagePlan entry, NfcException failure) {
    log.w('page ${entry.page} rejected: ${failure.message}');
    return PageOutcome(
      page: entry.page,
      status: PageStatus.failed,
      warning: 'page ${entry.page} could not be written (protected)',
    );
  }

  /// Writes one page. Never throws: the caller gets null on success.
  static Future<NfcException?> _tryWrite(TagSession session, PagePlan entry) async {
    try {
      if (!entry.isFull) {
        final current = await session.transceive(cmdReadPage(entry.page));
        if (current.length < 4) {
          return NfcException(
            NfcErrorKind.comms,
            'page ${entry.page} read back only ${current.length} bytes',
          );
        }
        final response =
            await session.transceive(cmdWritePage(entry.page, entry.apply(current)));
        if (!isAck(response)) {
          return NfcException(NfcErrorKind.comms, describeAck(response));
        }
      } else {
        final response =
            await session.transceive(cmdWritePage(entry.page, entry.value));
        if (!isAck(response)) {
          return NfcException(NfcErrorKind.comms, describeAck(response));
        }
      }
      return null;
    } on NfcException catch (e) {
      return e;
    }
  }

  /// Re-reads every written page and compares only the masked bytes.
  ///
  /// [outcomes] is positionally aligned with [plan].
  static Future<List<PageOutcome>> _verify(
    TagSession session,
    List<PagePlan> plan,
    List<PageOutcome> outcomes,
  ) async {
    final results = <PageOutcome>[];
    var sessionIsGone = false;

    for (var index = 0; index < outcomes.length; index++) {
      final outcome = outcomes[index];
      final entry = plan[index];

      if (outcome.status != PageStatus.written) {
        results.add(outcome);
        continue;
      }

      if (sessionIsGone) {
        results.add(_unverified(entry.page));
        continue;
      }

      Uint8List current;
      try {
        current = await session.transceive(cmdReadPage(entry.page));
      } on NfcException catch (e) {
        if (e.kind != NfcErrorKind.comms) sessionIsGone = true;
        log.w('page ${entry.page} could not be verified: ${e.message}');
        results.add(_unverified(entry.page));
        continue;
      }

      if (current.length < 4) {
        results.add(_unverified(entry.page));
        continue;
      }

      final wrong = [
        for (var i = 0; i < 4; i++)
          if ((current[i] ^ entry.value[i]) & entry.mask[i] != 0) i,
      ];
      if (wrong.isEmpty) {
        results.add(outcome);
      } else {
        log.w('data mismatch in page ${entry.page}: bytes $wrong are '
            '${formatHex(current)} on the tag, expected ${formatHex(entry.value)}');
        results.add(PageOutcome(
          page: entry.page,
          status: PageStatus.mismatched,
          warning: 'data mismatch in page ${entry.page}',
        ));
      }
    }

    return results;
  }

  static PageOutcome _unverified(int page) => PageOutcome(
        page: page,
        status: PageStatus.mismatched,
        warning: 'page $page could not be verified',
      );

  static String _fatalFor(NfcException failure) => switch (failure.kind) {
        NfcErrorKind.removed => 'The tag was removed from the phone.',
        NfcErrorKind.unavailable => 'This device has no NFC adapter.',
        NfcErrorKind.unsupported =>
          'This tag does not support raw NFC commands.',
        NfcErrorKind.timeout => 'The tag was not presented in time.',
        NfcErrorKind.noTag => 'No tag is connected.',
        _ => failure.message,
      };

  /// Tries the entered password first, then the known ones. Each candidate is
  /// tried at most once, and this loop runs at most once per tag.
  ///
  /// Returns the password that worked, or null when none did. A tag with no
  /// protection answers PWD_AUTH with a NAK too, so a null result is normal.
  static Future<List<int>?> _authenticate(
    TagSession session,
    List<int> password,
    bool autoTry,
  ) async {
    final candidates = <List<int>>[];
    final seen = <String>{};

    void consider(List<int> candidate) {
      if (candidate.length != 4) return;
      if (!seen.add(formatHex(candidate))) return;
      candidates.add(candidate);
    }

    consider(password);
    if (autoTry) {
      for (final hex in knownPasswordHex) {
        consider(hexToBytes(hex));
      }
    }

    for (final candidate in candidates) {
      if (await _pwdAuth(session, candidate)) {
        log.i('PWD_AUTH accepted ${formatHex(candidate)}');
        return candidate;
      }
      log.i('PWD_AUTH rejected ${formatHex(candidate)}');
    }

    if (candidates.isEmpty) {
      log.i('no password to try; writing unauthenticated');
    } else {
      log.i('no candidate password authenticated; the tag is probably not '
          'protected, writing unauthenticated');
    }
    return null;
  }

  static Future<bool> _pwdAuth(TagSession session, List<int> password) async {
    try {
      final response = await session.transceive(cmdPwdAuth(password));
      // Two bytes is a PACK. An empty response is the ACK Android swallowed.
      return response.length <= 2;
    } on NfcException {
      return false;
    }
  }
}