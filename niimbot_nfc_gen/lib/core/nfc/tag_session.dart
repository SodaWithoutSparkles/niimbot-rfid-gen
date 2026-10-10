// The tag session the write runner talks to.
//
// Abstract on purpose: the runner needs a tag that NAKs page 43, or that needs
// reviving, and that has to be reproducible in a unit test.

import 'dart:typed_data';

import '../generator/export.dart';
import 'commands.dart';

/// What we know about the tag currently in the field.
class TagInfo {
  /// 7-byte UID straight off `NFCTag.id`.
  final Uint8List uid;

  /// Page count from `GET_VERSION`. This is the authoritative number.
  ///
  /// Do not trust `NFCTag.mifareInfo.blockCount`: Android reports its generic
  /// `TYPE_ULTRALIGHT` page count (16) for every NTAG21x.
  final int? pageCount;

  /// Tag type implied by [pageCount], null for tags this app cannot write.
  TagType? get tagType {
    final pages = pageCount;
    return pages == null ? null : tagTypeForPages(pages);
  }

  const TagInfo({required this.uid, this.pageCount});

  @override
  String toString() => 'TagInfo(pageCount: $pageCount, uid: $uid)';
}

abstract class TagSession {
  TagInfo get tag;

  /// Sends one raw command. The empty result is a successful ACK, see
  /// `isAck` in commands.dart.
  Future<Uint8List> transceive(Uint8List command, {Duration? timeout});

  /// Brings a dead session back. The only way to do it is finish + poll.
  ///
  /// This resets the authenticated session, so re-run `PWD_AUTH` afterwards.
  Future<void> revive();

  Future<void> close();
}