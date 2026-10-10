// TEA cipher ported from reference-openroll.ts

import 'dart:typed_data';
import 'constants.dart';
import 'bytes.dart';

Uint8List teaCrypt(Uint8List input, {bool decrypt = false}) {
  if (input.length % 8 != 0) {
    throw ArgumentError('TEA requires complete eight-byte blocks.');
  }
  final out = Uint8List.fromList(input);
  final view = ByteData.view(out.buffer, out.offsetInBytes, out.lengthInBytes);
  print('[DEBUG] teaCrypt: decrypt=$decrypt in=${bytesToHex(input)}');

  for (int off = 0; off < input.length; off += 8) {
    int v0 = view.getUint32(off, Endian.little);
    int v1 = view.getUint32(off + 4, Endian.little);
    int sum = decrypt ? (teaDelta * 32) & 0xffffffff : 0;

    for (int i = 0; i < 32; i++) {
      if (decrypt) {
        v1 = (v1 -
                ((((v0 << 4) + teaKey[2]) ^ (v0 + sum)) ^
                    ((v0 >> 5) + teaKey[3]))) &
            0xffffffff;
        v0 = (v0 -
                ((((v1 << 4) + teaKey[0]) ^ (v1 + sum)) ^
                    ((v1 >> 5) + teaKey[1]))) &
            0xffffffff;
        sum = (sum - teaDelta) & 0xffffffff;
      } else {
        sum = (sum + teaDelta) & 0xffffffff;
        v0 = (v0 +
                ((((v1 << 4) + teaKey[0]) ^ (v1 + sum)) ^
                    ((v1 >> 5) + teaKey[1]))) &
            0xffffffff;
        v1 = (v1 +
                ((((v0 << 4) + teaKey[2]) ^ (v0 + sum)) ^
                    ((v0 >> 5) + teaKey[3]))) &
            0xffffffff;
      }
    }

    view.setUint32(off, v0, Endian.little);
    view.setUint32(off + 4, v1, Endian.little);
  }
  print('[DEBUG] teaCrypt: out=${bytesToHex(out)}');
  return out;
}