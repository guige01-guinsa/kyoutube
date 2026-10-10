/// Issued links are preserved exactly; never add tracking identifiers locally.
Uri? affiliateUri(String program, String link) {
  if (link.length > 2048 || RegExp(r'[\s\\]').hasMatch(link)) return null;
  final uri = Uri.tryParse(link);
  if (uri == null ||
      uri.scheme != 'https' ||
      uri.userInfo.isNotEmpty ||
      uri.hasPort) {
    return null;
  }
  final valid = program == 'coupang'
      ? RegExp(r'^https://link\.coupang\.com/a/[A-Za-z0-9]+$').hasMatch(link)
      : program == 'naver'
          ? RegExp(
                  r'^https://(naver\.me|brandconnect\.naver\.com)/[^?#]+([?#].*)?$')
              .hasMatch(link)
          : program == 'youtube' &&
              RegExp(r'^https://(www\.youtube\.com/watch\?v=[A-Za-z0-9_-]{11}(&[^#]*)?|youtu\.be/[A-Za-z0-9_-]{11}(\?[^#]*)?|www\.youtube\.com/shorts/[A-Za-z0-9_-]{11}(\?[^#]*)?)$')
                  .hasMatch(link);
  return valid ? uri : null;
}

class ShoppingAffiliate {
  ShoppingAffiliate(this.data);
  final Map<String, dynamic> data;
  String get id => data['id'] as String;
  String get program => data['program'] as String;
  String get title => data['title'] as String;
  String get specification => data['specification'] as String? ?? '';
  bool get isSuggestedMatch => data['_suggested_match'] == true;
  String get matchedIngredient => data['_matched_ingredient'] as String? ?? '';
  String? get imageUrl {
    final value = data['image_url'];
    if (value is! String || value.length > 2048) return null;
    final uri = Uri.tryParse(value);
    if (uri == null ||
        uri.scheme != 'https' ||
        uri.userInfo.isNotEmpty ||
        uri.hasPort ||
        !uri.host.toLowerCase().endsWith('coupangcdn.com')) {
      return null;
    }
    return value;
  }

  Uri? get uri => affiliateUri(program, data['link'] as String);
}
