import 'package:flutter/material.dart';

/// Wraps a field error so a long message wraps by word instead of
/// ellipsising.
///
/// The generator's own range messages run to several lines, and the default
/// single-line error text truncates away the part that says what the limit is.
Widget? wrapFieldError(String? message) {
  if (message == null) return null;
  return Text(
    message,
    softWrap: true,
    style: const TextStyle(fontSize: 12, height: 1.3),
  );
}