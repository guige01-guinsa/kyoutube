import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import 'ui_translations.dart';
import 'spanish_translation.dart';

typedef _DynamicTranslation = (RegExp, String Function(Match));

final RegExp _koreanTextPattern = RegExp(r'[가-힣]');
List<_DynamicTranslation>? _dynamicTranslationCache;
List<MapEntry<String, String>>? _translationFragmentCache;

/// UI translations are deliberately local and dependency-free. Korean is the
/// source language; Spanish uses a complete static catalog and reviewed overrides.
class AppLocalizations {
  const AppLocalizations(this.locale);

  final Locale locale;
  bool get isKorean => locale.languageCode == 'ko';
  bool get isSpanish => locale.languageCode == 'es';

  /// Compatibility for the older two-language presentation helpers. Those
  /// helpers use their English label for every non-Korean locale.
  bool get isEnglish => !isKorean;

  static const supportedLocales = <Locale>[
    Locale('ko'),
    Locale('en'),
    Locale.fromSubtags(languageCode: 'es', countryCode: '419'),
  ];
  static const delegate = _AppLocalizationsDelegate();

  static Locale resolveLocale(Locale? locale) => switch (locale?.languageCode) {
        'en' => const Locale('en'),
        'es' =>
          const Locale.fromSubtags(languageCode: 'es', countryCode: '419'),
        _ => const Locale('ko'),
      };

  static AppLocalizations of(BuildContext context) =>
      Localizations.of<AppLocalizations>(context, AppLocalizations) ??
      const AppLocalizations(Locale('ko'));

  String _text(String ko, String en, [String? es]) => isKorean
      ? ko
      : isSpanish
          ? (es ?? translateSpanish(en))
          : en;

  /// Resolve legacy bilingual copy through the same catalog as translated Text.
  String bilingual(String ko, String en) => isKorean ? ko : translate(en);

  String translate(String source) {
    if (isKorean) return source;
    final english = _translateToEnglish(source);
    if (!isSpanish) return english;
    return translateSpanish(english);
  }

