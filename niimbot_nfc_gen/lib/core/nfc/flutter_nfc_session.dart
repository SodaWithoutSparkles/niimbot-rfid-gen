// TagSession on top of flutter_nfc_kit.
//
// The reader-mode configuration and the error handling follow the proven
// reference app (references/nfcraw-en-src/src/nfc/raw/MainActivity.java);
// where this file deviates, it says why.

import 'package:flutter/services.dart';
import 'package:flutter_nfc_kit/flutter_nfc_kit.dart';

import '../generator/bytes.dart';
import '../log.dart';
import 'commands.dart';
import 'tag_session.dart';

/// What went wrong, in the terms the write runner cares about.
enum NfcErrorKind {
  /// Android reports a tag NAK as an `IOException`. The tag is now IDLE and
  /// needs a revive, but the write can carry on afterwards.
  comms,

  /// The tag left the field. Fatal, there is nothing left to write to.
  removed,

  /// No tag polled.
  noTag,

  /// No NFC adapter on this device.
  unavailable,

  /// The tag does not support raw transceive.
  unsupported,

  /// Nothing was presented before the poll timeout.
  timeout,

  unknown,
}

NfcErrorKind nfcErrorKindFor(String code) => switch (code) {
      '500' => NfcErrorKind.comms,
      '503' => NfcErrorKind.removed,
      '404' => NfcErrorKind.unavailable,
      '405' => NfcErrorKind.unsupported,
      '406' => NfcErrorKind.noTag,
      '408' => NfcErrorKind.timeout,
      _ => NfcErrorKind.unknown,
    };

class NfcException implements Exception {
  final NfcErrorKind kind;

  /// The raw `PlatformException` code, for the log.
  final String? code;

  final String message;

  const NfcException(this.kind, this.message, {this.code});

  /// True when a `revive()` has any chance of helping.
  bool get isRecoverable => kind == NfcErrorKind.comms;

  @override
  String toString() =>
      'NfcException(${kind.name}${code == null ? '' : ' $code'}): $message';
}

class FlutterNfcSession implements TagSession {
  /// How long to wait for the user to present a tag.
  static const pollTimeout = Duration(seconds: 60);

  /// On some phones the presence check re-activates the tag and it will not
  /// respond at all without it. Matches the reference app.
  static const presenceCheckDelay = Duration(seconds: 5);

  /// `FLAG_READER_SKIP_NDEF_CHECK | FLAG_READER_NO_PLATFORM_SOUNDS`. Same two
  /// bits the reference app gets from `androidCheckNDEF` / `androidPlatformSound`.
  static const readerModeFlags = 0x80 | 0x100;

  @override
  TagInfo tag;

  FlutterNfcSession._(this.tag);

  /// Waits for a tag, then confirms what it is with `GET_VERSION`.
  static Future<FlutterNfcSession> poll() async {
    final polled = await _invoke(_pollTag);

    final uid = _parseUid(polled.id);
    log.i('tag polled: uid=${formatHex(uid)} '
        'atqa=${polled.atqa} sak=${polled.sak} '
        'mifareInfo=${polled.mifareInfo?.type}/${polled.mifareInfo?.blockCount}p '
        '(that page count is unreliable for NTAG21x)');

    final session = FlutterNfcSession._(TagInfo(uid: uid));

    // One GET_VERSION per session settles the real page count. After this, no
    // reconnect: the authenticated session must survive.
    final response = await session.transceive(cmdGetVersion());
    final pages = pageCountFromVersionResponse(response);
    if (pages != null) {
      session.tag = TagInfo(uid: uid, pageCount: pages);
      final type = tagTypeForPages(pages);
      log.i('GET_VERSION: size=0x${response[6].toRadixString(16).padLeft(2, '0')} '
          '-> $pages pages, ${type?.name ?? 'unsupported by this app'}');
    } else {
      log.w('GET_VERSION did not answer with a known size; '
          'page count is unknown and the tag type cannot be auto-detected');
    }

    return session;
  }

  /// The reader-mode configuration of the reference app, verbatim.
  static Future<NFCTag> _pollTag() => FlutterNfcKit.poll(
        timeout: pollTimeout,
        androidCheckNDEF: false,
        androidPlatformSound: false,
        readIso14443B: false,
        readIso18092: false,
        readIso15693: false,
        androidReaderModeFlags: readerModeFlags,
        extraReaderPresenceCheckDelay: presenceCheckDelay,
      );

  @override
  Future<Uint8List> transceive(Uint8List command, {Duration? timeout}) async {
    final started = Stopwatch()..start();
    final tx = formatHex(command);
    String elapsed() =>
        '(${(started.elapsedMicroseconds / 1000).toStringAsFixed(1)}ms)';

    try {
      final response = await FlutterNfcKit.transceive<Uint8List>(command, timeout: timeout);
      log.i('TX $tx -> ${_describe(response)} ${elapsed()}');
      return response;
    } on PlatformException catch (e) {
      final kind = nfcErrorKindFor(e.code);
      log.w('TX $tx -> ${kind.name} ${elapsed()} (${e.code}: ${e.message})');
      throw NfcException(kind, e.message ?? 'NFC call failed', code: e.code);
    }
  }

  /// `finish()` + `poll()`. flutter_nfc_kit has no close/connect pair, so
  /// dropping the session and picking the tag up again is the only way back.
  @override
  Future<void> revive() async {
    log.i('reviving session (finish + poll); this resets PWD_AUTH, re-auth is required');
    await _invoke(() => FlutterNfcKit.finish());

    final polled = await _invoke(_pollTag);

    final uid = _parseUid(polled.id);
    if (!_sameUid(uid, tag.uid)) {
      throw NfcException(
        NfcErrorKind.removed,
        'A different tag was presented (${formatHex(uid)}, expected ${formatHex(tag.uid)}).',
      );
    }

    final response = await transceive(cmdGetVersion());
    final pages = pageCountFromVersionResponse(response);
    tag = TagInfo(uid: uid, pageCount: pages ?? tag.pageCount);
    log.i('revived: ${tag.pageCount ?? 0} pages');
  }

  @override
  Future<void> close() async {
    // Never throws: closing must not mask the error that got us here.
    try {
      await FlutterNfcKit.finish();
    } on PlatformException catch (e) {
      log.d('close: ignored ${e.code} ${e.message}');
    }
  }

  static Uint8List _parseUid(String id) {
    try {
      return parseUid(id);
    } on ArgumentError {
      throw NfcException(
        NfcErrorKind.unknown,
        'The tag reported an unusable UID ($id).',
      );
    }
  }

  static bool _sameUid(Uint8List a, Uint8List b) {
    if (a.length != b.length) return false;
    for (int i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }
}

/// Wraps the poll call so a PlatformException becomes an NfcException before
/// anything reaches the UI.
Future<T> _invoke<T>(Future<T> Function() call) async {
  try {
    return await call();
  } on PlatformException catch (e) {
    final kind = nfcErrorKindFor(e.code);
    log.w('NFC ${kind.name} (${e.code}: ${e.message})');
    throw NfcException(kind, e.message ?? 'NFC call failed', code: e.code);
  }
}

String _describe(Uint8List response) => response.isEmpty
    ? '[empty: ACK]'
    : '[${formatHex(response)}: ${describeAck(response)}]';