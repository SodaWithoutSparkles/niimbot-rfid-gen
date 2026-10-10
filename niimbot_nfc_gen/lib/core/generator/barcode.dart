// Barcode / catalogue ported from reference-openroll.ts

import 'dart:typed_data';
import 'media_params.dart';
import 'payload.dart';
import 'bytes.dart';

class CatalogueEntry {
  final int mediaType;
  final int widthMm;
  final int heightMm;
  final String barcode;
  final String sourceId;
  final String barcodeEvidence;

  const CatalogueEntry({
    required this.mediaType,
    required this.widthMm,
    required this.heightMm,
    required this.barcode,
    required this.sourceId,
    required this.barcodeEvidence,
  });
}

const String catalogueSha256 =
    'dd1c930f3ac0808fa3e0498fa26986ceee807980a06bffe86c987b29efc56efb';

final List<CatalogueEntry> catalogue = [
  CatalogueEntry(
    mediaType: 1,
    widthMm: 8,
    heightMm: 25,
    barcode: '6977031213614',
    sourceId: '80006700',
    barcodeEvidence: 'catalogue-primary',
  ),
  CatalogueEntry(
    mediaType: 1,
    widthMm: 10,
    heightMm: 25,
    barcode: '08042110',
    sourceId: '80032461',
    barcodeEvidence: 'catalogue-primary',
  ),
  CatalogueEntry(
    mediaType: 1,
    widthMm: 12,
    heightMm: 22,
    barcode: '010424774',
    sourceId: '80028832',
    barcodeEvidence: 'catalogue-primary',
  ),
  CatalogueEntry(
    mediaType: 1,
    widthMm: 12,
    heightMm: 24,
    barcode: '08132280',
    sourceId: '80002444',
    barcodeEvidence: 'catalogue-primary',
  ),
  CatalogueEntry(
    mediaType: 1,
    widthMm: 12,
    heightMm: 30,
    barcode: '6972842747594',
    sourceId: '50233717',
    barcodeEvidence: 'catalogue-primary',
  ),
  CatalogueEntry(
    mediaType: 1,
    widthMm: 12,
    heightMm: 40,
    barcode: '01222281',
    sourceId: '80000351',
    barcodeEvidence: 'tag-capture',
  ),
  CatalogueEntry(
    mediaType: 1,
    widthMm: 13,
    heightMm: 70,
    barcode: '6972842742674',
    sourceId: '50234177',
    barcodeEvidence: 'catalogue-primary',
  ),
  CatalogueEntry(
    mediaType: 1,
    widthMm: 14,
    heightMm: 20,
    barcode: '091625176',
    sourceId: '80045634',
    barcodeEvidence: 'catalogue-primary',
  ),
  CatalogueEntry(
    mediaType: 1,
    widthMm: 14,
    heightMm: 25,
    barcode: '010424779',
    sourceId: '58118004',
    barcodeEvidence: 'catalogue-primary',
  ),
  CatalogueEntry(
    mediaType: 1,
    widthMm: 14,
    heightMm: 30,
    barcode: '090223009',
    sourceId: '80006402',
    barcodeEvidence: 'catalogue-primary',
  ),
  CatalogueEntry(
    mediaType: 1,
    widthMm: 14,
    heightMm: 40,
    barcode: '08152233',
    sourceId: '80004091',
    barcodeEvidence: 'catalogue-primary',
  ),
  CatalogueEntry(
    mediaType: 1,
    widthMm: 14,
    heightMm: 50,
    barcode: '010424784',
    sourceId: '80004092',
    barcodeEvidence: 'catalogue-primary',
  ),
  CatalogueEntry(
    mediaType: 1,
    widthMm: 14,
    heightMm: 54,
    barcode: '06172280',
    sourceId: '51338418',
    barcodeEvidence: 'catalogue-primary',
  ),
  CatalogueEntry(
    mediaType: 1,
    widthMm: 14,
    heightMm: 60,
    barcode: '08042113',
    sourceId: '58117738',
    barcodeEvidence: 'catalogue-primary',
  ),
  CatalogueEntry(
    mediaType: 1,
    widthMm: 15,
    heightMm: 26,
    barcode: '6971501224582',
    sourceId: '80032608',
    barcodeEvidence: 'catalogue-primary',
  ),
  CatalogueEntry(
    mediaType: 1,
    widthMm: 15,
    heightMm: 30,
    barcode: '02282280',
    sourceId: '50230230',
    barcodeEvidence: 'tag-capture',
  ),
  CatalogueEntry(
    mediaType: 1,
    widthMm: 15,
    heightMm: 50,
    barcode: '010424787',
    sourceId: '80032548',
    barcodeEvidence: 'catalogue-primary',
  ),
  CatalogueEntry(
    mediaType: 1,
    widthMm: 20,
    heightMm: 8,
    barcode: '091026183',
    sourceId: '80111310',
    barcodeEvidence: 'catalogue-primary',
  ),
  CatalogueEntry(
    mediaType: 1,
    widthMm: 20,
    heightMm: 10,
    barcode: '123025190',
    sourceId: '80113174',
    barcodeEvidence: 'catalogue-primary',
  ),
  CatalogueEntry(
    mediaType: 1,
    widthMm: 20,
    heightMm: 30,
    barcode: '6977388393373',
    sourceId: '80019751',
    barcodeEvidence: 'catalogue-primary',
  ),
  CatalogueEntry(
    mediaType: 1,
    widthMm: 20,
    heightMm: 40,
    barcode: '010924601',
    sourceId: '80019755',
    barcodeEvidence: 'catalogue-primary',
  ),
  CatalogueEntry(
    mediaType: 1,
    widthMm: 20,
    heightMm: 45,
    barcode: '040724038',
    sourceId: '80019754',
    barcodeEvidence: 'catalogue-primary',
  ),
  CatalogueEntry(
    mediaType: 1,
    widthMm: 20,
    heightMm: 75,
    barcode: '08042124',
    sourceId: '58118885',
    barcodeEvidence: 'catalogue-primary',
  ),
  CatalogueEntry(
    mediaType: 1,
    widthMm: 22,
    heightMm: 22,
    barcode: '041124118',
    sourceId: '80014717',
    barcodeEvidence: 'catalogue-primary',
  ),
  CatalogueEntry(
    mediaType: 1,
    widthMm: 25,
    heightMm: 10,
    barcode: '123025196',
    sourceId: '80113172',
    barcodeEvidence: 'catalogue-primary',
  ),
  CatalogueEntry(
    mediaType: 1,
    widthMm: 25,
    heightMm: 15,
    barcode: '123025197',
    sourceId: '80113129',
    barcodeEvidence: 'catalogue-primary',
  ),
  CatalogueEntry(
    mediaType: 1,
    widthMm: 25,
    heightMm: 30,
    barcode: '010924603',
    sourceId: '80019752',
    barcodeEvidence: 'catalogue-primary',
  ),
  CatalogueEntry(
    mediaType: 1,
    widthMm: 25,
    heightMm: 40,
    barcode: '08042121',
    sourceId: '58118687',
    barcodeEvidence: 'catalogue-primary',
  ),
  CatalogueEntry(
    mediaType: 1,
    widthMm: 25,
    heightMm: 50,
    barcode: '040924192',
    sourceId: '80019753',
    barcodeEvidence: 'catalogue-primary',
  ),
  CatalogueEntry(
    mediaType: 1,
    widthMm: 30,
    heightMm: 15,
    barcode: '123025201',
    sourceId: '80113128',
    barcodeEvidence: 'catalogue-primary',
  ),
  CatalogueEntry(
    mediaType: 1,
    widthMm: 30,
    heightMm: 40,
    barcode: '090223012',
    sourceId: '80049324',
    barcodeEvidence: 'catalogue-primary',
  ),
  CatalogueEntry(
    mediaType: 1,
    widthMm: 33,
    heightMm: 33,
    barcode: '111225133',
    sourceId: '80014718',
    barcodeEvidence: 'catalogue-primary',
  ),
  CatalogueEntry(
    mediaType: 1,
    widthMm: 40,
    heightMm: 10,
    barcode: '123025058',
    sourceId: '80113162',
    barcodeEvidence: 'catalogue-primary',
  ),
  CatalogueEntry(
    mediaType: 1,
    widthMm: 40,
    heightMm: 15,
    barcode: '123025206',
    sourceId: '80113161',
    barcodeEvidence: 'catalogue-primary',
  ),
  CatalogueEntry(
    mediaType: 1,
    widthMm: 40,
    heightMm: 20,
    barcode: '070626199',
    sourceId: '80032472',
    barcodeEvidence: 'catalogue-primary',
  ),
  CatalogueEntry(
    mediaType: 1,
    widthMm: 40,
    heightMm: 30,
    barcode: '070626200',
    sourceId: '80001799',
    barcodeEvidence: 'catalogue-primary',
  ),
  CatalogueEntry(
    mediaType: 1,
    widthMm: 40,
    heightMm: 40,
    barcode: '010424618',
    sourceId: '80032603',
    barcodeEvidence: 'catalogue-primary',
  ),
  CatalogueEntry(
    mediaType: 1,
    widthMm: 40,
    heightMm: 60,
    barcode: '022824258',
    sourceId: '80036381',
    barcodeEvidence: 'catalogue-primary',
  ),
  CatalogueEntry(
    mediaType: 1,
    widthMm: 40,
    heightMm: 80,
    barcode: '69522800001478',
    sourceId: '50229043',
    barcodeEvidence: 'catalogue-primary',
  ),
  CatalogueEntry(
    mediaType: 1,
    widthMm: 44,
    heightMm: 44,
    barcode: '040824050',
    sourceId: '80014719',
    barcodeEvidence: 'catalogue-primary',
  ),
  CatalogueEntry(
    mediaType: 1,
    widthMm: 45,
    heightMm: 20,
    barcode: '060723012',
    sourceId: '80032587',
    barcodeEvidence: 'catalogue-primary',
  ),
  CatalogueEntry(
    mediaType: 1,
    widthMm: 45,
    heightMm: 60,
    barcode: '010424623',
    sourceId: '50229046',
    barcodeEvidence: 'catalogue-primary',
  ),
  CatalogueEntry(
    mediaType: 1,
    widthMm: 50,
    heightMm: 15,
    barcode: '123025208',
    sourceId: '80113148',
    barcodeEvidence: 'catalogue-primary',
  ),
  CatalogueEntry(
    mediaType: 1,
    widthMm: 50,
    heightMm: 20,
    barcode: '11262110',
    sourceId: '80001173',
    barcodeEvidence: 'catalogue-primary',
  ),
  CatalogueEntry(
    mediaType: 1,
    widthMm: 50,
    heightMm: 30,
    barcode: '022824255',
    sourceId: '80000579',
    barcodeEvidence: 'catalogue-primary',
  ),
  CatalogueEntry(
    mediaType: 1,
    widthMm: 50,
    heightMm: 40,
    barcode: '03222123',
    sourceId: '80032570',
    barcodeEvidence: 'catalogue-primary',
  ),
  CatalogueEntry(
    mediaType: 1,
    widthMm: 50,
    heightMm: 50,
    barcode: '12222117',
    sourceId: '80001493',
    barcodeEvidence: 'catalogue-primary',
  ),
  CatalogueEntry(
    mediaType: 1,
    widthMm: 50,
    heightMm: 60,
    barcode: '060426251',
    sourceId: '80003856',
    barcodeEvidence: 'catalogue-primary',
  ),
  CatalogueEntry(
    mediaType: 1,
    widthMm: 50,
    heightMm: 70,
    barcode: '6971501220577',
    sourceId: '80032535',
    barcodeEvidence: 'catalogue-primary',
  ),
  CatalogueEntry(
    mediaType: 1,
    widthMm: 50,
    heightMm: 80,
    barcode: '071426081',
    sourceId: '80084611',
    barcodeEvidence: 'catalogue-primary',
  ),
  CatalogueEntry(
    mediaType: 1,
    widthMm: 60,
    heightMm: 40,
    barcode: '6977031215731',
    sourceId: '80013469',
    barcodeEvidence: 'catalogue-primary',
  ),
  CatalogueEntry(
    mediaType: 1,
    widthMm: 60,
    heightMm: 50,
    barcode: '080625209',
    sourceId: '80062856',
    barcodeEvidence: 'catalogue-primary',
  ),
  CatalogueEntry(
    mediaType: 1,
    widthMm: 60,
    heightMm: 60,
    barcode: '6978642800453',
    sourceId: '80000258',
    barcodeEvidence: 'catalogue-primary',
  ),
  CatalogueEntry(
    mediaType: 1,
    widthMm: 60,
    heightMm: 80,
    barcode: '060923009',
    sourceId: '80013475',
    barcodeEvidence: 'catalogue-primary',
  ),
  CatalogueEntry(
    mediaType: 1,
    widthMm: 70,
    heightMm: 40,
    barcode: '6971501224414',
    sourceId: '80000581',
    barcodeEvidence: 'catalogue-primary',
  ),
  CatalogueEntry(
    mediaType: 1,
    widthMm: 70,
    heightMm: 80,
    barcode: '6978061953617',
    sourceId: '80001426',
    barcodeEvidence: 'catalogue-primary',
  ),
  CatalogueEntry(
    mediaType: 1,
    widthMm: 70,
    heightMm: 100,
    barcode: '060226086',
    sourceId: '80013478',
    barcodeEvidence: 'catalogue-primary',
  ),
  CatalogueEntry(
    mediaType: 1,
    widthMm: 76,
    heightMm: 130,
    barcode: '061826162',
    sourceId: '80113260',
    barcodeEvidence: 'catalogue-primary',
  ),
  CatalogueEntry(
    mediaType: 1,
    widthMm: 80,
    heightMm: 40,
    barcode: '121024064',
    sourceId: '80071393',
    barcodeEvidence: 'catalogue-primary',
  ),
  CatalogueEntry(
    mediaType: 1,
    widthMm: 80,
    heightMm: 50,
    barcode: '060923019',
    sourceId: '80013485',
    barcodeEvidence: 'catalogue-primary',
  ),
  CatalogueEntry(
    mediaType: 1,
    widthMm: 80,
    heightMm: 80,
    barcode: '012226003',
    sourceId: '80060859',
    barcodeEvidence: 'catalogue-primary',
  ),
  CatalogueEntry(
    mediaType: 1,
    widthMm: 80,
    heightMm: 100,
    barcode: '072226110',
    sourceId: '80084603',
    barcodeEvidence: 'catalogue-primary',
  ),
  CatalogueEntry(
    mediaType: 1,
    widthMm: 80,
    heightMm: 160,
    barcode: '082024269',
    sourceId: '80026366',
    barcodeEvidence: 'catalogue-primary',
  ),
  CatalogueEntry(
    mediaType: 1,
    widthMm: 100,
    heightMm: 60,
    barcode: '121024115',
    sourceId: '80071479',
    barcodeEvidence: 'catalogue-primary',
  ),
  CatalogueEntry(
    mediaType: 1,
    widthMm: 100,
    heightMm: 70,
    barcode: '121024063',
    sourceId: '80071411',
    barcodeEvidence: 'catalogue-primary',
  ),
  CatalogueEntry(
    mediaType: 1,
    widthMm: 100,
    heightMm: 100,
    barcode: '121024118',
    sourceId: '80071394',
    barcodeEvidence: 'catalogue-primary',
  ),
  CatalogueEntry(
    mediaType: 1,
    widthMm: 100,
    heightMm: 150,
    barcode: '121024252',
    sourceId: '80071481',
    barcodeEvidence: 'catalogue-primary',
  ),
  CatalogueEntry(
    mediaType: 1,
    widthMm: 100,
    heightMm: 200,
    barcode: '010526174',
    sourceId: '80113808',
    barcodeEvidence: 'catalogue-primary',
  ),
];

