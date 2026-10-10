// CRC32 ported from reference-openroll.ts

import 'dart:typed_data';
import 'bytes.dart';

int crc32(Uint8List bytes) {
  int crc = 0xffffffff;
  for (final byte in bytes) {
    crc ^= byte;
    for (int i = 0; i < 8; i++) {
      crc = (crc >> 1) ^ ((crc & 1) == 1 ? 0xedb88320 : 0);
    }
  }
  final out = (crc ^ 0xffffffff) & 0xffffffff;
  print('[DEBUG] crc32: in=${bytesToHex(bytes)} out=0x${out.toRadixString(16).padLeft(8, '0')}');
  return out;
}