  String _translateToEnglish(String source) {
    if (!_koreanTextPattern.hasMatch(source)) return source;
    final exact =
        koreanUiTranslations[source] ?? koreanUiTranslations[source.trim()];
    if (exact != null) return exact;

    final patterns = _dynamicTranslationCache ??= <_DynamicTranslation>[
      (RegExp(r'^(\d+)건을 복원했습니다\.$'), (m) => 'Restored ${m[1]} records.'),
      (
        RegExp(r'^(\d+)건을 보관했습니다\. 보관함에서 복원할 수 있습니다\.$'),
        (m) => 'Archived ${m[1]} records. Restore them from the archive.'
      ),
      (RegExp(r'^보관일: (.+)$'), (m) => 'Archived: ${m[1]}'),
      (RegExp(r'^선택 (\d+)건 복원$'), (m) => 'Restore ${m[1]} selected'),
      (RegExp(r'^선택 (\d+)건 보관$'), (m) => 'Archive ${m[1]} selected'),
      (
        RegExp(r'^재료 (\d+)개 · 확인 필요 (\d+)개$'),
        (m) => '${m[1]} ingredients · ${m[2]} need review'
      ),
      (
        RegExp(r'^(.+) · 재료·수량 정리 → 요청서 검토·승인 → 전달·입고 확인$'),
        (m) => '${m[1]} · Plan quantities → review requests → share and receive'
      ),
      (RegExp(r'^(.+)에서 가져오기$'), (m) => 'Copy from ${m[1]}'),
      (RegExp(r'^저장 위치: (.+)$'), (m) => 'Save to: ${m[1]}'),
      (
        RegExp(r'^수집한 내용은 먼저 (.+)에 저장하고 재료·조리법을 검토합니다\.$'),
        (m) =>
            'Save to ${m[1]} first, then review the ingredients and cooking steps.'
      ),
      (
        RegExp(r'^「(.+)」의 재료·조리법·팁을 검토 자료로 가져옵니다\.$'),
        (m) => 'Copy the ingredients, steps and tips of “${m[1]}” for review.'
      ),
      (RegExp(r'^(\d+)\. 구매 품명$'), (m) => '${m[1]}. Purchase item'),
      (RegExp(r'^검색 결과 (\d+)건$'), (m) => '${m[1]} matching requests'),
      (
        RegExp(r'^견적 대기 (\d+)품목 · 취소 (\d+)건$'),
        (m) => '${m[1]} unpriced items · ${m[2]} cancelled'
      ),
      (RegExp(r'^재료 (\d+)개$'), (m) => '${m[1]} ingredients'),
      (RegExp(r'^조리 (\d+)단계$'), (m) => '${m[1]} cooking steps'),
      (RegExp(r'^(\d+)단계$'), (m) => '${m[1]} steps'),
      (
        RegExp(r'^재료 (\d+)개 · (\d+)단계$'),
        (m) => '${m[1]} ingredients · ${m[2]} steps'
      ),
      (RegExp(r'^(\d+)인분$'), (m) => '${m[1]} servings'),
      (RegExp(r'^준비 (\d+)분$'), (m) => '${m[1]} min prep'),
      (RegExp(r'^조리 (\d+)분$'), (m) => '${m[1]} min cook'),
      (RegExp(r'^약 (\d+)분 남음$'), (m) => 'About ${m[1]} min left'),
      (RegExp(r'^(\d+)초$'), (m) => '${m[1]} sec'),
      (RegExp(r'^평점 (\d+)/5$'), (m) => 'Rating ${m[1]}/5'),
      (RegExp(r'^현재 단계 (\d+)/(\d+)$'), (m) => 'Current step ${m[1]}/${m[2]}'),
      (
        RegExp(r'^(\d+) / (\d+)단계 완료$'),
        (m) => '${m[1]} / ${m[2]} steps completed'
      ),
      (RegExp(r'^(\d+)/(\d+) 페이지$'), (m) => 'Page ${m[1]}/${m[2]}'),
      (
        RegExp(r'^전체 (\d+)개 중 (\d+)개 선택$'),
        (m) => '${m[2]} of ${m[1]} selected'
      ),
      (
        RegExp(r'^장보기 목록 만들기 · (\d+)개$'),
        (m) => 'Create shopping list · ${m[1]} items'
      ),
      (RegExp(r'^장보기 필요 (\d+)개$'), (m) => '${m[1]} items to buy'),
      (RegExp(r'^구매 완료 (\d+)개$'), (m) => '${m[1]} purchased'),
      (RegExp(r'^구매함 (\d+)개$'), (m) => '${m[1]} purchased'),
      (RegExp(r'^결정 필요 (\d+)개$'), (m) => '${m[1]} decisions needed'),
      (RegExp(r'^보류/구매 불가 (\d+)개$'), (m) => '${m[1]} skipped/unavailable'),
      (
        RegExp(r'^유통기한이 가까운 재료 (\d+)개$'),
        (m) => '${m[1]} ingredients expiring soon'
      ),
      (RegExp(r'^진행 중 (\d+)개$'), (m) => '${m[1]} active'),
      (RegExp(r'^완료 내역 (\d+)개$'), (m) => '${m[1]} completed'),
      (RegExp(r'^조리 완료 기록 (\d+)개$'), (m) => '${m[1]} cooking records'),
      (
        RegExp(r'^구매 (\d+)개 · 남은 재료 (\d+)개$'),
        (m) => '${m[1]} purchased · ${m[2]} remaining'
      ),
      (RegExp(r'^구매 (.+)$'), (m) => 'Buy ${m[1]}'),
      (RegExp(r'^검색 결과: (.+)$'), (m) => 'Search results: ${m[1]}'),
      (
        RegExp(r'^선택한 YouTube 영상 기반 레시피 · (.+)$'),
        (m) => 'Recipe based on the selected YouTube video · ${m[1]}'
      ),
      (
        RegExp(r'^YouTube 영상 기반으로 만든 임시 레시피입니다\.\n채널: (.+)$'),
        (m) => 'Draft recipe based on a YouTube video.\nChannel: ${m[1]}'
      ),
      (RegExp(r'^원문 · (.+)$'), (m) => 'Original · ${m[1]}'),
      (RegExp(r'^읽기 전용 원문 (.+)$'), (m) => 'Read-only source: ${m[1]}'),
      (RegExp(r'^읽기 전용 조리 원문 (.+)$'), (m) => 'Read-only direction: ${m[1]}'),
      (RegExp(r'^레시피 재료 (.+)$'), (m) => 'Recipe ingredient: ${m[1]}'),
      (RegExp(r'^조리 원문: (.+)$'), (m) => 'Original direction: ${m[1]}'),
      (RegExp(r'^환경: (.+)$'), (m) => 'Environment: ${m[1]}'),
      (RegExp(r'^현재 단계: (.+)$'), (m) => 'Current phase: ${m[1]}'),
      (RegExp(r'^최근 오류: (\d+)건$'), (m) => 'Recent errors: ${m[1]}'),
      (RegExp(r'^마지막 알림 제목: (.*)$'), (m) => 'Last notification title: ${m[1]}'),
      (RegExp(r'^마지막 알림 본문: (.*)$'), (m) => 'Last notification body: ${m[1]}'),
      (RegExp(r'^토큰: (.*)$'), (m) => 'Token: ${m[1]}'),
      (RegExp(r'^오류: (.*)$'), (m) => 'Error: ${m[1]}'),
      (RegExp(r'^권한 상태: (.+)$'), (m) => 'Permission status: ${m[1]}'),
      (RegExp(r'^진행 중 장보기 (\d+)개$'), (m) => '${m[1]} active shopping lists'),
      (RegExp(r'^· 건너뜀 (\d+)개$'), (m) => '· ${m[1]} skipped'),
      (RegExp(r'^· 구매하지 못함 (\d+)개$'), (m) => '· ${m[1]} unavailable'),
      (RegExp(r'^합산 수량 (.+)$'), (m) => 'Combined amount ${m[1]}'),
      (
        RegExp(r'^제목은 (\d+)자 이하로 입력해 주세요\.$'),
        (m) => 'Keep the title to ${m[1]} characters or fewer.'
      ),
      (
        RegExp(r'^비밀번호는 (\d+)자 이상 입력해 주세요\.$'),
        (m) => 'Enter at least ${m[1]} characters for the password.'
      ),
      (RegExp(r'^(.+) 구매 완료$'), (m) => '${m[1]} purchased'),
      (RegExp(r'^(.+) 구매 상태 변경$'), (m) => 'Change purchase status for ${m[1]}'),
      (
        RegExp(r'^(\d+)개의 쿠팡 제휴 상품이 있습니다\. 판매 규격을 비교해 선택해 주세요\.$'),
        (m) => '${m[1]} Coupang affiliate products are available. Compare package sizes and choose one.'
      ),
      (RegExp(r'^상품 (\d+)개 중 선택$'), (m) => 'Choose from ${m[1]} products'),
      (
        RegExp(r'^(.+) 재료 정보 수정$'),
        (m) => 'Edit ingredient details for ${m[1]}'
      ),
      (
        RegExp(r'^장보기 (\d+)개 · 구매할 재료 (\d+)개$'),
        (m) => '${m[1]} shopping lists · ${m[2]} items to buy'
      ),
      (
        RegExp(r'^구매함 (\d+)개 · 건너뜀 (\d+)개 · 구매하지 못함 (\d+)개$'),
        (m) => '${m[1]} purchased · ${m[2]} skipped · ${m[3]} unavailable'
      ),
      (
        RegExp(r'^자동 재생 \(단계당 (\d+)초\)$'),
        (m) => 'Auto advance (${m[1]} sec per step)'
      ),
      (
        RegExp(r'^(.+) · 이번 달 AI (\d+)회$'),
        (m) => '${m[1]} · ${m[2]} AI uses this month'
      ),
      (
        RegExp(r'^아직 결정하지 않은 재료가 (\d+)개 있습니다\.$'),
        (m) => '${m[1]} ingredients still need a decision.'
      ),
    ];
    for (final pattern in patterns) {
      final match = pattern.$1.firstMatch(source);
      if (match != null) return pattern.$2(match);
    }
    if (source.contains('\n')) {
      return source.split('\n').map(_translateToEnglish).join('\n');
    }
    var translated = source;
    final fragments = _translationFragmentCache ??=
        (koreanUiTranslations.entries.toList()
          ..sort((a, b) => b.key.length.compareTo(a.key.length)));
    for (final fragment in fragments) {
      if (translated.contains(fragment.key)) {
        translated = translated.replaceAll(fragment.key, fragment.value);
      }
    }
    if (translated != source) return translated;
    return source;
  }

