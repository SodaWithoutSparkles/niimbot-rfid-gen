// NIIMBOT 120-byte payload ported from reference-openroll.ts

import 'dart:typed_data';
import 'tea.dart';
import 'crc.dart';
import 'bytes.dart';
import '../log.dart';

class NiimbotPayload {
  final Uint8List mutable; // 4 bytes
  final Uint8List fixed; // 108 bytes
  final int count;
  final int capacity;

  NiimbotPayload({
    required this.mutable,
    required this.fixed,
    required this.count,
    required this.capacity,
  });
}

NiimbotPayload decodePayload(Uint8List bytes) {
  if (bytes.length != 120) {
    throw ArgumentError('NIIMBOT payload must contain 120 bytes.');
  }
  final plain = teaCrypt(bytes, decrypt: true);
  final mutable = plain.sublist(0, 4);
  final fixed = plain.sublist(8, 116);
  final view = ByteData.view(plain.buffer, plain.offsetInBytes, plain.lengthInBytes);
  if (crc32(mutable) != view.getUint32(4, Endian.little)) {
    throw ArgumentError('Mutable CRC failed.');
  }
  if (crc32(fixed) != view.getUint32(116, Endian.little)) {
    throw ArgumentError('Fixed CRC failed.');
  }
  final out = NiimbotPayload(
    mutable: mutable,
    fixed: fixed,
    count: ByteData.view(mutable.buffer, mutable.offsetInBytes, mutable.lengthInBytes).getUint16(2, Endian.little),
    capacity: ByteData.view(fixed.buffer, fixed.offsetInBytes, fixed.lengthInBytes).getUint16(58, Endian.little),
  );
  debugLog(() => 'decodePayload: in=${bytesToHex(bytes)} mutable=${bytesToHex(mutable)} fixed=${bytesToHex(fixed)} count=${out.count} capacity=${out.capacity}');
  return out;
}

Uint8List encodePayload(Uint8List mutable, Uint8List fixed) {
  if (mutable.length != 4 || fixed.length != 108) {
    throw ArgumentError('Invalid plaintext lengths.');
  }
  final plain = Uint8List(120);
  plain.setRange(0, 4, mutable);
  plain.setRange(8, 116, fixed);
  final view = ByteData.view(plain.buffer, plain.offsetInBytes, plain.lengthInBytes);
  view.setUint32(4, crc32(mutable), Endian.little);
  view.setUint32(116, crc32(fixed), Endian.little);
  final out = teaCrypt(plain, decrypt: false);
  debugLog(() => 'encodePayload: mutable=${bytesToHex(mutable)} fixed=${bytesToHex(fixed)} out=${bytesToHex(out)}');
  return out;
}

Uint8List rebindUid(Uint8List payload, Uint8List uid) {
  if (uid.length != 7) {
    throw ArgumentError('Target UID must contain exactly seven bytes.');
  }
  final decoded = decodePayload(payload);
  decoded.fixed.setRange(0, 8, [0x88, ...uid]);
  ByteData.view(decoded.mutable.buffer, decoded.mutable.offsetInBytes, decoded.mutable.lengthInBytes)
      .setUint16(2, 0, Endian.little);
  final out = encodePayload(decoded.mutable, decoded.fixed);
  debugLog(() => 'rebindUid: in=${bytesToHex(payload)} uid=${bytesToHex(uid)} out=${bytesToHex(out)}');
  return out;
}

void assertFixedIdentity(Uint8List fixed, Uint8List uid) {
  final expected = Uint8List.fromList([0x88, ...uid]);
  if (!bytesEqual(fixed.sublist(0, 8), expected)) {
    throw ArgumentError('Fixed identity does not match target UID.');
  }
  debugLog(() => 'assertFixedIdentity: fixed[0..7]=${bytesToHex(fixed.sublist(0, 8))} expected=${bytesToHex(expected)} OK');
}