CatalogueEntry? findCatalogueEntry(MediaParameters params) {
  for (final entry in catalogue) {
    if (entry.mediaType == params.mediaType &&
        entry.widthMm == params.widthMm &&
        entry.heightMm == params.heightMm) {
      print('[DEBUG] findCatalogueEntry: params=${params.toMap()} found=${entry.barcode}');
      return entry;
    }
  }
  print('[DEBUG] findCatalogueEntry: params=${params.toMap()} not found');
  return null;
}

Uint8List setBarcode(Uint8List payload, String barcode) {
  if (!RegExp(r'^[0-9]{1,15}$').hasMatch(barcode)) {
    throw ArgumentError('Unsupported catalogue barcode.');
  }
  final decoded = decodePayload(payload);
  final mutable = decoded.mutable;
  final fixed = decoded.fixed;
  int terminator = -1;
  for (int i = 32; i < 48; i++) {
    if (fixed[i] == 0) {
      terminator = i;
      break;
    }
  }
  if (terminator < 32 || terminator >= 48) {
    throw ArgumentError('Unsupported barcode string boundary.');
  }
  for (int i = 32; i < terminator; i++) {
    if (fixed[i] < 48 || fixed[i] > 57) {
      throw ArgumentError('Unsupported source barcode.');
    }
  }
  final newEnd = 32 + barcode.length;
  for (int i = terminator + 1; i <= newEnd; i++) {
    if (fixed[i] != 0) {
      throw ArgumentError(
        'Barcode edit would overwrite unknown nonzero bytes.',
      );
    }
  }
  for (int i = 32; i <= newEnd; i++) {
    fixed[i] = 0;
  }
  for (int i = 0; i < barcode.length; i++) {
    fixed[32 + i] = barcode.codeUnitAt(i);
  }
  final out = encodePayload(mutable, fixed);
  print('[DEBUG] setBarcode: in=${bytesToHex(payload)} barcode=$barcode out=${bytesToHex(out)}');
  return out;
}

Uint8List applyCatalogueBarcode(Uint8List payload) {
  final params = payloadToParameters(payload);
  final entry = findCatalogueEntry(params);
  final out = entry != null
      ? setBarcode(payload, entry.barcode)
      : Uint8List.fromList(payload);
  print('[DEBUG] applyCatalogueBarcode: in=${bytesToHex(payload)} out=${bytesToHex(out)}');
  return out;
}
