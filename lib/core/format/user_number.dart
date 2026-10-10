/// Shared numeric input for quantities, costs and explicit conversion factors.
double? parseUserNumber(String value) {
  var text = value.trim();
  // Preserve existing comma thousands. Accept decimal comma when it cannot be
  // a thousands group; Spanish 419 also permits the canonical decimal point.
  if (RegExp(r'^-?\d{1,3}(,\d{3})+(\.\d+)?$').hasMatch(text)) {
    text = text.replaceAll(',', '');
  } else if (RegExp(r'^-?\d+,\d+$').hasMatch(text)) {
    text = text.replaceAll(',', '.');
  } else if (RegExp(r'^-?\d{1,3}(\.\d{3})+,\d+$').hasMatch(text)) {
    text = text.replaceAll('.', '').replaceAll(',', '.');
  }
  final result = double.tryParse(text);
  return result != null && result.isFinite ? result : null;
}
