// Top-level orchestrator ported from reference-openroll.ts

import 'dart:typed_data';
import 'media_params.dart';
import 'profile.dart';
import 'orf1.dart';
import 'export.dart';
import 'bytes.dart';
import 'barcode.dart';
import '../log.dart';

class GenerateInput {
  final int mediaType;
  final int widthMm;
  final int heightMm;
  final int gapMm;
  final int nominalQuantity;
  final String uid;
  final TagType tagType;
  final Uint8List? targetMemory;

  GenerateInput({
    required this.mediaType,
    required this.widthMm,
    required this.heightMm,
    required this.gapMm,
    required this.nominalQuantity,
    required this.uid,
    this.tagType = TagType.ntag213,
    this.targetMemory,
  });
}

class GenerateResult {
  final Uint8List bytes;
  final String suffix;
  final List<String> assumptions;
  final String uid;
  final TagType tagType;
  final String profile;
  final bool custom;
  final bool fromRead;
  final String filename;

  GenerateResult({
    required this.bytes,
    required this.suffix,
    required this.assumptions,
    required this.uid,
    required this.tagType,
    required this.profile,
    required this.custom,
    required this.fromRead,
    required this.filename,
  });
}

Future<GenerateResult> generateTagFile(GenerateInput input) async {
  await initDefaultParameters();

  final tagType = input.tagType;
  final uid = parseUid(input.uid);

  // Continuous media has no fixed length/gap
  int effectiveHeightMm = input.heightMm;
  int effectiveGapMm = input.gapMm;
  if (input.mediaType == 3) {
    effectiveHeightMm = 0;
    effectiveGapMm = 0;
  }

  final params = MediaParameters(
    mediaType: input.mediaType,
    widthMm: input.widthMm,
    heightMm: effectiveHeightMm,
    gapMm: effectiveGapMm,
    nominalQuantity: input.nominalQuantity,
    usageLimit: computeUsageLimit(input.nominalQuantity),
  );
  validateParameters(params);

  if (input.targetMemory != null) {
    final targetUid = extractUidFromMemory(input.targetMemory!);
    if (!bytesEqual(uid, targetUid)) {
      throw ArgumentError('UID does not match the optional dump. Correct the UID or remove the dump.');
    }
    if (tagTypeFromByteLength(input.targetMemory!.length) != tagType) {
      throw ArgumentError('Tag type does not match the optional dump. Select its type or remove the dump.');
    }
  }

  final template = await loadTemplate(printerProfile.id, rollProfile.id);
  final payload = applyCatalogueBarcode(parametersToPayload(template, params));

  final orf1 = buildOrf1(payload, uid);
  validateOrf1(orf1, payload, uid);

  final exported = exportRaw(orf1, payload, uid, input.targetMemory, tagType);

  final custom = isCustomParameters(params);
  final mediaLabel = mediaTypes.firstWhere((m) => m.value == params.mediaType, orElse: () => MediaTypeOption(value: 0, label: 'Media')).label;
  final dims = params.mediaType == 3
      ? '${params.widthMm} mm wide · continuous'
      : '${params.widthMm} × ${params.heightMm} mm';
  final profile = '$mediaLabel · $dims';

  final profilePart = custom ? 'niimbot-custom' : rollProfile.id;
  final tagPart = tagType == TagType.ntag213 ? '' : '-${tagType.name.toLowerCase()}';
  final filename = 'openroll-$profilePart$tagPart-${bytesToHex(uid)}${exported.suffix}';

  final out = GenerateResult(
    bytes: exported.bytes,
    suffix: exported.suffix,
    assumptions: exported.assumptions,
    uid: bytesToHex(uid),
    tagType: tagType,
    profile: profile,
    custom: custom,
    fromRead: input.targetMemory != null,
    filename: filename,
  );
  debugLog(() => 'generateTagFile: input=$input out=$out');
  return out;
}