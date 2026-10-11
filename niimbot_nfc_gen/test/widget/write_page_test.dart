// Widget tests for the write screen.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:niimbot_nfc_gen/ui/app.dart';
import 'package:niimbot_nfc_gen/ui/decoder/decoder_page.dart';
import 'package:niimbot_nfc_gen/ui/write/roll_form.dart';
import 'package:niimbot_nfc_gen/ui/write/write_controller.dart';

/// Custom is the default selection, so this only makes it explicit.
Future<void> showCustom(WidgetTester tester) async {
  await tester.tap(find.byType(DropdownButtonFormField<int>).first);
  await tester.pumpAndSettle();
  await tester.tap(find.text('Custom…').last);
  await tester.pumpAndSettle();
}

TextFormField fieldFor(WidgetTester tester, String label) =>
    tester.widget<TextFormField>(find.widgetWithText(TextFormField, label));

FilledButton writeButton(WidgetTester tester) =>
    tester.widget<FilledButton>(find.byKey(const ValueKey('write-button')));

void main() {
  // The form is taller than the default 800x600 test surface, and ListView
  // builds lazily, so anything below the fold would simply not exist.
  void useTallSurface(WidgetTester tester) {
    tester.view.physicalSize = const Size(1000, 2600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
  }

  testWidgets('renders the roll form defaulted to Custom', (tester) async {
    useTallSurface(tester);
    await tester.pumpWidget(const NfcWriterApp());
    await tester.pumpAndSettle();

    expect(find.byType(RollForm), findsOneWidget);
    expect(find.text('Roll details'), findsOneWidget);
    expect(find.text('Tag'), findsOneWidget);

    // Custom is preselected, so the fields are on screen and the quantity is
    // the largest a tag can carry, not the 230 of the 30307 profile.
    expect(find.text('custom'), findsOneWidget);
    expect(find.text('usage limit 65534'), findsOneWidget);
    expect(fieldFor(tester, 'Nominal quantity').initialValue, '54612');
  });

  testWidgets('the write button is disabled until a UID is entered',
      (tester) async {
    useTallSurface(tester);
    await tester.pumpWidget(const NfcWriterApp());
    await tester.pumpAndSettle();

    expect(writeButton(tester).onPressed, isNull);
  });

  testWidgets('an out-of-range quantity shows the generator message',
      (tester) async {
    useTallSurface(tester);
    await tester.pumpWidget(const NfcWriterApp());
    await tester.pumpAndSettle();
    await showCustom(tester);

    await tester.enterText(
      find.widgetWithText(TextFormField, 'Nominal quantity'),
      '99999',
    );
    await tester.pumpAndSettle();

    // computeUsageLimit's own message, not one invented by the UI.
    expect(
      find.textContaining('must be a whole number from 1 to'),
      findsOneWidget,
    );
    expect(writeButton(tester).onPressed, isNull);
  });

  testWidgets('a valid quantity clears the error again', (tester) async {
    useTallSurface(tester);
    await tester.pumpWidget(const NfcWriterApp());
    await tester.pumpAndSettle();
    await showCustom(tester);

    final quantity = find.widgetWithText(TextFormField, 'Nominal quantity');
    await tester.enterText(quantity, '99999');
    await tester.pumpAndSettle();
    expect(find.textContaining('must be a whole number from 1 to'),
        findsOneWidget);

    await tester.enterText(quantity, '100');
    await tester.pumpAndSettle();
    expect(find.textContaining('must be a whole number from 1 to'),
        findsNothing);
    expect(find.text('usage limit 120'), findsOneWidget);
  });

  testWidgets('continuous media disables length and gap', (tester) async {
    useTallSurface(tester);
    await tester.pumpWidget(const NfcWriterApp());
    await tester.pumpAndSettle();
    await showCustom(tester);

    expect(fieldFor(tester, 'Length (mm)').enabled, isTrue);
    expect(fieldFor(tester, 'Gap (mm)').enabled, isTrue);

    await tester.tap(find.byType(DropdownButtonFormField<int>).last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Continuous media').last);
    await tester.pumpAndSettle();

    expect(fieldFor(tester, 'Length (mm)').enabled, isFalse);
    expect(fieldFor(tester, 'Gap (mm)').enabled, isFalse);

    // The generator zeroes both for media type 3, so the form shows that.
    expect(fieldFor(tester, 'Length (mm)').initialValue, '0');
    expect(fieldFor(tester, 'Gap (mm)').initialValue, '0');
  });

  testWidgets('a valid UID enables the write button', (tester) async {
    useTallSurface(tester);
    await tester.pumpWidget(const NfcWriterApp());
    await tester.pumpAndSettle();

    await tester.enterText(
        find.widgetWithText(TextFormField, 'UID'), '1DE1A193101080');
    await tester.pumpAndSettle();

    expect(writeButton(tester).onPressed, isNotNull);
  });

  testWidgets('a malformed UID is rejected inline', (tester) async {
    useTallSurface(tester);
    await tester.pumpWidget(const NfcWriterApp());
    await tester.pumpAndSettle();

    await tester.enterText(find.widgetWithText(TextFormField, 'UID'), 'NOTHEX');
    await tester.pumpAndSettle();

    expect(find.text('Enter 14 hexadecimal characters.'), findsOneWidget);
    expect(writeButton(tester).onPressed, isNull);
  });

  testWidgets('the known password chips fill the password field',
      (tester) async {
    useTallSurface(tester);
    await tester.pumpWidget(const NfcWriterApp());
    await tester.pumpAndSettle();

    await tester.tap(find.widgetWithText(ActionChip, '00000000'));
    await tester.pumpAndSettle();

    expect(find.text('Password'), findsOneWidget);
    expect(
      tester.widget<TextFormField>(find.widgetWithText(TextFormField, 'Password'))
          .initialValue,
      '00000000',
    );
  });

  testWidgets('a scanned UID appears in the field, not just the log',
      (tester) async {
    useTallSurface(tester);
    final controller = WriteController();
    await tester.pumpWidget(NfcWriterApp(controller: controller));
    await tester.pumpAndSettle();

    TextFormField uidField() => tester.widget<TextFormField>(
          find.widgetWithText(TextFormField, 'UID'),
        );

    expect(uidField().initialValue, isEmpty);

    // What scan() does once the tag has answered.
    controller.applyScannedUid('1DE1A193101080');
    await tester.pumpAndSettle();

    // Regression: initialValue is read only when the field state is created, so
    // without the revision key this stayed empty and the user saw nothing.
    expect(uidField().initialValue, '1DE1A193101080');
    expect(find.text('1DE1A193101080'), findsOneWidget);
  });

  testWidgets('a long quantity error wraps instead of ellipsising',
      (tester) async {
    useTallSurface(tester);
    await tester.pumpWidget(const NfcWriterApp());
    await tester.pumpAndSettle();
    await showCustom(tester);

    await tester.enterText(
      find.widgetWithText(TextFormField, 'Nominal quantity'),
      '99999',
    );
    await tester.pumpAndSettle();

    final error = tester
        .widgetList<Text>(find.byType(Text))
        .firstWhere((t) => (t.data ?? '').contains('whole number from 1 to'));
    expect(error.softWrap, isTrue);
    expect(error.overflow, isNot(TextOverflow.ellipsis));
  });

  testWidgets('the drawer opens the decoder', (tester) async {
    useTallSurface(tester);
    await tester.pumpWidget(const NfcWriterApp());
    await tester.pumpAndSettle();

    // The write page is home.
    expect(find.byType(RollForm), findsOneWidget);

    await tester.tap(find.byIcon(Icons.menu));
    await tester.pumpAndSettle();

    expect(find.byType(Drawer), findsOneWidget);
    expect(find.text('Decoder'), findsOneWidget);

    await tester.tap(find.text('Decoder'));
    await tester.pumpAndSettle();

    expect(find.byType(DecoderPage), findsOneWidget);
    expect(find.text('Scan tag'), findsOneWidget);
    // The drawer closed rather than stacking on top of the new page.
    expect(find.byType(Drawer), findsNothing);
  });

  testWidgets('the log page opens from the header action', (tester) async {
    useTallSurface(tester);
    await tester.pumpWidget(const NfcWriterApp());
    await tester.pumpAndSettle();

    await tester.tap(find.byIcon(Icons.receipt_long));
    await tester.pumpAndSettle();

    expect(find.text('Transaction log'), findsOneWidget);
    expect(find.byIcon(Icons.copy_all), findsOneWidget);
    expect(find.byIcon(Icons.delete_outline), findsOneWidget);
  });
}