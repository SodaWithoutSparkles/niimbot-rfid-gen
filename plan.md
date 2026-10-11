# Plan — NIIMBOT NFC Writer (Flutter, Android)

Replace the current tap-tag → export `.bin` → side-load → write workflow with a single
self-contained app: enter roll details, scan the tag UID, tap **Write tag**, and the app
generates the openroll image in-process and writes it straight to the tag over NFC.

---

## 1. What exists today (verified, not assumed)

| Fact                                                                                                                     | Where                                               |
| ------------------------------------------------------------------------------------------------------------------------ | --------------------------------------------------- |
| Generator port is complete and green against the golden vector. **Treated as correct — not re-tested, not refactored.**  | `lib/core/generator/**`, `test/generator_test.dart` |
| `generateTagFile()` returns a full tag memory image (`pages*4` = 180 / 540 / 924 bytes)                                  | `lib/core/generator/generator.dart`                 |
| Provisioning masks: `known` + `write`, both 180 bytes                                                                    | `lib/core/generator/uid_masks.dart`                 |
| Physical byte-offset mapping: `off < 164 → off`, `off >= 164 → configPage*4 + (off - 164)`                               | `lib/core/generator/export.dart:159`                |
| `TagTypeSpec` gives `configPage` = 41 / 131 / 227                                                                        | `lib/core/generator/export.dart`                    |
| 68-entry roll catalogue (all `mediaType: 1`), plus `rollProfile` (50×30, gap 6, 230 labels)                              | `lib/core/generator/barcode.dart`, `profile.dart`   |
| `flutter_nfc_kit ^3.6.2` is a direct dependency; **nothing in the app imports it yet**                                   | `pubspec.yaml`                                      |
| `lib/main.dart` is still the stock Flutter counter demo                                                                  | `lib/main.dart`                                     |
| Android manifest has **no** `android.permission.NFC` and no `uses-feature`                                               | `android/app/src/main/AndroidManifest.xml`          |
| Plugin requires `minSdkVersion 24`                                                                                       | `references/flutter_nfc_kit/android/build.gradle`   |
| Toolchain: Flutter 3.44.8 / Dart 3.12.2 at `C:\dev\flutter`; `dart test` alone does **not** work (needs the Flutter SDK) | `android/local.properties`                          |

### Hard-won facts from the proven reference app (`references/nfcraw-en-src/.../MainActivity.java`)

These drive the whole NFC design. They are the reason this is not a `writeBlock` loop.

1. **Raw `transceive` is mandatory.** `PWD_AUTH` is command `0x1B`; it has no
   `MifareUltralight` equivalent, so `FlutterNfcKit.readBlock` / `writeBlock` cannot be used
   for the write path.
2. **Reader mode flags:** `FLAG_READER_NFC_A | FLAG_READER_SKIP_NDEF_CHECK`, with
   `EXTRA_READER_PRESENCE_CHECK_DELAY = 5000` — on some phones the presence check
   re-activates the tag and is required for it to respond at all.
3. **A NAK puts the tag in IDLE.** Android surfaces a NAK as an `IOException`. The reference
   app reconnects after any failed transceive. The session can only be revived by
   `finish()` + `poll()` (flutter_nfc_kit has no `close()`/`connect()` pair).
4. **After `PWD_AUTH` succeeds, do not reconnect** — that resets the authenticated session.
5. **ACK is a 4-bit `0x0A` that Android's stack swallows** → an **empty response means ACK**.
   A 1-byte response is a NAK; low nibble `0x0` = protected/invalid address, `0x1` = CRC,
   `0x4` = auth counter overflow, `0x5` = EEPROM write error.
6. **`READ 0x30 p` returns 16 bytes; take the first 4.** Taking the first 4 is what avoids
   wrap-around garbage on the last page of memory.
7. **`GET_VERSION 0x60` → byte 6 = size**: `0x0F`→45 (NTAG213), `0x11`→135 (NTAG215),
   `0x13`→231 (NTAG216).
8. **Blocks 43 and 44 fail.** The generator's write mask puts the 4-byte password at
   offset 172 and `0x5555` at offset 176 — pages 43 and 44 of an NTAG213. Those pages do
   not accept writes on real hardware. This is expected and must be reported as a warning,
   never as a failure.

---

## 2. Core design decision — how the generator image becomes NFC writes

The generator emits one flat memory image. The tag only accepts **4-byte page** writes, and
some of the pages we touch are only **partially** ours.

**Rule (single source of truth, already implemented in `export.dart`):**

```
for every byte offset `off` where writeMask[off] != 0:
    target = off < 164 ? off : configPage*4 + (off - 164)
    merged[target] = (actual[target] & ~writeMask[off]) | (value[target] & writeMask[off])
```

