/// Compose `WING-NUMBER` from structured wing + flat number fields.
///
/// Flat `number` is often stored as `E-303`. Callers must not concatenate
/// wing + number blindly or the label becomes `E-E-303`.
String formatFlatLabel(String? wingCode, String? flatNumber) {
  final wing = (wingCode ?? '').trim().toUpperCase();
  var number = (flatNumber ?? '').trim().toUpperCase();
  if (number.isEmpty && wing.isEmpty) return '';
  if (wing.isEmpty) return number;

  final prefix = '$wing-';
  while (number.startsWith(prefix)) {
    number = number.substring(prefix.length);
  }
  if (number.startsWith(wing) &&
      number.length > wing.length &&
      RegExp(r'^\d').hasMatch(number.substring(wing.length))) {
    number = number.substring(wing.length).replaceFirst(RegExp(r'^-+'), '');
  }
  if (number.isEmpty || number == wing) return wing;
  return '$wing-$number';
}
