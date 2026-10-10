typedef HomeText = ({String ko, String en});

/// Editorial selections, not cached YouTube API results. Original sources are
/// recorded in docs/korean-classics.md. Never infer timings, ratings or yields.
class KoreanClassic {
  const KoreanClassic(this.id, this.name, this.category, this.focus,
      this.videoId, this.sourceSlug,
      {required this.koreanVideo});
  final String id;
  final HomeText name;
  final String category;
  final HomeText focus;
  final String videoId;
  final String sourceSlug;
  final ClassicVideo koreanVideo;
  ClassicVideo videoFor(String languageCode) => languageCode != 'ko'
      ? ClassicVideo(videoId, 'Maangchi', 'en',
          recipeUrl: 'https://www.maangchi.com/recipe/$sourceSlug')
      : koreanVideo;
}

/// A source and its language travel together through display, playback and AI.
class ClassicVideo {
  const ClassicVideo(this.videoId, this.creator, this.languageCode,
      {this.recipeUrl});
  final String videoId;
  final String creator;
  final String languageCode;
  final String? recipeUrl;
  String get videoUrl => 'https://www.youtube.com/watch?v=$videoId';
  String get thumbnailUrl => 'https://i.ytimg.com/vi/$videoId/hqdefault.jpg';
}

const homeCopy = <String, HomeText>{
  'eyebrow': (
    ko: 'RECIPE SCOUT · 한식 컬렉션',
    en: 'RECIPE SCOUT · KOREAN COLLECTION'
  ),
  'title': (ko: '한식의 기본,\n나만의 깊이로.', en: 'Korean classics.\nYour own craft.'),
  'intro': (
    ko: '대표 한식 15선, 원본 영상으로 만나는 조리의 디테일.',
    en: 'Fifteen Korean classics. Discover the details in the original videos.'
  ),
  'collection': (ko: '대표 한식 15선', en: '15 Korean classics'),
  'all': (ko: '전체 보기', en: 'View all'),
  'guest': (ko: '로그인 없이 영상 감상', en: 'Explore videos without signing in'),
  'watch': (ko: 'YouTube 원본 보기', en: 'Watch on YouTube'),
  'source': (ko: '제작자의 레시피 보기', en: 'Read the creator’s recipe'),
  'focus': (ko: '살펴볼 조리 포인트', en: 'What to look for'),
  'draft': (ko: '이 영상으로 AI 초안 만들기', en: 'Create an AI draft from this video'),
  'signInDraft': (ko: '로그인하고 AI 초안 만들기', en: 'Sign in to create an AI draft'),
  'draftNote': (
    ko: 'AI 초안은 원본과 비교해 재료·분량·순서를 확인한 뒤 나만의 레시피로 완성하세요.',
    en: 'Check ingredients, quantities and steps against the source before making an AI draft your own.'
  ),
  'tools': (ko: '나의 주방에 맞게', en: 'Make it work in your kitchen'),
  'toolsIntro': (
    ko: '새로운 영상을 찾고, 재료를 활용하고, 나만의 방식을 기록하세요.',
    en: 'Find a video, use what you have, and develop your own approach.'
  ),
  'curation': (
    ko: '레시피 스카우트 선정 · 한국어 조리 영상',
    en: 'Selected by Recipe Scout · English cooking videos'
  ),
  'unavailable': (
    ko: '영상을 열지 못했습니다. 인터넷 연결과 YouTube 앱을 확인한 뒤 다시 시도해 주세요.',
    en: 'Could not open the video. Check your internet connection and YouTube app, then try again.'
  ),
  'videoLanguage': (ko: '추천 영상', en: 'Featured video'),
  'imageFallback': (ko: '미리보기를 불러오지 못했어요', en: 'Preview unavailable'),
};

