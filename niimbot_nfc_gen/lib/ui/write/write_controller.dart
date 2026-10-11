// Owns the write flow: form state, validation, generation, NFC, report.

import 'package:flutter/foundation.dart';
import 'package:flutter_nfc_kit/flutter_nfc_kit.dart';

import '../../core/generator.dart';
import '../../core/nfc/flutter_nfc_session.dart';
import '../../core/nfc/tag_session.dart';
import '../../core/nfc/write_plan.dart';
import '../../core/nfc/write_progress.dart';
import '../../core/nfc/write_runner.dart';

/// A memory image and the pages that will be written to it.
typedef Prepared = ({Uint8List memory, List<PagePlan> plan});

/// One entry in the roll dropdown: the built-in roll profile, a catalogue
/// dimension, or Custom.
class RollPreset {
  final String label;

  /// Null for the roll profile and for Custom.
  final CatalogueEntry? entry;

  final bool isCustom;

  const RollPreset(this.label, {this.entry, this.isCustom = false});
}

/// Custom comes first: it is the entry people reach for when their roll is
/// not in the catalogue, and burying it under 68 presets is hostile.
List<RollPreset> buildPresets() => [
      const RollPreset('Custom…', isCustom: true),
      RollPreset('${rollProfile.displayName} · ${printerProfile.name}'),
      ...catalogue
          .where((e) => e.mediaType == 1)
          .map((e) => RollPreset(
                '${e.widthMm} × ${e.heightMm} mm · src ${e.sourceId}',
                entry: e,
              )),
    ];

class WriteController extends ChangeNotifier {
  static const defaultPasswordHex = '12345678';

  late final List<RollPreset> presets = buildPresets();

  int presetIndex = 0;

  int mediaType = 1;
  int widthMm = 50;
  int heightMm = 30;
  int gapMm = 6;
  int nominalQuantity = 230;

  TagType tagType = TagType.ntag213;
  String uid = '';

  String passwordHex = defaultPasswordHex;
  bool autoTryPasswords = true;

  bool busy = false;
  bool nfcAvailable = false;

  /// Set while a scan is waiting for a tag.
  String? scanning;

  /// Set for anything that is not a field-level problem.
  String? banner;

  WriteReport? report;

  /// Where the write has got to. Null when nothing is running.
  ///
  /// A write is about 70 NFC round trips and one of them can block for ten
  /// seconds waiting for a tag, so this is what keeps the screen honest
  /// instead of showing an indeterminate spinner.
  WriteProgress? progress;

  /// Messages keyed by the generator's own field names, so a FieldError can
  /// be rendered under the field that caused it.
  final Map<String, String> fieldErrors = {};

  WriteController() {
    // The roll profile is the default selection.
    presetIndex = presets.indexWhere((p) => !p.isCustom && p.entry == null);
    revalidate();
  }

  bool get isCustom => presets[presetIndex].isCustom;

  bool get isContinuous => mediaType == 3;

  MediaParameters currentParams() => MediaParameters(
        mediaType: mediaType,
        widthMm: widthMm,
        heightMm: heightMm,
        gapMm: gapMm,
        nominalQuantity: nominalQuantity,
        usageLimit: safeUsageLimit(),
      );

  /// True when the catalogue has no barcode for the current dimensions. This
  /// is advisory: the tag still writes, it just has no catalogue barcode.
  bool get noCatalogueBarcode => findCatalogueEntry(currentParams()) == null;

  String? errorFor(String field) => fieldErrors[field];

  bool get canWrite =>
      !busy && fieldErrors.isEmpty && uid.isNotEmpty && banner == null;

  Future<void> refreshAvailability() async {
    final availability = await FlutterNfcKit.nfcAvailability;
    nfcAvailable = availability == NFCAvailability.available;
    notifyListeners();
  }

  void selectPreset(int index) {
    presetIndex = index;
    final entry = presets[index].entry;
    if (!presets[index].isCustom) {
      final physical = rollProfile.physical;
      mediaType = entry?.mediaType ?? 1;
      widthMm = entry?.widthMm ?? physical.widthMm;
      heightMm = entry?.heightMm ?? physical.heightMm;
      // The catalogue only knows the label size. Gap and quantity come from
      // the roll profile the payload template was built around.
      gapMm = physical.gapMm;
      nominalQuantity = physical.nominalQuantity;
    }
    revalidate();
    notifyListeners();
  }

  void setMediaType(int value) {
    mediaType = value;
    // The generator zeroes length and gap for continuous media, so the form
    // must show that rather than a stale value.
    if (value == 3) {
      heightMm = 0;
      gapMm = 0;
    }
    revalidate();
    notifyListeners();
  }

  /// Sets one custom field. An unparseable value becomes -1 so the
  /// generator's own range check produces the message.
  void setField(String key, String raw) {
    final value = int.tryParse(raw.trim()) ?? -1;
    switch (key) {
      case 'widthMm':
        widthMm = value;
      case 'heightMm':
        heightMm = value;
      case 'gapMm':
        gapMm = value;
      case 'nominalQuantity':
        nominalQuantity = value;
    }
    revalidate();
    notifyListeners();
  }

  void setTagType(TagType value) {
    tagType = value;
    notifyListeners();
  }

  void setUid(String value) {
    uid = value.trim();
    revalidate();
    notifyListeners();
  }

  int _uidRevision = 0;

  /// Bumped when the UID is filled by a scan rather than typed.
  ///
  /// The field is a TextFormField with an initialValue, and Flutter only reads
  /// that once when the field state is created. Without re-keying, a scanned
  /// UID lands in the controller but the box on screen stays empty.
  int get uidRevision => _uidRevision;

