// Byte / hex helpers ported from reference-openroll.ts

import 'dart:typed_data';

Uint8List hexToBytes(String hex) {
  if (!RegExp(r'^(?:[0-9a-fA-F]{2})*$').hasMatch(hex)) {
    throw ArgumentError('Invalid hexadecimal bytes.');
  }
  final bytes = <int>[];
  for (int i = 0; i < hex.length; i += 2) {
    bytes.add(int.parse(hex.substring(i, i + 2), radix: 16));
  }
  final out = Uint8List.fromList(bytes);
  print('[DEBUG] hexToBytes: in="$hex" out=${bytesToHex(out)}');
  return out;
}

String bytesToHex(Uint8List bytes) {
  final out = bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join('');
  print('[DEBUG] bytesToHex: in_len=${bytes.length} out="$out"');
  return out;
}

bool bytesEqual(Uint8List a, Uint8List b) {
  if (a.length != b.length) return false;
  for (int i = 0; i < a.length; i++) {
    if (a[i] != b[i]) return false;
  }
  return true;
}

ByteData dataView(Uint8List bytes) {
  return ByteData.view(bytes.buffer, bytes.offsetInBytes, bytes.lengthInBytes);
}

Uint8List parseUid(String input) {
  final trimmed = input.trim();
  if (RegExp(r'^[0-9a-fA-F]{14}$').hasMatch(trimmed)) {
    return hexToBytes(trimmed);
  }
  for (final sep in [':', '-', r'\s+']) {
    if (RegExp(r'^[0-9a-fA-F]{2}(?:' + sep + r'[0-9a-fA-F]{2}){6}$').hasMatch(trimmed)) {
      return hexToBytes(trimmed.replaceAll(RegExp(sep), ''));
    }
  }
  throw ArgumentError(
    'Enter 14 hexadecimal characters, or seven byte pairs separated by spaces, colons or hyphens.',
  );
}

String formatUidBytes(Uint8List bytes) {
  final hex = bytesToHex(bytes).toUpperCase();
  final parts = <String>[];
  for (int i = 0; i < hex.length; i += 2) {
    parts.add(hex.substring(i, i + 2));
  }
  return parts.join(' ');
}