  String get appName => _text('레시피 스카우트', 'Recipe Scout');
  String get more => _text('더보기', 'More');
  String get home => _text('홈', 'Home');
  String get myRecipes => _text('내 레시피', 'My recipes');
  String get shopping => _text('장보기', 'Shopping');
  String get welcome =>
      _text('오늘의 요리, 여기서 발견해요.', 'Discover what to cook today.');
  String get newMeal => _text('새로운 한 끼의 발견', 'Discover your next meal');
  String get saveRecipes => _text(
      '마음에 드는 요리를 나의 레시피로 모아보세요.', 'Save dishes you love to your recipes.');
  String get videoFromTable => _text('영상에서 식탁까지', 'From video to table');
  String get tastyDiscovery =>
      _text('맛있는 발견,\n나만의 레시피로.', 'Tasty discoveries,\nyour own recipes.');
  String get videoDescription => _text('좋아하는 요리 영상을 찾고\nAI 초안을 내 요리 노트로 완성하세요.',
      'Find a cooking video you love\nand turn its AI draft into your recipe note.');
  String get findVideoRecipe => _text('영상 레시피 찾기', 'Find video recipes');
  String get findWithIngredients => _text('있는 재료로 찾기', 'Search by ingredients');
  String get oneMinuteGuide => _text('사용자별 튜토리얼', 'Guided tutorials');
  String get firstRecipe => _text('첫 레시피를 찾아볼까요?', 'Find your first recipe?');
  String get searchOrVideo => _text('요리 이름으로 검색하거나 영상에서 시작해 보세요.',
      'Search by dish name or start with a video.');
  String get recipesLoadFailed =>
      _text('레시피를 불러오지 못했어요', 'Could not load recipes');
  String get checkConnection =>
      _text('연결 상태를 확인하고 다시 시도해 주세요.', 'Check your connection and try again.');
  String get retry => _text('다시 시도', 'Try again');
  String get loadingRecipes => _text('레시피 불러오는 중', 'Loading recipes');
  String get gettingStarted => _text('사용자별 튜토리얼', 'Guided tutorials');
  String get account => _text('계정 관리', 'Account');
  String get signIn => _text('로그인', 'Sign in');
  String get signOut => _text('로그아웃', 'Sign out');
  String get diagnostics => _text('개발 진단', 'Developer diagnostics');
}

class _AppLocalizationsDelegate
    extends LocalizationsDelegate<AppLocalizations> {
  const _AppLocalizationsDelegate();
  @override
  bool isSupported(Locale locale) => AppLocalizations.supportedLocales
      .any((item) => item.languageCode == locale.languageCode);
  @override
  Future<AppLocalizations> load(Locale locale) =>
      SynchronousFuture<AppLocalizations>(AppLocalizations(locale));
  @override
  bool shouldReload(_AppLocalizationsDelegate old) => false;
}
