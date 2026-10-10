// Media parameters ported from reference-openroll.ts

import 'dart:typed_data';
import 'payload.dart';
import 'errors.dart';
import 'constants.dart';
import 'bytes.dart';

class MediaParameters {
  final int mediaType;
  final int widthMm;
  final int heightMm;
  final int gapMm;
  final int nominalQuantity;
  final int usageLimit;

  MediaParameters({
    required this.mediaType,
    required this.widthMm,
    required this.heightMm,
    required this.gapMm,
    required this.nominalQuantity,
    required this.usageLimit,
  });

  Map<String, int> toMap() {
    return {
      'mediaType': mediaType,
      'widthMm': widthMm,
      'heightMm': heightMm,
      'gapMm': gapMm,
      'nominalQuantity': nominalQuantity,
      'usageLimit': usageLimit,
    };
  }
}

class MediaTypeOption {
  final int value;
  final String label;

  MediaTypeOption({required this.value, required this.label});
}

final List<MediaTypeOption> mediaTypes = [
  MediaTypeOption(value: 1, label: 'Gap labels'),
  MediaTypeOption(value: 2, label: 'Black-mark labels'),
  MediaTypeOption(value: 3, label: 'Continuous media'),
  MediaTypeOption(value: 4, label: 'Hole-indexed labels'),
  MediaTypeOption(value: 5, label: 'Transparent labels'),
  MediaTypeOption(value: 10, label: 'Black-mark + gap labels'),
];

class ParameterField {
  final String key;
  final String label;
  final int offset;
  final int size; // 1 or 2
  final int min;
  final int max;

  const ParameterField({
    required this.key,
    required this.label,
    required this.offset,
    required this.size,
    required this.min,
    required this.max,
  });
}

final List<ParameterField> parameterFields = [
  const ParameterField(key: 'widthMm', label: 'Width (mm)', offset: 82, size: 1, min: 1, max: 255),
  const ParameterField(key: 'heightMm', label: 'Length (mm)', offset: 83, size: 1, min: 1, max: 255),
  const ParameterField(key: 'gapMm', label: 'Gap (mm)', offset: 87, size: 1, min: 0, max: 255),
  const ParameterField(key: 'nominalQuantity', label: 'Nominal quantity', offset: 84, size: 2, min: 1, max: 65535),
  const ParameterField(key: 'usageLimit', label: 'Usage limit', offset: 58, size: 2, min: 1, max: 65535),
];

void validateParameters(MediaParameters params) {
  if (!mediaTypes.any((m) => m.value == params.mediaType)) {
    throw FieldError('mediaType', 'Select a listed media type.');
  }
  for (final field in parameterFields) {
    final value = params.toMap()[field.key]!;
    int min = field.min;
    if (field.key == 'heightMm' && params.mediaType == 3) {
      min = 0;
    }
    if (field.key == 'gapMm' && value != value.round()) {
      throw FieldError(
        'gapMm',
        'The known NIIMBOT gap encoding supports whole millimetres only. $value mm cannot be encoded exactly; OpenRoll will not round it automatically.',
      );
    }
    if (value < min || value > field.max) {
      throw FieldError(field.key, '${field.label} must be a whole number from $min to ${field.max}.');
    }
  }
  print('[DEBUG] validateParameters: params=${params.toMap()} OK');
}

int computeUsageLimit(int nominalQuantity) {
  if (nominalQuantity < 1 || nominalQuantity > maxNominalQuantity) {
    throw FieldError(
      'nominalQuantity',
      'Nominal quantity must be a whole number from 1 to $maxNominalQuantity so its 1.2× usage limit fits the tag.',
    );
  }
  return ((nominalQuantity * 6) / 5).round();
}

NiimbotPayload decodeEditablePayload(Uint8List payload) {
  final decoded = decodePayload(payload);
  if ([98, 99, 102].any((off) => decoded.fixed[off] != 0)) {
    throw ArgumentError('Extended or fractional dimensions are not supported by this editor.');
  }
  return decoded;
}

MediaParameters payloadToParameters(Uint8List payload) {
  final decoded = decodeEditablePayload(payload);
  final fixed = decoded.fixed;
  final view = ByteData.view(fixed.buffer, fixed.offsetInBytes, fixed.lengthInBytes);
  final result = <String, int>{'mediaType': fixed[60]};
  for (final field in parameterFields) {
    result[field.key] = field.size == 1 ? fixed[field.offset] : view.getUint16(field.offset, Endian.little);
  }
  final params = MediaParameters(
    mediaType: result['mediaType']!,
    widthMm: result['widthMm']!,
    heightMm: result['heightMm']!,
    gapMm: result['gapMm']!,
    nominalQuantity: result['nominalQuantity']!,
    usageLimit: result['usageLimit']!,
  );
  validateParameters(params);
  print('[DEBUG] payloadToParameters: in=${bytesToHex(payload)} out=${params.toMap()}');
  return params;
}

Uint8List parametersToPayload(Uint8List payload, MediaParameters params) {
  validateParameters(params);
  final decoded = decodeEditablePayload(payload);
  final fixed = decoded.fixed;
  final view = ByteData.view(fixed.buffer, fixed.offsetInBytes, fixed.lengthInBytes);
  fixed[60] = params.mediaType;
  for (final field in parameterFields) {
    final value = params.toMap()[field.key]!;
    if (field.size == 1) {
      fixed[field.offset] = value;
    } else {
      view.setUint16(field.offset, value, Endian.little);
    }
  }
  final out = encodePayload(decoded.mutable, fixed);
  print('[DEBUG] parametersToPayload: in=${bytesToHex(payload)} params=${params.toMap()} out=${bytesToHex(out)}');
  return out;
}