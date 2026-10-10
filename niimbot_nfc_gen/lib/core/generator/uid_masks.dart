// UID / BCC + provisioning masks ported from reference-openroll.ts

import 'dart:typed_data';
import 'bytes.dart';
import '../log.dart';

Uint8List uidHeader(Uint8List uid) {
  if (uid.length != 7) {
    throw ArgumentError('Target UID must contain exactly seven bytes.');
  }
  final out = Uint8List.fromList([
    uid[0],
    uid[1],
    uid[2],
    0x88 ^ uid[0] ^ uid[1] ^ uid[2],
    uid[3],
    uid[4],
    uid[5],
    uid[6],
    uid[3] ^ uid[4] ^ uid[5] ^ uid[6],
  ]);
  debugLog(() => 'uidHeader: uid=${bytesToHex(uid)} out=${bytesToHex(out)}');
  return out;
}

class ProvisioningMasks {
  final Uint8List known;
  final Uint8List write;

  ProvisioningMasks({required this.known, required this.write});
}

ProvisioningMasks provisioningMasks() {
  final known = Uint8List(180);
  final write = Uint8List(180);
  known.fillRange(0, 9, 0xff);
  for (final range in [
    [20, 140],
    [172, 178],
  ]) {
    known.fillRange(range[0], range[1], 0xff);
    write.fillRange(range[0], range[1], 0xff);
  }
  for (final entry in [
    [164, 192],
    [167, 255],
    [168, 159],
  ]) {
    known[entry[0]] = entry[1];
    write[entry[0]] = entry[1];
  }
  debugLog(() => 'provisioningMasks: known=${bytesToHex(known)} write=${bytesToHex(write)}');
  return ProvisioningMasks(known: known, write: write);
}