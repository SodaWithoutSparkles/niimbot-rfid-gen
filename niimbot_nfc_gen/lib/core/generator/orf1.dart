// ORF1 provisioning dump ported from reference-openroll.ts

import 'dart:typed_data';
import 'payload.dart';
import 'uid_masks.dart';
import 'constants.dart';
import 'bytes.dart';

class Orf1Info {
  final String format;
  final int bytes;
  final int pageCount;
  final String uid;
  final bool fixedCrcValid;
  final bool mutableCrcValid;
  final bool profileMatches;
  final int count;
  final int capacity;
  final bool permanentLockWrites;

  Orf1Info({
    required this.format,
    required this.bytes,
    required this.pageCount,
    required this.uid,
    required this.fixedCrcValid,
    required this.mutableCrcValid,
    required this.profileMatches,
    required this.count,
    required this.capacity,
    required this.permanentLockWrites,
  });
}

Uint8List buildOrf1(Uint8List payload, Uint8List uid) {
  final memory = Uint8List(180);
  memory.setRange(0, 9, uidHeader(uid));
  memory.setRange(20, 140, rebindUid(payload, uid));
  memory[167] = 0xff;
  memory.setRange(172, 176, pwdBytes);
  memory.setRange(176, 178, packBytes);

  final masks = provisioningMasks();
  final out = Uint8List(544);
  out.setRange(0, 4, orf1Magic);
  out.setRange(4, 184, memory);
  out.setRange(184, 364, masks.known);
  out.setRange(364, 544, masks.write);
  print('[DEBUG] buildOrf1: payload=${bytesToHex(payload)} uid=${bytesToHex(uid)} out=${bytesToHex(out)}');
  return out;
}

Orf1Info validateOrf1(Uint8List orf1, Uint8List payload, Uint8List uid) {
  if (orf1.length != 544 || !bytesEqual(orf1.sublist(0, 4), Uint8List.fromList(orf1Magic))) {
    throw ArgumentError('Expected a 544-byte ORF1 provisioning dump.');
  }
  final memory = orf1.sublist(4, 184);
  final known = orf1.sublist(184, 364);
  final write = orf1.sublist(364);
  final masks = provisioningMasks();

  if (!bytesEqual(known, masks.known) || !bytesEqual(write, masks.write)) {
    throw ArgumentError('Invalid masks: manufacturer and lock writes are forbidden.');
  }
  for (int i = 0; i < memory.length; i++) {
    if ((memory[i] & ~masks.known[i]) != 0) {
      throw ArgumentError('Unknown bits must remain canonical preserve placeholders.');
    }
  }
  if (!bytesEqual(memory.sublist(0, 9), uidHeader(uid))) {
    throw ArgumentError('Target UID/BCC mismatch.');
  }
  if (memory[164] != 0 ||
      memory[167] != 0xff ||
      memory[168] != 0 ||
      !bytesEqual(memory.sublist(172, 176), Uint8List.fromList(pwdBytes)) ||
      !bytesEqual(memory.sublist(176, 178), Uint8List.fromList(packBytes))) {
    throw ArgumentError('Authentication/configuration policy mismatch.');
  }

  final decoded = decodePayload(memory.sublist(20, 140));
  assertFixedIdentity(decoded.fixed, uid);
  if (decoded.count != 0) {
    throw ArgumentError('Fresh-roll count must be zero.');
  }
  if (!bytesEqual(orf1, buildOrf1(payload, uid))) {
    throw ArgumentError('Dump does not match the selected profile.');
  }

  final out = Orf1Info(
    format: 'ORF1',
    bytes: 544,
    pageCount: 45,
    uid: bytesToHex(uid),
    fixedCrcValid: true,
    mutableCrcValid: true,
    profileMatches: true,
    count: decoded.count,
    capacity: decoded.capacity,
    permanentLockWrites: false,
  );
  print('[DEBUG] validateOrf1: orf1=${bytesToHex(orf1)} payload=${bytesToHex(payload)} uid=${bytesToHex(uid)} out=${out}');
  return out;
}