const classicCategories = <String, HomeText>{
  'all': (ko: '전체', en: 'All'),
  'rice': (ko: '밥·면', en: 'Rice & noodles'),
  'soup': (ko: '국·찌개', en: 'Soups & stews'),
  'meat': (ko: '고기 요리', en: 'Meat'),
  'snack': (ko: '분식·전', en: 'Snacks & pancakes'),
};

const koreanClassics = <KoreanClassic>[
  KoreanClassic(
      'bibimbap',
      (ko: '비빔밥', en: 'Bibimbap'),
      'rice',
      (
        ko: '재료별 익힘과 고명 배치',
        en: 'Cooking each component and arranging the bowl'
      ),
      '6QQ67F8y2b8',
      'bibimbap',
      koreanVideo: ClassicVideo('p0JEtaprf2c', '하루한끼', 'ko')),
  KoreanClassic(
      'bulgogi',
      (ko: '불고기', en: 'Bulgogi'),
      'meat',
      (ko: '양념의 균형과 고기 굽기', en: 'Balancing the marinade and grilling the beef'),
      '3qBjL_HGvco',
      'bulgogi',
      koreanVideo: ClassicVideo('3qBjL_HGvco', 'Maangchi', 'en',
          recipeUrl: 'https://www.maangchi.com/recipe/bulgogi')),
  KoreanClassic(
      'kimchi-jjigae',
      (ko: '김치찌개', en: 'Kimchi jjigae'),
      'soup',
      (ko: '김치와 육수가 만드는 국물의 깊이', en: 'Building a broth with kimchi and stock'),
      'rJgb92JWMCE',
      'kimchi-jjigae',
      koreanVideo: ClassicVideo('rJgb92JWMCE', 'Maangchi', 'en',
          recipeUrl: 'https://www.maangchi.com/recipe/kimchi-jjigae')),
  KoreanClassic(
      'doenjang-jjigae',
      (ko: '된장찌개', en: 'Doenjang jjigae'),
      'soup',
      (
        ko: '된장 풀기와 재료를 넣는 순서',
        en: 'Incorporating soybean paste and layering ingredients'
      ),
      'Slj_fM1jQVo',
      'doenjang-jjigae',
      koreanVideo: ClassicVideo('Slj_fM1jQVo', 'Maangchi', 'en',
          recipeUrl: 'https://www.maangchi.com/recipe/doenjang-jjigae')),
  KoreanClassic(
      'japchae',
      (ko: '잡채', en: 'Japchae'),
      'rice',
      (
        ko: '당면의 식감과 채소의 수분 조절',
        en: 'Noodle texture and moisture in the vegetables'
      ),
      'i1djfV9uigc',
      'japchae',
      koreanVideo: ClassicVideo('i1djfV9uigc', 'Maangchi', 'en',
          recipeUrl: 'https://www.maangchi.com/recipe/japchae')),
  KoreanClassic(
      'tteokbokki',
      (ko: '떡볶이', en: 'Tteokbokki'),
      'snack',
      (ko: '떡의 익힘과 소스 농도', en: 'Cooking the rice cakes and reducing the sauce'),
      'TA3Uo3a9674',
      'tteokbokki',
      koreanVideo: ClassicVideo('TA3Uo3a9674', 'Maangchi', 'en',
          recipeUrl: 'https://www.maangchi.com/recipe/tteokbokki')),
  KoreanClassic(
      'samgyetang',
      (ko: '삼계탕', en: 'Samgyetang'),
      'soup',
      (
        ko: '닭 속 채우기와 국물 끓이기',
        en: 'Stuffing the chicken and simmering the broth'
      ),
      'JUmFtHqwrnk',
      'samgyetang',
      koreanVideo: ClassicVideo('zuuhl1MKWss', '여의도 육퇴클럽', 'ko')),
  KoreanClassic(
      'galbi-jjim',
      (ko: '갈비찜', en: 'Galbi jjim'),
      'meat',
      (
        ko: '갈비 손질과 양념 졸이기',
        en: 'Preparing the ribs and reducing the braising liquid'
      ),
      'vtGzj6cUn7Q',
      'galbi-jjim',
      koreanVideo: ClassicVideo('vtGzj6cUn7Q', 'Maangchi', 'en',
          recipeUrl: 'https://www.maangchi.com/recipe/galbi-jjim')),
  KoreanClassic(
      'pajeon',
      (ko: '파전', en: 'Pajeon'),
      'snack',
      (
        ko: '반죽 농도와 뒤집는 타이밍',
        en: 'Batter consistency and when to turn the pancake'
      ),
      'RXcsHj1l-Pc',
      'pajeon',
      koreanVideo: ClassicVideo('RXcsHj1l-Pc', 'Maangchi', 'en',
          recipeUrl: 'https://www.maangchi.com/recipe/pajeon')),
  KoreanClassic(
      'gimbap',
      (ko: '김밥', en: 'Gimbap'),
      'rice',
      (
        ko: '밥 펴기와 속재료의 균형',
        en: 'Spreading the rice and balancing the fillings'
      ),
      'Y-Y9CXGRJPU',
      'gimbap',
      koreanVideo: ClassicVideo('Y-Y9CXGRJPU', 'Maangchi', 'en',
          recipeUrl: 'https://www.maangchi.com/recipe/gimbap')),
  KoreanClassic(
      'kimchi-bokkeumbap',
      (ko: '김치볶음밥', en: 'Kimchi fried rice'),
      'rice',
      (
        ko: '김치 볶기와 밥의 수분 조절',
        en: 'Frying the kimchi and managing moisture in the rice'
      ),
      'Lf44Fk7H24s',
      'kimchi-bokkeumbap',
      koreanVideo: ClassicVideo('Lf44Fk7H24s', 'Maangchi', 'en',
          recipeUrl: 'https://www.maangchi.com/recipe/kimchi-bokkeumbap')),
  KoreanClassic(
      'sundubu-jjigae',
      (ko: '순두부찌개', en: 'Sundubu jjigae'),
      'soup',
      (
        ko: '순두부의 질감과 국물의 균형',
        en: 'Keeping the tofu tender and balancing the broth'
      ),
      'BvZ9m3Bikuw',
      'sundubu-jjigae',
      koreanVideo: ClassicVideo('BvZ9m3Bikuw', 'Maangchi', 'en',
          recipeUrl: 'https://www.maangchi.com/recipe/sundubu-jjigae')),
  KoreanClassic(
      'jeyuk-bokkeum',
      (ko: '제육볶음', en: 'Spicy pork stir-fry'),
      'meat',
      (ko: '고기 익힘과 양념의 수분 조절', en: 'Cooking the pork and reducing the sauce'),
      '3oFCGKmzQX8',
      'dwaejigogi-bokkeum',
      koreanVideo: ClassicVideo('3oFCGKmzQX8', 'Maangchi', 'en',
          recipeUrl: 'https://www.maangchi.com/recipe/dwaejigogi-bokkeum')),
  KoreanClassic(
      'dakbokkeumtang',
      (ko: '닭볶음탕', en: 'Dakbokkeumtang'),
      'meat',
      (ko: '닭과 채소의 익힘 순서', en: 'Timing the chicken and vegetables'),
      'bDXL_g6kJ5U',
      'traditional-dakbokkeumtang',
      koreanVideo: ClassicVideo('bDXL_g6kJ5U', 'Maangchi', 'en',
          recipeUrl:
              'https://www.maangchi.com/recipe/traditional-dakbokkeumtang')),
  KoreanClassic(
      'miyeokguk',
      (ko: '미역국', en: 'Miyeokguk'),
      'soup',
      (ko: '미역 볶기와 국물 우려내기', en: 'Sautéing the seaweed and building the broth'),
      'znpwSp0Ro2I',
      'miyeokguk',
      koreanVideo: ClassicVideo('znpwSp0Ro2I', 'Maangchi', 'en',
          recipeUrl: 'https://www.maangchi.com/recipe/miyeokguk')),
];
