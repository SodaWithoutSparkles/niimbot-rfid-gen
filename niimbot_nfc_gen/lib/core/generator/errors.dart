// Errors ported from reference-openroll.ts

class FieldError implements Exception {
  final String field;
  final String message;

  FieldError(this.field, this.message);

  @override
  String toString() => 'FieldError($field): $message';
}