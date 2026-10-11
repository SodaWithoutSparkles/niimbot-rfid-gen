// Read-only: work out whether a tag carries the NIIMBOT roll payload.
//
// This never writes. The payload is TEA-encrypted with a fixed key that lives
// in the generator's constants, so decoding a tag needs no key material from
// the tag itself and no lookup table.

import 'dart:typed_data';

import '../generator.dart';
import '../log.dart';
import 'commands.dart';
import 'flutter_nfc_session.dart';
import 'tag_session.dart';

/// The NIIMBOT payload is 120 bytes starting at page 5, on every NTAG21x.
const int payloadStartPage = 5;
const int payloadPageCount = 30;
const int payloadByteCount = payloadPageCount * 4;

/// Reads [pageCount] pages starting at [startPage].
///
/// `READ` answers with 16 bytes spanning four pages, but the reference app
/// keeps only the first four because the extra twelve wrap around at the end
/// of memory. So one command per page, four bytes kept.
Future<Uint8List> readPages(
  TagSession session,
  int startPage,
  int pageCount,
) async {
  final out = Uint8List(pageCount * 4);

  for (var i = 0; i < pageCount; i++) {
    final page = startPage + i;
    final response = await session.transceive(cmdReadPage(page));
    if (response.length < 4) {
      throw NfcException(
        NfcErrorKind.comms,
        'page $page answered with ${response.length} bytes',
      );
    }
    out.setRange(i * 4, i * 4 + 4, response.sublist(0, 4));
  }

  return out;
}

class RollInfo {
  final Uint8List uid;
  final TagType? tagType;
  final int pageCount;

  final int count;
  final int capacity;
  final int usageLimit;
  final int nominalQuantity;
  final int widthMm;
  final int heightMm;
  final int gapMm;
  final int mediaType;

  /// NUL-padded catalogue code, or an empty string.
  final String barcode;

  final CatalogueEntry? catalogueEntry;

  const RollInfo({
    required this.uid,
    required this.tagType,
    required this.pageCount,
    required this.count,
    required this.capacity,
    required this.usageLimit,
    required this.nominalQuantity,
    required this.widthMm,
    required this.heightMm,
    required this.gapMm,
    required this.mediaType,
    required this.barcode,
    required this.catalogueEntry,
  });

  /// Labels the tag still allows.
  int get capacityLeft => capacity - count;

  /// Labels left against the nominal roll size. Can go negative if a roll is
  /// used past its stated quantity.
  int get rollsLeft => nominalQuantity - count;

  bool get isPrinted => count > 0;

  String get mediaTypeLabel => mediaTypes
      .firstWhere((m) => m.value == mediaType,
          orElse: () => MediaTypeOption(value: mediaType, label: 'Unknown'))
      .label;

  /// Dimensions with any zero (continuous media) shown the way the app writes
  /// them.
  String get geometryLabel => heightMm == 0 && gapMm == 0
      ? '$widthMm mm wide, continuous'
      : '$widthMm × $heightMm mm, ${gapMm}mm gap';
}

/// What a scan found. A tag that is not a NIIMBOT roll is a normal outcome,
/// not an error.
sealed class RollProbe {
  const RollProbe();
}

class RollFound extends RollProbe {
  final RollInfo info;

  const RollFound(this.info);
}

class RollNotRecognised extends RollProbe {
  final String reason;

  const RollNotRecognised(this.reason);
}

/// Polls for a tag and decodes its payload, writing nothing.
Future<RollProbe> readRoll(TagSession session) async {
  final info = session.tag;
  final type = info.tagType;
  if (type == null) {
    return RollNotRecognised(
      info.pageCount == null
          ? 'GET_VERSION reported a tag size this app does not know.'
          : '${info.pageCount} pages is not an NTAG213, 215 or 216.',
    );
  }

  final spec = getTagTypeSpec(type);
  if (spec.pages < payloadStartPage + payloadPageCount) {
    return RollNotRecognised('${spec.label} is too small to hold a roll payload.');
  }

  Uint8List payload;
  try {
    payload = await readPages(session, payloadStartPage, payloadPageCount);
  } on NfcException catch (e) {
    // A genuine NIIMBOT roll does not hand its payload over. Its password is
    // 0x12345678 and its pages stay locked, and the referenced raw nfc tool
    // app only gets about 16 bytes back. So a read failure here says as much
    // about the tag being real as it does about the tag being broken.
    log.w('could not read the payload: ${e.message}');
    return RollNotRecognised(
      'Could not read the payload: ${e.message}. This could be a genuine '
      'NIIMBOT tag, but this app cannot read it.',
    );
  }

  // decodePayload throws on a bad CRC, which is the format test.
  final NiimbotPayload decoded;
  try {
    decoded = decodePayload(payload);
  } on ArgumentError catch (e) {
    log.i('not a roll tag: ${e.message}');
    return RollNotRecognised('The payload is not NIIMBOT roll data (${e.message}).');
  }

  // The payload must belong to this physical tag. This is what stops a stale
  // roll from being read as if it were freshly written.
  try {
    assertFixedIdentity(decoded.fixed, info.uid);
  } on ArgumentError {
    log.w('payload identity does not match the tag UID');
    return const RollNotRecognised(
      'The payload carries a different UID, so it belongs to another tag.',
    );
  }

  MediaParameters params;
  try {
    params = payloadToParameters(payload);
  } on ArgumentError catch (e) {
    return RollNotRecognised('The roll dimensions are not valid (${e.message}).');
  }

  final barcode = _readBarcode(decoded.fixed);
  final entry = findCatalogueEntry(params);

  return RollFound(RollInfo(
    uid: info.uid,
    tagType: type,
    pageCount: spec.pages,
    count: decoded.count,
    capacity: decoded.capacity,
    usageLimit: params.usageLimit,
    nominalQuantity: params.nominalQuantity,
    widthMm: params.widthMm,
    heightMm: params.heightMm,
    gapMm: params.gapMm,
    mediaType: params.mediaType,
    barcode: barcode,
    catalogueEntry: entry,
  ));
}

/// Convenience wrapper: polls for a tag and closes the session afterwards.
Future<RollProbe> scanRoll() async {
  TagSession? session;
  try {
    session = await FlutterNfcSession.poll();
    return await readRoll(session);
  } finally {
    await session?.close();
  }
}

/// The barcode is a NUL-padded digit string at fixed[32..48].
String _readBarcode(Uint8List fixed) {
  var end = 32;
  while (end < 48 && fixed[end] != 0) {
    end++;
  }
  return String.fromCharCodes(fixed.sublist(32, end));
}