// Tests for the raw NTAG command layer. No hardware involved.

import 'dart:typed_data';

import 'package:niimbot_nfc_gen/core/generator/export.dart';
import 'package:niimbot_nfc_gen/core/nfc/commands.dart';
import 'package:niimbot_nfc_gen/core/nfc/tag_session.dart';
import 'package:test/test.dart';

Uint8List bytes(List<int> values) => Uint8List.fromList(values);

void main() {
  group('command builders', () {
    test('GET_VERSION is a single 0x60', () {
      expect(cmdGetVersion(), bytes([0x60]));
    });

    test('READ is 0x30 plus the page', () {
      expect(cmdReadPage(5), bytes([0x30, 0x05]));
      expect(cmdReadPage(0x1d), bytes([0x30, 0x1d]));
    });

    test('WRITE is 0xA2, the page, then four data bytes', () {
      expect(
        cmdWritePage(5, [0x74, 0x2f, 0xc7, 0x63]),
        bytes([0xa2, 0x05, 0x74, 0x2f, 0xc7, 0x63]),
      );
    });

    test('WRITE rejects anything that is not one page', () {
      expect(() => cmdWritePage(5, [0, 0, 0]), throwsArgumentError);
      expect(() => cmdWritePage(5, [0, 0, 0, 0, 0]), throwsArgumentError);
    });

    test('PWD_AUTH is 0x1B plus four password bytes', () {
      expect(
        cmdPwdAuth([0x12, 0x34, 0x56, 0x78]),
        bytes([0x1b, 0x12, 0x34, 0x56, 0x78]),
      );
      expect(() => cmdPwdAuth([0x12, 0x34]), throwsArgumentError);
    });

    test('pages outside 0..255 are rejected', () {
      expect(() => cmdReadPage(-1), throwsArgumentError);
      expect(() => cmdReadPage(256), throwsArgumentError);
      expect(() => cmdWritePage(999, [0, 0, 0, 0]), throwsArgumentError);
    });
  });

  group('ACK / NAK decoding', () {
    test('an empty response is an ACK', () {
      // Android's stack swallows the 4-bit ACK, so this is the common case.
      expect(isAck(Uint8List(0)), isTrue);
      expect(describeAck(Uint8List(0)), contains('ACK'));
    });

    test('an explicit 0x0A is an ACK', () {
      expect(isAck(bytes([0x0a])), isTrue);
      expect(isAck(bytes([0x8a])), isTrue, reason: 'only the low nibble matters');
      expect(describeAck(bytes([0x0a])), 'ACK');
    });

    test('NAK codes decode to their reason', () {
      expect(describeAck(bytes([0x00])), contains('NAK 0'));
      expect(describeAck(bytes([0x00])), contains('protected'));
      expect(describeAck(bytes([0x01])), contains('NAK 1'));
      expect(describeAck(bytes([0x04])), contains('counter overflow'));
      expect(describeAck(bytes([0x05])), contains('EEPROM'));
    });

    test('NAKs are not ACKs', () {
      expect(isAck(bytes([0x00])), isFalse);
      expect(isAck(bytes([0x01])), isFalse);
      expect(isAck(bytes([0x04])), isFalse);
      expect(isAck(bytes([0x05])), isFalse);
    });

    test('an unknown NAK still says something', () {
      expect(describeAck(bytes([0x07])), contains('NAK 7'));
    });

    test('a 16-byte READ response carries no ACK nibble', () {
      expect(describeAck(bytes(List.filled(16, 0xaa))), 'no ACK/NAK');
    });
  });

  group('GET_VERSION size byte', () {
    test('maps the NTAG21x sizes to page counts', () {
      expect(pagesFromVersion(0x0f), 45);
      expect(pagesFromVersion(0x11), 135);
      expect(pagesFromVersion(0x13), 231);
    });

    test('maps the Ultralight EV1 sizes too', () {
      expect(pagesFromVersion(0x0b), 20);
      expect(pagesFromVersion(0x0e), 41);
    });

    test('an unknown size gives null, not a guess', () {
      expect(pagesFromVersion(0x00), isNull);
      expect(pagesFromVersion(0xff), isNull);
    });

    test('page counts become the generator tag types', () {
      expect(tagTypeForPages(45), TagType.ntag213);
      expect(tagTypeForPages(135), TagType.ntag215);
      expect(tagTypeForPages(231), TagType.ntag216);
    });

    test('tags this app cannot write give null', () {
      expect(tagTypeForPages(20), isNull);
      expect(tagTypeForPages(41), isNull);
      expect(tagTypeForPages(16), isNull);
    });

    test('reads byte 6 only when the response is long enough', () {
      final version = bytes([0x04, 0x00, 0x44, 0x00, 0x00, 0x00, 0x0f, 0x00]);
      expect(pageCountFromVersionResponse(version), 45);
      expect(pageCountFromVersionResponse(bytes([0x04, 0x00, 0x44])), isNull);
    });

    test('an NTAG213 reports 45 pages, not the 16 Android claims', () {
      // Android's MifareInfo.fromUltralight reports 0x0F + 1 == 16 for every
      // NTAG21x. GET_VERSION is the only trustworthy source.
      const uid = [1, 2, 3, 4, 5, 6, 7];
      expect(TagInfo(uid: bytes(uid), pageCount: 45).tagType, TagType.ntag213);
      expect(TagInfo(uid: bytes(uid), pageCount: 16).tagType, isNull);
      expect(TagInfo(uid: bytes(uid)).tagType, isNull);
    });
  });

  test('formatHex is upper case and space separated', () {
    expect(formatHex([0xa2, 0x05, 0x74, 0x2f, 0xc7, 0x63]), 'A2 05 74 2F C7 63');
    expect(formatHex([0x00, 0x0f]), '00 0F');
    expect(formatHex([]), '');
  });
}