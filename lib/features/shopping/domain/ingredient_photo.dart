/// Representative ingredient photos, never photos of a particular sale offer.
/// Exact aliases prevent e.g. garlic sauce from getting a whole-garlic photo.
class IngredientPhoto {
  const IngredientPhoto(this.id, this.aliases);
  final String id;
  final List<String> aliases;
  String get asset => 'assets/ingredients/$id.jpg';

  /// Used when an ingredient does not yet have its own exact-match photo.
  static const fallbackAsset = 'assets/ingredients/ingredient-fallback.jpg';

  static const catalog = <IngredientPhoto>[
    IngredientPhoto('onion', ['양파', '깐양파', 'onion', 'onions', 'yellow onion']),
    IngredientPhoto('carrot', ['당근', 'carrot', 'carrots']),
    IngredientPhoto('minced-garlic', [
      '다진마늘',
      '간마늘',
      '마늘다진것',
      '마늘(다진것)',
      'minced garlic',
      'chopped garlic',
      'crushed garlic'
    ]),
    IngredientPhoto(
        'garlic', ['마늘', '통마늘', '깐마늘', '마늘쪽', 'garlic', 'garlic cloves']),
    IngredientPhoto('green-onion', [
      '대파',
      '다진대파',
      '송송썬대파',
      'green onion',
      'green onions',
      'scallion',
      'scallions',
      'spring onion'
    ]),
    IngredientPhoto('potato', ['감자', '깐감자', 'potato', 'potatoes']),
    IngredientPhoto('tomato', ['토마토', 'tomato', 'tomatoes']),
    IngredientPhoto(
        'tofu', ['두부', '부침두부', '찌개두부', '단단한두부', 'tofu', 'firm tofu']),
    IngredientPhoto('egg', ['달걀', '계란', '생란', 'egg', 'eggs']),
    IngredientPhoto('soy-sauce', [
      '간장',
      '진간장',
      '국간장',
      '양조간장',
      'soy sauce',
      'light soy sauce',
      'dark soy sauce'
    ]),
    IngredientPhoto(
        'pork', ['돼지고기', '돼지목살', '돼지고기목살', 'pork', 'pork shoulder']),
    IngredientPhoto(
        'chicken', ['닭가슴살', '생닭가슴살', 'chicken breast', 'chicken breasts']),
    IngredientPhoto('paste', ['고추장', '된장', '쌈장', '춘장']),
    IngredientPhoto('spices', ['고춧가루', '소금', '후추', '카레가루', '치킨스톡']),
    IngredientPhoto('oils',
        ['대두유', '식용유', '콩기름', '참기름', '들기름', '올리브유', '식초', '물엿', '올리고당', '맛술']),
    IngredientPhoto('leafy-greens', [
      '배추',
      '양배추',
      '애호박',
      '청양고추',
      '오이',
      '깻잎',
      '상추',
      '부추',
      '시금치',
      '콩나물',
      '숙주나물',
      '브로콜리',
      '파프리카'
    ]),
    IngredientPhoto('mushrooms', ['팽이버섯', '새송이버섯', '표고버섯', '생표고버섯']),
    IngredientPhoto('roots', ['무', '무우', '생강', '흙생강', '고구마']),
    IngredientPhoto('pork-cuts', ['돼지고기 앞다리살', '돼지고기 삼겹살', '돼지고기 목살']),
    IngredientPhoto('beef-cuts', ['소고기 국거리', '소고기 불고기용']),
    IngredientPhoto('chicken-cuts', ['닭고기 볶음탕용', '닭가슴살', '닭다리살']),
    IngredientPhoto('seafood', ['새우살', '냉동 새우', '오징어', '고등어', '동태']),
    IngredientPhoto(
        'shellfish-seaweed', ['바지락', '참바지락', '홍합', '건미역', '건다시마', '김밥용 김']),
    IngredientPhoto('dairy', ['우유', '버터', '모차렐라치즈', '생크림']),
    IngredientPhoto('grains', ['쌀', '밀가루', '부침가루', '튀김가루', '감자전분', '빵가루']),
  ];

  static String _key(String value) =>
      value.toLowerCase().replaceAll(RegExp(r'\s+'), '');

  static IngredientPhoto? find(String ingredient) {
    var name = _key(ingredient.trim());
    // Only modifiers that leave the identity/form of the pictured food intact.
    name = name.replaceFirst(RegExp(r'^(?:국내산|국산|유기농|무농약|신선한|손질한|손질)+'), '');
    for (final photo in catalog) {
      if (photo.aliases.any((alias) => _key(alias) == name)) return photo;
    }
    return null;
  }
}
