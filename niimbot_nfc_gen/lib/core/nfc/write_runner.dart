// Authenticate, write, verify. The only file that drives a live tag.
//
// Two rules shape everything here:
//
//   * A NAK is not a failure. Pages 43 and 44 reject writes on real NTAG21x
//     hardware by design, so a rejected page becomes a warning and the run
//     continues. Only [WriteReport.fatalError] makes a write unsuccessful.
//   * A wrong password is the one way to brick a tag, because NTAG21x counts
//     failed authentications against a finite limit. So we never guess a
//     password until the tag has actually refused a write, and every candidate
//     is tried at most once per tag.

import 'dart:typed_data';

import '../generator/bytes.dart';
import '../log.dart';
import 'commands.dart';
import 'tag_session.dart';
import 'write_plan.dart';
import 'write_progress.dart';

/// Tried after the entered password when auto-try is on, in this order.
///
/// FFFFFFFF is first because it is the NXP factory default, and because this
/// app can never actually set a password: the generator's password bytes land
/// on the page that real NTAG21x hardware refuses to write (plan fact #8). So
/// a tag this app has provisioned still carries its factory password, and the
/// common protected case is a tag whose password is all ones.
const List<String> knownPasswordHex = ['FFFFFFFF', '12345678', '00000000'];

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

/// What the pre-flight settled before the main loop starts.
class _Gate {
  /// How the probe page turned out.
  final PageStatus probeStatus;

  /// First page the main loop still has to write. The probe is page 0, so this
  /// is always 1.
  final int nextIndex;

  /// The password that authenticated, kept so a revive can re-authenticate.
  /// Null when the tag needed no password.
  final List<int>? unlocked;

  /// Set when the probe page could not be written at all.
  final String? fatal;

  const _Gate(this.probeStatus, this.nextIndex, this.unlocked, this.fatal);
}

/// Counts round trips across the whole run and emits a [WriteProgress].
class _Progress {
  final ProgressCallback? _callback;
  int done = 0;
  int total;

  _Progress(this._callback, this.total);

  void emit(WritePhase phase, String message) {
    _callback?.call(WriteProgress(phase, done, total, message));
  }

  void step(WritePhase phase, String message) {
    done++;
    emit(phase, message);
  }
}

class WriteRunner {
  /// How many times a dead session may be brought back before the run stops.
  static const int maxRevives = 2;

  /// Used when the probe page cannot be written even after authenticating.
  static const earlyAbortMessage =
      'The tag rejected the write - it is probably password protected.';