So the app does not invent a layout. It:

1. takes `provisioningMasks().write` and `generateTagFile(...).bytes`;
2. groups masked bytes by physical page;
3. **full-mask page** → write the 4 bytes straight;
4. **partial-mask page** → `READ` the live page, apply the mask, write back (read-modify-write);
5. verifies by re-reading and comparing **only the masked bytes**.

This is layout-independent. Whatever the physical page numbering turns out to be, the mask
decides what we write, and anything that does not stick surfaces as a mismatch warning.

### Resulting plan for NTAG213 (derived, to be asserted in a unit test)

| Pages             | Kind    | Mask          | Value                                |
| ----------------- | ------- | ------------- | ------------------------------------ |
| 5 – 34 (30 pages) | full    | `FF FF FF FF` | payload (generator)                  |
| 41                | partial | `C0 00 00 FF` | config page, RMW                     |
| 42                | partial | `9F 00 00 00` | password page, RMW                   |
| 43                | full    | `FF FF FF FF` | `12 34 56 78` — **expected to fail** |
| 44                | partial | `FF FF 00 00` | `55 55` — **expected to fail**       |

34 pages total. For NTAG215/216 the last four become 131–134 / 227–230.

### Explicit non-goals

- **Do not** pass a live tag read as `GenerateInput.targetMemory`. `assertMemoryBcc`
  expects the generator's *logical* UID layout (`BCC0` at byte 3, `BCC1` at byte 8), which is
  not the physical NTAG page layout (`BCC0`/`BCC1` both live in page 2). It would throw.
  UID consistency is checked in the app against `NFCTag.id` instead.
- Bytes 0–19 of the image (UID/BCC header, NDEF CC in the preset) are **never written** —
  the mask is zero there. Do not try to reconcile them with a live read.
- No `.bin` export/import UI, no share sheet, no new pub dependencies.

---

## 3. File layout

```
lib/
  main.dart                              REWRITE  app bootstrap only
  ui/
    app.dart                             NEW      MaterialApp, theme, Material 3
    log/log_page.dart                    NEW      full transaction log screen
    write/
      write_page.dart                    NEW      main screen
      write_controller.dart              NEW      ChangeNotifier, owns the flow
      roll_form.dart                     NEW      roll details card
      tag_form.dart                      NEW      tag type / UID / password card
      write_result_view.dart             NEW      per-page outcomes + warnings
  core/
    log.dart                             NEW      bounded log + broadcast stream
    nfc/
      commands.dart                      NEW      NTAG command builders + ACK/NAK decode
      tag_session.dart                   NEW      abstract session (testable)
      flutter_nfc_session.dart           NEW      FlutterNfcKit implementation
      write_plan.dart                    NEW      memory image -> List<PagePlan>
      write_runner.dart                  NEW      auth + write + verify -> WriteReport
    generator.dart + generator/          EDIT    strip print()s only
```

---

## 4. Work items

### Phase A — logging backbone + debug-print cleanup

- **A1** `lib/core/log.dart`
  `LogLevel {debug, info, warn, error}`. Singleton with a `List<LogEntry>` capped at 5000
  (drop oldest) and a `Stream<LogEntry>` broadcast controller. `log.d/i/w/e(String)` plus
  `log.debug()` which additionally routes to `debugPrint` **only under `kDebugMode`**.
  Entry carries `DateTime` + monotonic ms-since-start (mirrors the reference app's
  `SystemClock.elapsedRealtime()` offset column).
- **A2** Strip debug prints from the generator.
  There are ~20 `print('[DEBUG] …')` calls across `bytes.dart`, `tea.dart`, `crc.dart`,
  `payload.dart`, `media_params.dart`, `profile.dart`, `uid_masks.dart`, `orf1.dart`,
  `export.dart`, `barcode.dart`, `generator.dart`. `bytesToHex` logs on **every call** and
  sits in the hot path — this is the real cost.
  Replace each with `debugLog('…')` backed by A1 (so debug builds keep the visibility and
  release builds are silent), and delete the `dart_output.txt` capture habit.
  **No behavioural change. Golden-vector test must stay green.**

### Phase B — raw NFC layer

- **B1** `core/nfc/commands.dart`
  `cmdGetVersion() = [0x60]`, `cmdReadPage(p) = [0x30, p]`,
  `cmdWritePage(p, d) = [0xA2, p, d0..d3]`, `cmdPwdAuth(pwd) = [0x1B, p0..p3]`.
  `describeAck(Uint8List)` → `ACK` / `NAK <n> – <reason>` per fact #5.
  `pagesFromVersion(size)` and `tagTypeForPages(n)` per fact #7.
