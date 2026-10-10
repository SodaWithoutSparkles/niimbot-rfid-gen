// Profile / template data ported from reference-openroll.ts

import 'dart:typed_data';
import 'package:crypto/crypto.dart';
import 'media_params.dart';
import 'bytes.dart';
import 'payload.dart';
import '../log.dart';

class PrinterProfile {
  final String id;
  final String name;
  final String compatibility;

  const PrinterProfile({
    required this.id,
    required this.name,
    required this.compatibility,
  });
}

const PrinterProfile printerProfile = PrinterProfile(
  id: 'niimbot-b1-fw-6-19',
  name: 'NIIMBOT B1',
  compatibility: 'Tested on firmware 6.19',
);

class Brand {
  final String id;
  final String name;

  const Brand({required this.id, required this.name});
}

const Brand brand = Brand(id: 'niimbot', name: 'NIIMBOT');

class PhysicalSpec {
  final int widthMm;
  final int heightMm;
  final int gapMm;
  final int nominalQuantity;

  const PhysicalSpec({
    required this.widthMm,
    required this.heightMm,
    required this.gapMm,
    required this.nominalQuantity,
  });
}

class TemplateSpec {
  final String format;
  final String hex;
  final String sha256;

  const TemplateSpec({
    required this.format,
    required this.hex,
    required this.sha256,
  });
}

class RollProfile {
  final int schemaVersion;
  final String id;
  final int revision;
  final List<String> printerProfiles;
  final String displayName;
  final PhysicalSpec physical;
  final int capacityLimit;
  final TemplateSpec template;

  const RollProfile({
    required this.schemaVersion,
    required this.id,
    required this.revision,
    required this.printerProfiles,
    required this.displayName,
    required this.physical,
    required this.capacityLimit,
    required this.template,
  });
}

const RollProfile rollProfile = RollProfile(
  schemaVersion: 1,
  id: 'niimbot-30307-50x30',
  revision: 1,
  printerProfiles: ['niimbot-b1-fw-6-19'],
  displayName: '30307 freezer labels, 50 x 30 mm, 230 labels',
  physical: PhysicalSpec(
    widthMm: 50,
    heightMm: 30,
    gapMm: 6,
    nominalQuantity: 230,
  ),
  capacityLimit: 276,
  template: TemplateSpec(
    format: 'niimbot-pages5-34-raw-v1',
    hex: '742fc763e017dbf98ed6902b0c984b48f5de9eff112aac55452558e8848403e8'
        'eabebae8bb22ebc9cc3bb5bf9addc656aa7fe67ccd0adce494803b743a8b6488'
        '741abe5d162ff80ed7e61e8f66e35d5d3e24e38a6a56550e6d152f2a21a4ebe3'
        'db4b279be1d8d6832b4f1f29d68fba0b2f371ab05aad3d1e',
    sha256: 'bfb84efd42f1fd89d99d165e1fbcaba7d3bb2e661e264701a505fff100b2e049',
  ),
);

late final MediaParameters defaultParameters;

var _defaultsReady = false;

Future<void> initDefaultParameters() async {
  // `late final` can only be assigned once, and generateTagFile calls this on
  // every run. Without the guard the second call in a process throws.
  if (_defaultsReady) return;
  defaultParameters = payloadToParameters(hexToBytes(rollProfile.template.hex));
  _defaultsReady = true;
  debugLog(() => 'initDefaultParameters: defaultParameters=${defaultParameters.toMap()}');
}

Future<Uint8List> loadTemplate(String printerProfileId, String rollProfileId) async {
  if (printerProfileId != printerProfile.id ||
      rollProfileId != rollProfile.id ||
      !rollProfile.printerProfiles.contains(printerProfileId)) {
    throw ArgumentError('This printer and roll combination is not supported.');
  }
  if (rollProfile.schemaVersion != 1 ||
      rollProfile.revision != 1 ||
      rollProfile.template.format != 'niimbot-pages5-34-raw-v1') {
    throw ArgumentError('Unsupported profile version.');
  }
  final template = hexToBytes(rollProfile.template.hex);
  final digest = sha256.convert(template);
  if (digest.toString() != rollProfile.template.sha256) {
    throw ArgumentError('Profile template integrity check failed.');
  }
  if (decodePayload(template).capacity != rollProfile.capacityLimit) {
    throw ArgumentError('Profile capacity mismatch.');
  }
  debugLog(() => 'loadTemplate: template=${bytesToHex(template)}');
  return template;
}

bool isCustomParameters(MediaParameters params) {
  final result = [
    'mediaType',
    'widthMm',
    'heightMm',
    'gapMm',
    'nominalQuantity',
    'usageLimit',
  ].any((key) {
    final defaultValue = defaultParameters.toMap()[key];
    final currentValue = params.toMap()[key];
    return defaultValue != currentValue;
  });
  debugLog(() => 'isCustomParameters: params=${params.toMap()} default=${defaultParameters.toMap()} result=$result');
  return result;
}