  void applyScannedUid(String value) {
    _uidRevision++;
    setUid(value);
  }

  void setPassword(String value) {
    passwordHex = value.trim();
    revalidate();
    notifyListeners();
  }

  int _passwordRevision = 0;

  /// Bumped when the password is set from outside the field, so the field
  /// reloads what it displays. Typing does not bump it, because that would
  /// reset the cursor on every keystroke.
  int get passwordRevision => _passwordRevision;

  /// Sets the password from a quick-pick chip.
  void applyPassword(String value) {
    _passwordRevision++;
    setPassword(value);
  }

  void setAutoTry(bool value) {
    autoTryPasswords = value;
    notifyListeners();
  }

  void clearBanner() {
    if (banner == null) return;
    banner = null;
    notifyListeners();
  }

  /// Runs the generator's own validators. Never throws: every problem
  /// becomes an inline message under the field that caused it.
  void revalidate() {
    fieldErrors.clear();
    banner = null;

    safeUsageLimit();
    try {
      validateParameters(currentParams());
    } on FieldError catch (e) {
      fieldErrors[e.field] = e.message;
    }

    if (uid.isEmpty) {
      fieldErrors['uid'] = 'Scan or type the tag UID.';
    } else {
      try {
        parseUid(uid);
      } on ArgumentError {
        fieldErrors['uid'] = 'Enter 14 hexadecimal characters.';
      }
    }

    if (passwordHex.isNotEmpty) {
      try {
        hexToBytes(normalisePassword(passwordHex));
      } on ArgumentError {
        fieldErrors['password'] = 'Password must be 8 hexadecimal digits.';
      }
    }
  }

  /// Usage limit is derived, so a bad quantity surfaces as a quantity error.
  int safeUsageLimit() {
    try {
      return computeUsageLimit(nominalQuantity);
    } on FieldError catch (e) {
      fieldErrors[e.field] = e.message;
      return 0;
    }
  }

  static String normalisePassword(String input) =>
      input.replaceAll(RegExp('[^0-9A-Fa-f]'), '');

  List<int> get passwordBytes {
    if (passwordHex.isEmpty) return const [];
    return hexToBytes(normalisePassword(passwordHex));
  }

  /// Scans a tag, fills the UID, and follows the tag's own idea of its type.
  Future<void> scan() async {
    if (busy) return;
    scanning = 'Waiting for a tag…';
    notifyListeners();

    TagSession? session;
    try {
      session = await FlutterNfcSession.poll();
      scanning = null;
      // 14 plain hex digits, which is what parseUid expects.
      applyScannedUid(session.tag.uid
          .map((b) => b.toRadixString(16).padLeft(2, '0'))
          .join()
          .toUpperCase());

      final scanned = session.tag.tagType;
      if (scanned != null) tagType = scanned;

      if (session.tag.pageCount == null) {
        banner = 'That tag is not an NTAG213/215/216, so its type was left as '
            'selected.';
      }
      revalidate();
    } on NfcException catch (e) {
      scanning = null;
      banner = switch (e.kind) {
        NfcErrorKind.timeout => 'No tag was presented.',
        NfcErrorKind.unavailable => 'This device has no NFC adapter.',
        _ => e.message,
      };
    } finally {
      await session?.close();
      notifyListeners();
    }
  }

  /// Generates the image and the page plan without touching the tag.
  ///
  /// Returns null when the input is bad; the reason is in [fieldErrors] or
  /// [banner].
  Future<Prepared?> prepare() async {
    banner = null;
    revalidate();
    if (fieldErrors.isNotEmpty) return null;

    try {
      final generated = await generateTagFile(GenerateInput(
        mediaType: mediaType,
        widthMm: widthMm,
        heightMm: heightMm,
        gapMm: gapMm,
        nominalQuantity: nominalQuantity,
        uid: uid,
        tagType: tagType,
      ));
      return (
        memory: generated.bytes,
        plan: buildWritePlan(generated.bytes, tagType),
      );
    } on FieldError catch (e) {
      fieldErrors[e.field] = e.message;
      return null;
    } on ArgumentError catch (e) {
      banner = e.message.toString();
      return null;
    }
  }

  /// Polls for a tag and runs the write. The caller confirms the plan first.
  ///
  /// [progress] is updated throughout, because a write is dozens of NFC round
  /// trips and one of them can block waiting for the tag.
  Future<WriteReport> writePlan(List<PagePlan> plan) async {
    busy = true;
    report = null;
    progress = const WriteProgress(
      WritePhase.connecting,
      0,
      1,
      'Waiting for a tag…',
    );
    notifyListeners();

    TagSession? session;
    try {
      session = await FlutterNfcSession.poll();
      final result = await WriteRunner.run(
        session,
        plan,
        password: passwordBytes,
        autoTryKnownPasswords: autoTryPasswords,
        onProgress: (value) {
          progress = value;
          notifyListeners();
        },
      );
      report = result;
      return result;
    } on NfcException catch (e) {
      final failure = WriteReport(
        outcomes: const [],
        warnings: const [],
        fatalError: e.message,
      );
      report = failure;
      return failure;
    } finally {
      await session?.close();
      progress = null;
      busy = false;
      notifyListeners();
    }
  }

  /// Prepare, write and publish, with no confirm step. Used by tests.
  Future<WriteReport> write() async {
    final prepared = await prepare();
    if (prepared == null) {
      return const WriteReport(outcomes: [], warnings: []);
    }
    return writePlan(prepared.plan);
  }
}