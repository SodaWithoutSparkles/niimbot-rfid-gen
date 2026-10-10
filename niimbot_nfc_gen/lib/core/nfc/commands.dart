// Raw NTAG21x command builders and response decoding.
//
// Nothing here touches hardware: every function is a pure encode/decode so the
// write path can be unit tested without a tag.
//
// The commands are built by hand rather than through `MifareUltralight` because
// `PWD_AUTH` (0x1B) has no `MifareUltralight` equivalent, and because a mixed
// raw/high-level sequence would drop the authenticated session on every frame.

import 'dart:typed_data';

import '../generator/export.dart';

/// `GET_VERSION` (0x60). Byte 6 of the response is the size code.
Uint8List cmdGetVersion() => Uint8List.fromList([0x60]);

/// `READ` (0x30). The tag answers with 16 bytes; take the first 4.
Uint8List cmdReadPage(int page) {
  _checkPage(page);
  return Uint8List.fromList([0x30, page]);
}

/// `WRITE` (0xA2). [data] must be exactly one 4-byte page.
Uint8List cmdWritePage(int page, List<int> data) {
  _checkPage(page);
  if (data.length != 4) {
    throw ArgumentError('A page is 4 bytes, got ${data.length}.');
  }
  return Uint8List.fromList([0xA2, page, data[0], data[1], data[2], data[3]]);
}

/// `PWD_AUTH` (0x1B) followed by the 4-byte password. No `MifareUltralight`
/// equivalent exists, which is why the whole write path is raw.
Uint8List cmdPwdAuth(List<int> password) {
  if (password.length != 4) {
    throw ArgumentError('The password is exactly 4 bytes, got ${password.length}.');
  }
  return Uint8List.fromList([0x1b, password[0], password[1], password[2], password[3]]);
}

void _checkPage(int page) {
  if (page < 0 || page > 255) {
    throw ArgumentError('Page must be 0..255, got $page.');
  }
}

/// True when [response] means the tag accepted the command.
///
/// A tag answers a successful frame with a 4-bit `0x0A`, which Android's NFC
/// stack swallows, so an empty response is an ACK. The explicit form is kept
/// for the rare stack that does pass it through.
bool isAck(Uint8List response) =>
    response.isEmpty || (response.length == 1 && (response[0] & 0x0f) == 0x0a);

/// Human readable reading of a response's ACK/NAK nibble.
String describeAck(Uint8List response) {
  if (response.isEmpty) {
    return 'ACK (empty response, the stack ate the 4-bit ACK)';
  }
  if (response.length != 1) {
    return 'no ACK/NAK';
  }
  switch (response[0] & 0x0f) {
    case 0x0a:
      return 'ACK';
    case 0x00:
      return 'NAK 0 - invalid address, or the page is protected';
    case 0x01:
      return 'NAK 1 - CRC or parity error';
    case 0x04:
      return 'NAK 4 - authentication counter overflow';
    case 0x05:
      return 'NAK 5 - EEPROM write error';
    default:
      return 'NAK ${response[0] & 0x0f} - unknown reason';
  }
}

/// Page count for a `GET_VERSION` size byte, or null when unrecognised.
int? pagesFromVersion(int size) => switch (size & 0xff) {
      0x0b => 20, // Ultralight EV1 MF0UL11
      0x0e => 41, // Ultralight EV1 MF0UL21
      0x0f => 45, // NTAG213
      0x11 => 135, // NTAG215
      0x13 => 231, // NTAG216
      _ => null,
    };

/// Generator tag type for a page count, or null when this app cannot write it.
TagType? tagTypeForPages(int pages) => switch (pages) {
      45 => TagType.ntag213,
      135 => TagType.ntag215,
      231 => TagType.ntag216,
      _ => null,
    };

/// Pulls the page count out of a `GET_VERSION` response, or null if the tag
/// did not answer with the expected 8 bytes.
int? pageCountFromVersionResponse(Uint8List response) =>
    response.length >= 8 ? pagesFromVersion(response[6]) : null;

/// Upper case, space separated hex: `A2 05 74 2F C7 63`.
String formatHex(List<int> bytes) =>
    bytes.map((b) => (b & 0xff).toRadixString(16).padLeft(2, '0').toUpperCase()).join(' ');