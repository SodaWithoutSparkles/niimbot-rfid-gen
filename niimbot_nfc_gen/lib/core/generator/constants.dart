// Constants ported from reference-openroll.ts

const List<int> teaKey = [52385, 29367, 26456, 26057];
const int teaDelta = 2654435769; // 0x9E3779B9

const int maxReadSize = 32768;
const int maxNominalQuantity = 54612;

const List<int> orf1Magic = [0x4f, 0x52, 0x46, 0x31]; // "ORF1"
const List<int> pwdBytes = [0x12, 0x34, 0x56, 0x78];
const List<int> packBytes = [0x55, 0x55]; // "UU"