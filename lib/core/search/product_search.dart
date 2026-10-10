/// Search is presentation only: never use this key to merge stock or quantities.
String productSearchKey(String value) =>
    value.toLowerCase().replaceAll(RegExp(r'\s+'), '');

bool productSearchMatches(String value, String query) {
  final text = productSearchKey(value);
  return query
      .trim()
      .split(RegExp(r'\s+'))
      .every((word) => text.contains(productSearchKey(word)));
}
