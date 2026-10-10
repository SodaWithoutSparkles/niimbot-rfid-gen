import 'package:flutter/material.dart';

import 'core/log.dart';
import 'ui/app.dart';

void main() {
  log.i('NIIMBOT NFC Writer starting');
  runApp(const NfcWriterApp());
}