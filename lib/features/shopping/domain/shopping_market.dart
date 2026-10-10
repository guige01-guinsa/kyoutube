import 'shopping_assistant.dart';

/// Country is an explicit shopping preference, independent of UI language.
/// Shopping-tab support: support.google.com/merchants/answer/160637 (2026-10).
const shoppingCountries = <String, String>{
  'KR': '대한민국',
  'US': '미국',
  'CA': '캐나다',
  'MX': '멕시코',
  'BR': '브라질',
  'AR': '아르헨티나',
  'CL': '칠레',
  'CO': '콜롬비아',
  'PE': '페루',
  'EC': '에콰도르',
  'UY': '우루과이',
  'PY': '파라과이',
  'CR': '코스타리카',
  'PA': '파나마',
  'GT': '과테말라',
  'DO': '도미니카 공화국',
  'BO': '볼리비아',
  'SV': '엘살바도르',
  'HN': '온두라스',
  'NI': '니카라과',
  'VE': '베네수엘라',
  'ES': '스페인',
  'JP': '일본',
  'GB': '영국',
  'FR': '프랑스',
  'DE': '독일',
  'AU': '호주',
  'NZ': '뉴질랜드',
  'OTHER': '기타 국가',
};

const _shoppingTabCountries = {
  'KR',
  'US',
  'CA',
  'MX',
  'BR',
  'AR',
  'CL',
  'CO',
  'ES',
  'JP',
  'GB',
  'FR',
  'DE',
  'AU',
  'NZ',
};

class ShoppingMarket {
  const ShoppingMarket({this.country = 'KR', this.language = 'en'});
  final String country, language;
  bool get isKorea => country == 'KR';
  bool get supportsShoppingTab => _shoppingTabCountries.contains(country);

  factory ShoppingMarket.fromJson(Map<String, dynamic> json) => ShoppingMarket(
        country: shoppingCountries.containsKey(json['country'])
            ? json['country'] as String
            : 'KR',
        language: const {'ko', 'en', 'es'}.contains(json['language'])
            ? json['language'] as String
            : 'en',
      );
  Map<String, String> toJson() => {'country': country, 'language': language};

  /// Only product terms and explicit region/language hints leave the app.
  /// Google may also use the shopper's own location and account preferences.
  Uri search(String ingredient,
          {String specification = '', bool general = false}) =>
      Uri.https('www.google.com', '/search', {
        'q': shoppingSearchQuery(ingredient, specification: specification),
        'hl': language,
        if (country != 'OTHER') 'gl': country.toLowerCase(),
        if (!general && supportsShoppingTab) 'tbm': 'shop',
      });
}

/// Exact aliases only. Never infer a cut, firmness, package mass, or substitute.
/// Unknown names retain the user's text and can be edited before searching.
const _ingredientSearchNames = <List<String>>[
  ['두부', 'tofu', 'tofu'],
  ['연두부', 'silken tofu', 'tofu sedoso'],
  ['돼지고기', 'pork', 'carne de cerdo'],
  ['소고기', 'beef', 'carne de res'],
  ['닭고기', 'chicken meat', 'carne de pollo'],
  ['김치', 'kimchi', 'kimchi'],
  ['대파', 'large green onion', 'cebolla verde'],
  ['양파', 'onion', 'cebolla'],
  ['마늘', 'garlic', 'ajo'],
  ['감자', 'potato', 'papa'],
  ['당근', 'carrot', 'zanahoria'],
  ['토마토', 'tomato', 'tomate'],
  ['쌀', 'rice', 'arroz'],
  ['달걀', 'eggs', 'huevos'],
  ['우유', 'milk', 'leche'],
  ['버터', 'butter', 'mantequilla'],
  ['소금', 'salt', 'sal'],
  ['설탕', 'sugar', 'azúcar'],
  ['간장', 'soy sauce', 'salsa de soja'],
  ['진간장', 'Korean jin soy sauce', 'salsa de soja coreana jin'],
  ['국간장', 'Korean soup soy sauce', 'salsa de soja coreana para sopa'],
  ['고추장', 'gochujang', 'gochujang'],
  ['된장', 'doenjang', 'doenjang'],
  ['참기름', 'sesame oil', 'aceite de sésamo'],
  ['식용유', 'cooking oil', 'aceite de cocina'],
  ['소면', 'Korean somyeon noodles', 'fideos coreanos somyeon'],
];

String ingredientSearchName(String original, String language) {
  final key = original.trim().toLowerCase();
  for (final names in _ingredientSearchNames) {
    if (names.any((name) => name.toLowerCase() == key) ||
        (key == '계란' && names.first == '달걀') ||
        (key == '국수소면' && names.first == '소면')) {
      return names[switch (language) { 'ko' => 0, 'es' => 2, _ => 1 }];
    }
  }
  return original.trim();
}