- **B2** `core/nfc/tag_session.dart`
  ```dart
  abstract class TagSession {
    TagInfo get tag;                      // uid, tagType?, pageCount?
    Future<Uint8List> transceive(Uint8List cmd, {Duration? timeout});
    Future<void> revive();                // finish() + poll()
    Future<void> close();
  }
  ```
- **B3** `core/nfc/flutter_nfc_session.dart`
  - `poll(timeout: 60s, androidCheckNDEF: false, androidPlatformSound: false,
    readIso14443B/18092/15693: false, androidReaderModeFlags: 0x80|0x100,
    extraReaderPresenceCheckDelay: 5s)`
    — exactly the reference app's reader-mode configuration.
  - `transceive` passes `Uint8List` in/out; **every call is logged TX/RX with elapsed ms**,
    formatted like the reference app (`TX A2 05 74 2F C7 63 -> [empty: ACK] (8.2ms)`).
  - Map `PlatformException.code` to outcomes:
    `500` = comms/NAK → recoverable per page · `503` = tag removed → fatal ·
    `406` = no tag · `404` = NFC disabled.
  - Tag identity from `NFCTag.id` (7-byte hex, feeds `parseUid` directly), page count from
    `NFCTag.mifareInfo`, confirmed with `GET_VERSION` once per session.

### Phase C — write plan + runner

- **C1** `core/nfc/write_plan.dart` (pure Dart, no NFC — the unit-testable core)
  ```dart
  class PagePlan {
    final int page;          // physical page index
    final List<int> mask;    // 4 entries
    final List<int> value;   // 4 entries
    bool get isFull;
    List<int> apply(List<int> actual);   // (actual & ~mask) | (value & mask)
  }
  List<PagePlan> buildWritePlan(Uint8List memory, TagType type);
  ```
  Skips bytes whose target offset falls past the end of `memory` (defensive only).
  Must reproduce the table in §2 exactly.
- **C2** `core/nfc/write_runner.dart`
  1. `PWD_AUTH` candidate loop (§5) → `authed` bool.
  2. For each `PagePlan` in ascending page order:
     - partial page → `READ`, `apply()`, `WRITE`;
     - full page → `WRITE`;
     - on success, log the TX/RX;
     - on `500`, log the NAK reason, mark the page failed, **keep going**.
  3. **Early abort:** if the *first* plan page fails, stop and report
     "tag rejected the write — it is probably password protected".
  4. **Revive:** at most 2 `revive()` + re-auth cycles, then give up and mark the remaining
     pages `notWritten`.
  5. Verification pass: re-`READ` every planned page, compare masked bytes, build
     `List<PageOutcome>`.
  6. `WriteReport { outcomes, warnings, fatalError }` where warnings read
     `data mismatch in block 43`, `block 43 could not be written (protected)`,
     `block 5 could not be verified`.
     **A report with warnings and no `fatalError` is a SUCCESS.** No warning may ever
     escalate to an error (requirement 6).

### Phase D — UI

- **D1** `ui/log/log_page.dart` — full transaction log, monospace, auto-scroll with a
  follow/pause toggle, per-level colouring, **Copy** and **Clear** actions. Reached from
  the header action button on the write screen (requirement 7).
- **D2** `ui/write/roll_form.dart`
  - Preset dropdown built from `catalogue` ("Gap labels · 50 × 30 mm · src 80000579") plus
    `rollProfile` as the default, plus "Custom…".
  - Custom mode: media type dropdown from `mediaTypes`; integer fields width / length /
    gap / nominal quantity. Length + gap are disabled and zeroed when media type is
    Continuous (media type 3), mirroring `generateTagFile`.
  - Live validation by calling the generator's own `computeUsageLimit` +
    `validateParameters(MediaParameters(...))`; render `FieldError.message` inline under
    the offending field.
  - Read-only derived chips: `usage limit`, `profile`, `custom vs catalogue`.
  - Advisory (non-blocking): `findCatalogueEntry(...) == null` → "no catalogue barcode for
    these dimensions".
- **D3** `ui/write/tag_form.dart`
  - Tag type dropdown from `tagTypes` (shows the `evidence` string as helper text).
  - UID field + **Scan** button → `poll` → fill `NFCTag.id`; auto-switch tag type from
    `GET_VERSION` when it disagrees with the selection.
  - Password: hex field (default `12345678`), three quick-pick chips
    (`12345678` / `00000000` / `FFFFFFFF`), and an "auto-try the three known passwords"
    switch (default on).
