// Export formats (raw only) ported from reference-openroll.ts

import 'dart:typed_data';
import 'orf1.dart';
import 'bytes.dart';

enum TagType { ntag213, ntag215, ntag216 }

class TagTypeSpec {
  final TagType id;
  final String label;
  final int pages;
  final int configPage;
  final int passwordPage;
  final int packPage;
  final int ccSize;
  final int versionSize;
  final int chameleonId;
  final String evidence;

  const TagTypeSpec({
    required this.id,
    required this.label,
    required this.pages,
    required this.configPage,
    required this.passwordPage,
    required this.packPage,
    required this.ccSize,
    required this.versionSize,
    required this.chameleonId,
    required this.evidence,
  });
}

const List<TagTypeSpec> tagTypes = [
  TagTypeSpec(
    id: TagType.ntag213,
    label: 'NTAG213',
    pages: 45,
    configPage: 41,
    passwordPage: 43,
    packPage: 44,
    ccSize: 18,
    versionSize: 15,
    chameleonId: 1100,
    evidence: 'Tested with B1 firmware 6.19.',
  ),
  TagTypeSpec(
    id: TagType.ntag215,
    label: 'NTAG215 · experimental',
    pages: 135,
    configPage: 131,
    passwordPage: 133,
    packPage: 134,
    ccSize: 62,
    versionSize: 17,
    chameleonId: 1101,
    evidence: 'Experimental: generated files are validated; printer compatibility has not been physically tested.',
  ),
  TagTypeSpec(
    id: TagType.ntag216,
    label: 'NTAG216',
    pages: 231,
    configPage: 227,
    passwordPage: 229,
    packPage: 230,
    ccSize: 109,
    versionSize: 19,
    chameleonId: 1102,
    evidence: 'Contributor reports printing on B1 Pro firmware 2.12; readback supports counter writeback.',
  ),
];

TagTypeSpec getTagTypeSpec(TagType id) {
  final spec = tagTypes.firstWhere((t) => t.id == id, orElse: () => throw ArgumentError('Unsupported tag type.'));
  return spec;
}

TagType tagTypeFromByteLength(int length) {
  final spec = tagTypes.firstWhere((t) => t.pages * 4 == length, orElse: () => throw ArgumentError('Target read must contain exactly 180 bytes (NTAG213), 540 bytes (NTAG215) or 924 bytes (NTAG216).'));
  return spec.id;
}

Uint8List blankTagPreset(Uint8List uid, TagType tagType) {
  final spec = getTagTypeSpec(tagType);
  if (uid.length != 7) {
    throw ArgumentError('Target UID must contain exactly seven bytes.');
  }
  final memory = Uint8List(spec.pages * 4);
  memory.setRange(0, 3, uid.sublist(0, 3));
  memory[3] = 0x88 ^ uid[0] ^ uid[1] ^ uid[2];
  memory.setRange(4, 8, uid.sublist(3));
  memory[8] = uid[3] ^ uid[4] ^ uid[5] ^ uid[6];
  memory[9] = 0xc0;
  memory.setRange(12, 20, hexToBytes('e11012000103a00c340300fe'));
  memory[14] = spec.ccSize;
  if (tagType != TagType.ntag213) {
    memory.setRange(16, 20, hexToBytes('0300fe00'));
  }
  memory[spec.configPage * 4 - 1] = 0xbd;
  memory[spec.configPage * 4] = tagType == TagType.ntag213 ? 0 : 4;
  memory[spec.configPage * 4 + 3] = 0xff;
  return memory;
}

Uint8List assertMemoryBcc(Uint8List memory) {
  tagTypeFromByteLength(memory.length);
  if (memory[3] != (0x88 ^ memory[0] ^ memory[1] ^ memory[2]) ||
      memory[8] != (memory[4] ^ memory[5] ^ memory[6] ^ memory[7])) {
    throw ArgumentError('Target read has invalid UID check bytes. Use an unmodified read of the target tag.');
  }
  return Uint8List.fromList(memory);
}

Uint8List extractUidFromMemory(Uint8List memory) {
  final checked = assertMemoryBcc(memory);
  return Uint8List.fromList([...checked.sublist(0, 3), ...checked.sublist(4, 8)]);
}

class ExportResult {
  final Uint8List bytes;
  final String suffix;
  final List<String> assumptions;

  ExportResult({
    required this.bytes,
    required this.suffix,
    required this.assumptions,
  });
}

ExportResult exportRaw(Uint8List orf1, Uint8List payload, Uint8List uid, Uint8List? targetMemory, TagType tagType) {
  final spec = getTagTypeSpec(tagType);
  validateOrf1(orf1, payload, uid);

  final baseMemory = targetMemory != null ? assertMemoryBcc(targetMemory) : blankTagPreset(uid, tagType);

  if (tagTypeFromByteLength(baseMemory.length) != tagType) {
    throw ArgumentError('Target dump type does not match the selected tag type.');
  }

  final assumptions = <String>[];
  if (targetMemory == null) {
    assumptions.add(
      'UID-only: non-payload memory uses a blank ${spec.label} preset, not a read of this tag. Preserve physical UID, lock bits and unrelated factory state when writing.',
    );
  }

  final orf1Memory = orf1.sublist(4, 184);
  final writeMask = orf1.sublist(364);

  if (!bytesEqual(baseMemory.sublist(0, 9), orf1Memory.sublist(0, 9))) {
    throw ArgumentError('Target read UID does not match the entered UID.');
  }

  final merged = Uint8List.fromList(baseMemory);
  for (int offset = 0; offset < 180; offset++) {
    if (writeMask[offset] == 0) continue;
    final targetOffset = offset >= 164 ? spec.configPage * 4 + offset - 164 : offset;
    merged[targetOffset] = (merged[targetOffset] & ~writeMask[offset]) | (orf1Memory[offset] & writeMask[offset]);
  }

  print('[DEBUG] exportRaw: orf1=${bytesToHex(orf1)} payload=${bytesToHex(payload)} uid=${bytesToHex(uid)} tagType=$tagType merged=${bytesToHex(merged)}');

  return ExportResult(bytes: merged, suffix: '.bin', assumptions: assumptions);
}