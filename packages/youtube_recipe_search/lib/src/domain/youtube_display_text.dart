String decodeYoutubeDisplayText(String value) {
  return value.replaceAllMapped(
    RegExp(r'&(amp|lt|gt|quot|#39|#[0-9]+|#[xX][0-9a-fA-F]+);'),
    (match) {
      final entity = match.group(1)!;
      const named = <String, String>{
        'amp': '&',
        'lt': '<',
        'gt': '>',
        'quot': '"',
        '#39': "'",
      };
      final known = named[entity];
      if (known != null) return known;
      final radix =
          entity.startsWith('#x') || entity.startsWith('#X') ? 16 : 10;
      final digits = entity.substring(radix == 16 ? 2 : 1);
      final codePoint = int.tryParse(digits, radix: radix);
      if (codePoint == null ||
          codePoint > 0x10ffff ||
          (codePoint >= 0xd800 && codePoint <= 0xdfff)) {
        return match.group(0)!;
      }
      return String.fromCharCode(codePoint);
    },
  );
}
