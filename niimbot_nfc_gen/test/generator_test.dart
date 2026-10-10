// Test for generator module - ported from reference-openroll.test.ts

import 'dart:typed_data';
import 'package:test/test.dart';
import 'package:niimbot_nfc_gen/core/generator.dart';

void main() {
  test('generateTagFile matches golden reference', () async {
    final result = await generateTagFile(
      GenerateInput(
        mediaType: 1,
        widthMm: 50,
        heightMm: 30,
        gapMm: 6,
        nominalQuantity: 230,
        uid: '1D:E1:A1:93:10:10:80',
        tagType: TagType.ntag213,
      ),
    );

    const goldenBinaryString =
        '1de1a1d59310108013c00000e11012000103a00c742fc763e017dbf935a3fd09be86168ff5de9eff112aac55452558e8848403e8eabebae8bb22ebc960a540537fcccad380063526fc53bc2694803b743a8b6488741abe5d162ff80ed7e61e8f66e35d5d3e24e38a6a56550e6d152f2a21a4ebe3db4b279be1d8d6832b4f1f29d68fba0b5d339b383e3487110000000000000000000000000000000000000000000000bd000000ff000000001234567855550000';

    final goldenBytes = Uint8List.fromList(
      goldenBinaryString
          .split('')
          .fold<List<String>>([], (acc, char) {
            if (acc.isEmpty || acc.last.length == 2) {
              acc.add(char);
            } else {
              acc[acc.length - 1] += char;
            }
            return acc;
          })
          .map((byte) => int.parse(byte, radix: 16))
          .toList(),
    );

    expect(result.bytes.length, equals(goldenBytes.length));
    for (int i = 0; i < goldenBytes.length; i++) {
      expect(
        result.bytes[i],
        equals(goldenBytes[i]),
        reason: 'Byte mismatch at index $i',
      );
    }
  });
}
