/// Stable food-category paths used by the affiliate catalog.
///
/// They follow the way food is browsed in major Korean marketplaces: a broad
/// food family followed by a practical shopping group. The database keeps the
/// human-readable path, so existing operator-entered categories remain valid.
class AffiliateFoodCategory {
  const AffiliateFoodCategory(this.path, this.aliases);

  final String path;
  final Set<String> aliases;

  static const unclassified = '기타·분류 확인';

  static const all = <AffiliateFoodCategory>[
    AffiliateFoodCategory('신선식품 > 채소', {
      '양파',
      '마늘',
      '감자',
      '당근',
      '배추',
      '무',
      '고추',
      '대파',
      '오이',
      '토마토',
      '상추',
      '시금치',
      '애호박',
      '브로콜리',
      '파프리카',
      'onion',
      'garlic',
      'carrot',
      'potato',
      'tomato',
      'cebolla',
      'ajo',
      'zanahoria',
      'papa',
      'tomate'
    }),
    AffiliateFoodCategory('신선식품 > 과일', {
      '사과',
      '배',
      '바나나',
      '딸기',
      '포도',
      '레몬',
      '오렌지',
      'apple',
      'banana',
      'strawberry',
      'grape',
      'manzana',
      'plátano',
      'fresa'
    }),
    AffiliateFoodCategory('신선식품 > 버섯·나물',
        {'버섯', '표고버섯', '팽이버섯', '느타리버섯', '콩나물', '숙주', 'mushroom', 'champiñón'}),
    AffiliateFoodCategory('축산·수산 > 소·돼지·양고기', {
      '소고기',
      '돼지고기',
      '삼겹살',
      '목살',
      '앞다리살',
      '갈비',
      'beef',
      'pork',
      'carne de res',
      'carne de cerdo'
    }),
    AffiliateFoodCategory('축산·수산 > 닭·오리·가금류',
        {'닭고기', '닭가슴살', '닭다리', '오리고기', 'chicken', 'duck', 'pollo'}),
    AffiliateFoodCategory('축산·수산 > 생선·해산물', {
      '고등어',
      '연어',
      '참치',
      '새우',
      '오징어',
      '조개',
      '굴',
      '게',
      'fish',
      'salmon',
      'shrimp',
      'tuna',
      'salmón',
      'camarón',
      'calamar'
    }),
    AffiliateFoodCategory('유제품·달걀 > 우유·치즈·달걀', {
      '우유',
      '치즈',
      '버터',
      '요거트',
      '달걀',
      '계란',
      'milk',
      'cheese',
      'butter',
      'yogurt',
      'egg',
      'leche',
      'queso',
      'mantequilla',
      'huevo'
    }),
    AffiliateFoodCategory('콩·두부·견과 > 두부·콩·견과', {
      '두부',
      '콩',
      '두유',
      '땅콩',
      '아몬드',
      '호두',
      'tofu',
      'bean',
      'soybean',
      'nut',
      'frijol',
      'almendra'
    }),
    AffiliateFoodCategory('쌀·잡곡·면·가루 > 쌀·잡곡',
        {'쌀', '현미', '보리', '귀리', '잡곡', 'rice', 'arroz', 'oats'}),
    AffiliateFoodCategory('쌀·잡곡·면·가루 > 면·파스타',
        {'소면', '국수', '라면', '우동', '파스타', '당면', 'noodles', 'pasta', 'fideos'}),
    AffiliateFoodCategory('쌀·잡곡·면·가루 > 밀가루·베이킹',
        {'밀가루', '부침가루', '빵가루', '이스트', '베이킹파우더', 'flour', 'harina', 'yeast'}),
    AffiliateFoodCategory('장류·소스·오일 > 장류·소스', {
      '간장',
      '진간장',
      '국간장',
      '고추장',
      '된장',
      '쌈장',
      '케첩',
      '마요네즈',
      'soy sauce',
      'salsa de soya',
      'salsa de soja'
    }),
    AffiliateFoodCategory('장류·소스·오일 > 식용유·식초', {
      '식용유',
      '올리브유',
      '참기름',
      '들기름',
      '식초',
      'oil',
      'olive oil',
      'aceite de oliva',
      'vinagre'
    }),
    AffiliateFoodCategory('가루·조미료 > 소금·설탕·향신료', {
      '소금',
      '설탕',
      '후추',
      '고춧가루',
      '카레가루',
      '다시다',
      '미원',
      'salt',
      'sugar',
      'pepper',
      'spice',
      'sal',
      'azúcar',
      'pimienta'
    }),
    AffiliateFoodCategory(
        '김치·반찬·간편식 > 김치·반찬', {'김치', '배추김치', '깍두기', '장아찌', '반찬', 'kimchi'}),
    AffiliateFoodCategory('김치·반찬·간편식 > 냉동·간편식',
        {'만두', '볶음밥', '즉석밥', '카레', '찌개', '냉동식품', 'frozen', 'dumpling'}),
    AffiliateFoodCategory('통조림·건식 > 통조림·건어물',
        {'참치캔', '옥수수캔', '통조림', '김', '미역', '다시마', '멸치', 'canned', 'seaweed'}),
    AffiliateFoodCategory('베이커리·잼·디저트', {
      '빵',
      '식빵',
      '잼',
      '꿀',
      '초콜릿',
      '쿠키',
      'bread',
      'jam',
      'honey',
      'chocolate'
    }),
    AffiliateFoodCategory('음료·차·커피',
        {'물', '주스', '커피', '차', '탄산수', '음료', 'water', 'juice', 'coffee', 'tea'}),
    AffiliateFoodCategory(
        '건강·특수식', {'단백질파우더', '프로틴', '영양식', '저당', '글루텐프리', 'protein powder'}),
  ];

  static String infer(String ingredient) {
    final key = ingredient.trim().toLowerCase();
    if (key.isEmpty) return unclassified;
    for (final category in all) {
      if (category.aliases.contains(key)) return category.path;
    }
    return unclassified;
  }
}