- **D4** `ui/write/write_controller.dart` — `ChangeNotifier`. Holds form state, NFC
  availability, busy flag, and the last `WriteReport`. Sequence:
  validate → `generateTagFile` → `buildWritePlan` → confirm dialog listing the pages that
  will be written → write → publish report. Surfaces generator `FieldError` /
  `ArgumentError` as inline messages.
- **D5** `ui/write/write_result_view.dart` — summary line
  (`32 written · 2 failed · 0 mismatched`), then a compact per-page grid of ✓ / ⚠ / ✗,
  then the warning list verbatim (`data mismatch in block 43`).
- **D6** `ui/app.dart` + `main.dart` — Material 3 theme, app title "NIIMBOT NFC Writer",
  header action `Icons.receipt_long` opening the log page.
- **D7** Android plumbing:
  - manifest: `<uses-permission android:name="android.permission.NFC"/>` +
    `<uses-feature android:name="android.hardware.nfc" android:required="true"/>`;
    `android:label="NIIMBOT NFC"`.
  - `app/build.gradle.kts`: pin `minSdk = 24` (plugin floor) instead of
    `flutter.minSdkVersion`.

---

## 5. Password handling (the one place we can brick a tag)

NTAG21x `PWD_AUTH` failures increment a **finite** counter that eventually blocks the tag.
So:

- Try the entered password **first**; if it is blank or fails and "auto-try" is on, try
  `12345678`, `00000000`, `FFFFFFFF` in that order, **each at most once per session**.
- Cache the password that worked in memory and reuse it for any later `revive()`.
- If no candidate authenticates, log it plainly and **still attempt the writes
  unauthenticated** — an unprotected tag needs no auth, so this is the common happy path.
- Never re-run the candidate loop against the same tag more than once. If writes still get
  NAKed, report a wrong-password error and stop.
- Note in the UI help text: this app cannot *set* a password. The generator's password
  bytes land on page 43, which real hardware rejects (fact #8).

---

## 6. Tests

| Test                               | Covers                                                                                                                                                                           |
| ---------------------------------- | -------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `test/generator_test.dart`         | **unchanged** — must stay green (golden vector)                                                                                                                                  |
| `test/write_plan_test.dart`        | `buildWritePlan` on the golden image → exactly pages 5–34 full + 41/42/43/44 partial with the §2 masks; `apply()` RMW maths; NTAG215/216 offset mapping                          |
| `test/write_runner_test.dart`      | fake `TagSession`: all-ACK run → 34 written, 0 warnings; NAK on 43/44 → success + exactly the two warnings; NAK on page 5 → early abort with the password message; revive budget |
| `test/log_test.dart`               | ring-buffer cap, level filtering, stream emission                                                                                                                                |
| `test/widget/write_page_test.dart` | renders; out-of-range quantity shows the generator's `FieldError.message`; continuous media disables length/gap; busy state blocks the write button                              |

Command (the Flutter SDK is not on `PATH` from this shell):

```
cmd.exe /c "C:\dev\flutter\bin\flutter.bat test"      # from niimbot_nfc_gen/
cmd.exe /c "C:\dev\flutter\bin\flutter.bat analyze"
```

---

## 7. Risks

| Risk                                                            | Mitigation                                                                                                                                    |
| --------------------------------------------------------------- | --------------------------------------------------------------------------------------------------------------------------------------------- |
| Pages 43/44 reject writes                                       | Expected (fact #8). Warning only, never a failure.                                                                                            |
| Physical page numbering differs from `TagTypeSpec.configPage`   | Plan is mask-driven, not layout-driven; a wrong assumption shows up as masked-byte mismatches in the verify pass, never as silent corruption. |
| Writing the config page (41) changes tag behaviour irreversibly | It is part of the proven openroll image. Covered by the confirm dialog, which lists exactly which pages will be touched.                      |
| NAK puts the tag in IDLE and kills the session                  | Ordered ascending (payload pages first), per-page tolerance, bounded revive budget.                                                           |
| `print()` removal breaks a golden test                          | Golden test asserts bytes only; prints are pure side effects. Re-run to confirm.                                                              |
| Phone drops the tag mid-write                                   | `503` → fatal, report partial state honestly (pages already written stay written).                                                            |
| Generator throws at the UI layer                                | `FieldError.field` maps to a form field; anything else shows as a banner and lands in the log.                                                |

---

## 8. Definition of done

- [ ] App opens, shows the roll form defaulted to the 30307 50×30 profile, no NFC permission error.
- [ ] Scan fills the UID from a real tag.
- [ ] Write produces pages 5–34 verified OK; 43/44 reported as warnings.
- [ ] Header button opens the full TX/RX transaction log; Copy works.
- [ ] Release build logs nothing from the generator.
- [ ] `flutter test` and `flutter analyze` clean.