  static Future<WriteReport> run(
    TagSession session,
    List<PagePlan> plan, {
    List<int> password = const [],
    bool autoTryKnownPasswords = true,
    ProgressCallback? onProgress,
  }) async {
    // A listener that throws must never abort a write that is half done.
    void safeEmit(WriteProgress value) {
      try {
        onProgress?.call(value);
      } catch (e) {
        log.w('progress listener threw, ignoring: $e');
      }
    }

    if (plan.isEmpty) {
      return const WriteReport(outcomes: [], warnings: []);
    }

    // Connecting (1) + one write per page (plan.length) + one read per page in
    // the verify pass (plan.length). Authentication and revives interrupt these
    // but do not add their own steps, because they are bounded and rare.
    final progress = _Progress(
      safeEmit,
      1 + plan.length * 2,
    );

    progress.emit(WritePhase.probing, 'Checking whether the tag is protected…');

    // Get in before writing anything else. See _openTheTag.
    final gate = await _openTheTag(
      session,
      plan,
      password,
      autoTryKnownPasswords,
      progress,
    );

    // The probe page counts as one write step.
    progress.done = gate.nextIndex + 1;

    final outcomes = <PageOutcome>[
      PageOutcome(
        page: plan.first.page,
        status: gate.probeStatus,
        warning: gate.probeStatus == PageStatus.failed
            ? 'page ${plan.first.page} could not be written (protected)'
            : null,
      ),
    ];

    final unlocked = gate.unlocked;
    var revivesLeft = maxRevives;
    String? fatal = gate.fatal;

    for (var index = gate.nextIndex; index < plan.length; index++) {
      final entry = plan[index];

      progress.emit(
        WritePhase.writing,
        'Writing page ${index + 1} of ${plan.length}…',
      );

      if (fatal != null) {
        outcomes.add(PageOutcome(
          page: entry.page,
          status: PageStatus.notWritten,
          warning: 'page ${entry.page} was not written',
        ));
        progress.done++;
        continue;
      }

      final failure = await _tryWrite(session, entry);
      progress.done++;

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

      // A NAK on a later page. Expected for the password and pack pages.
      outcomes.add(_rejected(entry, failure));

      if (index + 1 >= plan.length) break; // nothing left to save, do not revive
      if (revivesLeft <= 0) {
        fatal = 'The tag stopped responding and could not be revived.';
        continue;
      }

      // A NAK leaves the tag IDLE; the session has to come back before the
      // remaining pages can be attempted at all. So does an authentication.
      revivesLeft--;
      log.i('reviving before the remaining pages '
          '(${maxRevives - revivesLeft}/$maxRevives)');
      progress.emit(
        WritePhase.reviving,
        'Tag went idle — hold it against the phone…',
      );
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

    progress.emit(
      WritePhase.verifying,
      'Reading back to confirm (1 of ${outcomes.length})…',
    );
    final verified = await _verify(session, plan, outcomes, progress);
    progress.emit(WritePhase.done, 'Done');

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

  /// Works out how to get into the tag, using the first page as the probe.
  ///
  /// The order matters. A refused WRITE costs nothing, but a refused PWD_AUTH
  /// increments the tag's finite failure counter, which is the one way to
  /// brick a tag. So the first thing we do is try to write page 1 with no
  /// password at all:
  ///
  ///  * most tags are unprotected, so this succeeds immediately and we spend no
  ///    authentication attempts whatsoever;
  ///  * only when the write is refused do we start guessing passwords, and each
  ///    candidate is confirmed by re-probing that same single page rather than
  ///    by starting the whole 34-page write.
  ///
  /// The probe page is genuinely written, so the main loop resumes after it.
  static Future<_Gate> _openTheTag(
    TagSession session,
    List<PagePlan> plan,
    List<int> password,
    bool autoTry,
    _Progress progress,
  ) async {
    final probe = plan.first;

    final direct = await _tryWrite(session, probe);
    if (direct == null) {
      log.i('page ${probe.page} accepted an unauthenticated write');
      return const _Gate(PageStatus.written, 1, null, null);
    }

    // A NAK could mean the tag is protected. Anything else means the tag is
    // gone or the hardware cannot do this, and guessing a password would only
    // turn a clear diagnosis into a misleading one.
    if (direct.kind != NfcErrorKind.comms) {
      return _Gate(PageStatus.failed, 1, null, _fatalFor(direct));
    }

    log.i('page ${probe.page} refused an unauthenticated write: '
        '${direct.message}');

    // The tag is protected, or refuses writes outright. Try to authenticate.
    final candidates = _candidates(password, autoTry);
    for (var i = 0; i < candidates.length; i++) {
      final candidate = candidates[i];
      progress.emit(
        WritePhase.authenticating,
        'Trying passwords (${i + 1} of ${candidates.length})…',
      );
      if (!await _pwdAuth(session, candidate)) {
        log.i('PWD_AUTH rejected ${formatHex(candidate)}');
        continue;
      }

      log.i('PWD_AUTH accepted ${formatHex(candidate)}, re-probing');
      final afterAuth = await _tryWrite(session, probe);
      if (afterAuth == null) {
        log.i('page ${probe.page} accepted after authenticating');
        return _Gate(PageStatus.written, 1, candidate, null);
      }
      log.w('page ${probe.page} still refused after authenticating: '
          '${afterAuth.message}');
    }

    return _Gate(PageStatus.failed, 1, null, earlyAbortMessage);
  }

  /// Writes one page. Never throws: the caller gets null on success.
  static Future<NfcException?> _tryWrite(
    TagSession session,
    PagePlan entry,
  ) async {
    try {
      if (!entry.isFull) {
        final current = await session.transceive(cmdReadPage(entry.page));
        if (current.length < 4) {
          return NfcException(
            NfcErrorKind.comms,
            'page ${entry.page} read back only ${current.length} bytes',
          );
        }
        final response = await session.transceive(
          cmdWritePage(entry.page, entry.apply(current)),
        );
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
    _Progress progress,
  ) async {
    final results = <PageOutcome>[];
    var sessionIsGone = false;

    for (var index = 0; index < outcomes.length; index++) {
      final outcome = outcomes[index];
      final entry = plan[index];

      progress.emit(
        WritePhase.verifying,
        'Reading back to confirm (${index + 1} of ${outcomes.length})…',
      );

      if (outcome.status != PageStatus.written) {
        results.add(outcome);
        progress.done++;
        continue;
      }

      if (sessionIsGone) {
        results.add(_unverified(entry.page));
        progress.done++;
        continue;
      }

      Uint8List current;
      try {
        current = await session.transceive(cmdReadPage(entry.page));
      } on NfcException catch (e) {
        if (e.kind != NfcErrorKind.comms) sessionIsGone = true;
        log.w('page ${entry.page} could not be verified: ${e.message}');
        results.add(_unverified(entry.page));
        progress.done++;
        continue;
      }

      if (current.length < 4) {
        results.add(_unverified(entry.page));
        progress.done++;
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
      progress.done++;

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

  /// The entered password first, then the known ones, without duplicates.
  static List<List<int>> _candidates(List<int> password, bool autoTry) {
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

    return candidates;
  }

  /// Tries PWD_AUTH. A tag with no protection NAKs this too, which is why the
  /// unauthenticated probe runs first and this is only reached once the tag has
  /// refused a write.
  ///
  /// Two bytes is a PACK. An empty response is the ACK Android swallowed.
  static Future<bool> _pwdAuth(TagSession session, List<int> password) async {
    try {
      final response = await session.transceive(cmdPwdAuth(password));
      return response.length <= 2;
    } on NfcException {
      return false;
    }
  }
}