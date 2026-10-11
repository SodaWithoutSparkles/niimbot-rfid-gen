# NIIMBOT NFC Writer

An Android app that writes NIIMBOT roll data straight to an NFC tag, and reads
it back. No `.bin` export, no file transfer, no desktop tool — enter the roll,
scan the tag, tap **Write tag**.

Built with Flutter. Android only.

---

## What it does

**Writer** — pick a roll, scan the tag, write.

- Roll presets from the NIIMBOT catalogue, or set the dimensions yourself
- Live validation from the same rules the generator uses
- Scan the tag to fill the UID and detect the tag type automatically
- Password handling that tries as little as possible (see *Passwords* below)
- Per-page results, and a full TX/RX transaction log

**Decoder** — read a tag and see what it carries.

- Warns if a tag is not a NIIMBOT roll tag, and says why
- Dimensions, media type, nominal quantity, usage limit
- Catalogue code and its source id
- Labels printed, labels left on the roll, capacity left

**Log** — every NFC command sent and received, with timings.

---

## Usage

### Requirements

- An Android phone with NFC (Android 7.0 / API 24 or newer)
- NTAG213 (verified), NTAG215 or NTAG216 tags

### Building

```sh
flutter pub get
flutter run                  # debug build onto a connected phone
flutter build apk --release  # release build
```

### Writing a tag

1. **Choose a roll.** Pick a preset, or *Custom…* to enter your own dimensions.
   The usage limit updates as you type.
2. **Fill in the tag.** Tap **Scan tag** and hold the tag against the phone.
   The UID and tag type fill in by themselves.
3. **Check the password.** The default `12345678` is almost always right for
   tags this app has written. Leave *Auto-try the three known passwords* on
   unless you have a reason not to.
4. **Tap Write tag** and confirm. The dialog lists every page that will be
   touched.
5. **Wait.** The progress bar shows which page it is on. Hold the tag still
   until it finishes.

The result tells you what happened to each page. Two warnings are **normal and
expected**:

```
page 43 could not be written (protected)
page 44 could not be written (protected)
```

Real NTAG21x hardware refuses writes to the password and pack pages. The app
reports these as warnings, not failures. If pages 5–34 are confirmed, the tag
is good.

### Reading a tag

Open the menu (☰) → **Decoder** → **Scan tag**. You get the roll details, or a
plain reason why the tag is not one of ours.

### Reading the log

The receipt icon in the app bar, or the menu → **Transaction log**. Every frame
is logged with its timing:

```
TX A2 05 74 2F C7 63 -> [empty: ACK] (8.2ms)
```

---

## Things worth knowing

### Passwords

NTAG21x tags count failed authentication attempts against a **finite** counter,
and enough failures can lock a tag out. So the app avoids guessing:

1. It writes the first page with **no password at all**. Most tags are
   unprotected, so this succeeds without spending a single attempt.
2. Only if that is refused does it try passwords, most-likely first
   (`FFFFFFFF`, the NXP factory default), each tried at most once.

**This app cannot set a password.** The generator's password bytes land on a
page real hardware refuses to write, so a tag written here keeps whatever
password it already had.

### Lock bits

The config page holds lock bits. This app **only ever clears them, never sets
them**, so it cannot permanently lock a page. It does not touch the config
byte. Clear a lock bit and you cannot set it again, so only run this on tags
you are provisioning.

### Reading back

A write ends with a read-back of every written page, comparing only the bytes
the app owns. That is roughly half the round trips and explains most of the
wait.

---

## Credits and origins

**This is a reverse-engineered reimplementation of the work of
[openroll.cc](https://openroll.cc/).** The generator here is a port of logic
recovered from that site's published JavaScript bundle. The original author is
anonymous and is not affiliated with this project. All credit for the format,
the reverse-engineering effort and the original tool belongs to them.

If you have not already, **read the [OpenRoll FAQ](https://openroll.cc/#faq)**
before using this. It covers what the tag format is, which printers are
supported, and what the original tool can do that this one cannot.

This app also stands on:

- [flutter_nfc_kit](https://pub.dev/packages/flutter_nfc_kit) for raw NFC
- The Zip of source code for a demo NFC app provided by MultiMote inside discord for raw command examples

---

## Development

```sh
flutter test          # 122 tests
flutter analyze
```

Tests cover the generator golden vector, the write plan, the write runner
against a fake tag, the tag decoder, and the UI. The NFC layer is abstracted
behind `TagSession` so all of it is testable without hardware.

### Layout

```
lib/core/generator/   reverse-engineered payload logic  (see licensing)
lib/core/nfc/         raw NFC: commands, sessions, write plan and runner
lib/ui/               writer, decoder and log screens
test/                 unit and widget tests
```

---

## Provenance and limits

**This project was written with LLM assistance.** The generator was ported by
an AI from minified JavaScript it had never seen explained; the NFC layer and
UI were built the same way. It has been reviewed and tested, but it is the work
of a language model rather than a person who reverse-engineered a protocol over
time. Read the code before trusting it with anything you care about.

It has **not** been validated against a broad range of real hardware. The NFC
path is exercised by a fake tag in tests and by the logic being a faithful
port of a working reference implementation — not by the author running it
against a drawer full of tags.

Although it has been tested against a few roll sizes and 1 singular printer, 
it has **not** been tested against the full range of NIIMBOT catalogue rolls or
various printer models. It is possible that some combinations of roll and 
printer will not work, and the author cannot guarantee that it will work for you.
If you find a combination that does not work, please report it in the issues.

---

## Licence

**Everything except the generator is MIT licensed.** See [LICENSE](LICENSE).

**The generator is not.** `lib/core/generator/` is reverse-engineered from
[openroll.cc](https://openroll.cc/), whose source carries no licence. It would
not be fair to slap one of my own on someone else's work, so it is left
unlicensed and is excluded from the MIT grant:

- `lib/core/generator.dart`
- `lib/core/generator/**`

That covers `test/generator_test.dart` as well, since it exists to hold the
ported behaviour in place. If you need the generator and cannot accept those
terms, use [openroll.cc](https://openroll.cc/) directly.

---

## Disclaimer

**This software is provided AS-IS, without warranty of any kind.**

The author accepts no liability for any damage arising from its use, including
but not limited to damage to printers, tags, phones, or data. Writing to an NFC
tag changes its contents permanently. Lock bits cannot be set once cleared, and
misconfigured parameters can produce tags your printer will not read. **Test
on a tag you do not mind ruining.**

If any of that matters to you, read the [OpenRoll FAQ](https://openroll.cc/#faq)
first.