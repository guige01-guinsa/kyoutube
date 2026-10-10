import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:k_youtube/core/localization/app_localizations.dart';
import 'package:k_youtube/core/theme/app_theme.dart';
import 'package:k_youtube/features/auth/application/auth_providers.dart';
import 'package:k_youtube/features/home/domain/korean_classics.dart';
import 'package:k_youtube/features/home/presentation/classic_recipe_widgets.dart';
import 'package:k_youtube/features/home/presentation/home_page.dart';
import 'package:k_youtube/features/recipes/presentation/youtube_recipe_enrichment_page.dart';

void main() {
  testWidgets('home play control opens the original video for a guest',
      (tester) async {
    Uri? opened;
    await tester.pumpWidget(ProviderScope(overrides: [
      authUserProvider.overrideWith((_) => Stream.value(null)),
      classicUrlLauncherProvider.overrideWithValue((uri) async {
        opened = uri;
        return true;
      }),
    ], child: MaterialApp(theme: AppTheme.light, home: const HomePage())));
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
        find.byKey(const Key('classic-play-bibimbap')), 250,
        scrollable: find.byType(Scrollable).first);
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('classic-play-bibimbap')));
    await tester.pumpAndSettle();
    expect(opened.toString(), koreanClassics.first.videoFor('ko').videoUrl);
    expect(find.byType(ClassicRecipePage), findsNothing);
  });

  test('fifteen dishes have distinct curated video sources', () {
    expect(koreanClassics.length, 15);
    expect(koreanClassics.map((r) => r.id).toSet().length, 15);
    expect(
        koreanClassics.map((r) => r.videoFor('ko').videoId).toSet().length, 15);
    for (final recipe in koreanClassics) {
      for (final language in ['ko', 'en']) {
        final video = recipe.videoFor(language);
        expect(video.videoId, matches(RegExp(r'^[a-zA-Z0-9_-]{11}$')));
        expect(Uri.parse(video.videoUrl).host, 'www.youtube.com');
        expect(video.thumbnailUrl, contains(video.videoId));
        expect(video.languageCode, isNotEmpty);
        expect(video.creator, isNotEmpty);
        final draft = classicDraftRecipe(recipe, language);
        expect(draft.youtubeUrl, video.videoUrl);
        expect(draft.imageUrl, video.thumbnailUrl);
        expect(draft.title, language == 'en' ? recipe.name.en : recipe.name.ko);
        expect(draft.ingredients, isEmpty);
        expect(draft.steps, isEmpty);
      }
      expect(recipe.videoFor('ko').creator, isNot('백종원'));
      expect(recipe.videoFor('en').creator, isNot('백종원'));
      expect(classicCategories.containsKey(recipe.category), isTrue);
      expect(recipe.focus.ko, isNotEmpty);
      expect(recipe.focus.en, isNotEmpty);
    }
  });

  for (final language in ['ko', 'en']) {
    testWidgets('$language guest opens exact video and AI action goes to login',
        (tester) async {
      Uri? opened;
      final recipe = koreanClassics.first;
      final router = GoRouter(routes: [
        GoRoute(
            path: '/', builder: (_, __) => ClassicRecipePage(recipe: recipe)),
        GoRoute(
            path: '/login',
            builder: (_, __) => const Scaffold(body: Text('LOGIN'))),
      ]);
      addTearDown(router.dispose);
      await tester.pumpWidget(ProviderScope(
          overrides: [
            authUserProvider.overrideWith((_) => Stream.value(null)),
            classicUrlLauncherProvider.overrideWithValue((uri) async {
              opened = uri;
              return true;
            }),
          ],
          child: MaterialApp.router(
            theme: AppTheme.light,
            routerConfig: router,
            locale: Locale(language),
            supportedLocales: AppLocalizations.supportedLocales,
            localizationsDelegates: const [
              AppLocalizations.delegate,
              GlobalMaterialLocalizations.delegate,
              GlobalWidgetsLocalizations.delegate,
              GlobalCupertinoLocalizations.delegate
            ],
          )));
      await tester.pumpAndSettle();
      await tester.scrollUntilVisible(
          find.byKey(const Key('classic-watch')), 250);
      await tester.tap(find.byKey(const Key('classic-watch')));
      await tester.pumpAndSettle();
      expect(opened.toString(), recipe.videoFor(language).videoUrl);
      expect(find.byType(YoutubeRecipeEnrichmentPage), findsNothing);
      await tester.scrollUntilVisible(
          find.byKey(const Key('classic-draft')), 250);
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('classic-draft')));
      await tester.pumpAndSettle();
      expect(find.text('LOGIN'), findsOneWidget);
    });

    testWidgets('$language 320px large text keeps all fifteen dishes reachable',
        (tester) async {
      tester.view.physicalSize = const Size(320, 740);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(ProviderScope(
          overrides: [
            authUserProvider.overrideWith((_) => Stream.value(null)),
          ],
          child: MaterialApp(
            locale: Locale(language),
            theme: AppTheme.light,
            supportedLocales: AppLocalizations.supportedLocales,
            localizationsDelegates: const [
              AppLocalizations.delegate,
              GlobalMaterialLocalizations.delegate,
              GlobalWidgetsLocalizations.delegate,
              GlobalCupertinoLocalizations.delegate
            ],
            builder: (context, child) => MediaQuery(
                data: MediaQuery.of(context)
                    .copyWith(textScaler: const TextScaler.linear(2)),
                child: child!),
            home: const HomePage(),
          )));
      await tester.pumpAndSettle();
      for (final recipe in koreanClassics) {
        await tester.scrollUntilVisible(
            find.byKey(ValueKey('classic-card-${recipe.id}')), 300,
            scrollable: find.byType(Scrollable).first, maxScrolls: 80);
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
      }
      if (language == 'en') {
        final text = tester
            .widgetList<Text>(find.byType(Text))
            .map((w) => w.data ?? '')
            .join();
        expect(RegExp(r'[가-힣]').hasMatch(text), isFalse);
      }
    });
  }

  testWidgets(
      'failed external launch shows recovery and direct AI route stays gated',
      (tester) async {
    await tester.pumpWidget(ProviderScope(
        overrides: [
          authUserProvider.overrideWith((_) => Stream.value(null)),
          classicUrlLauncherProvider.overrideWithValue((_) async => false),
        ],
        child: MaterialApp(
            theme: AppTheme.light,
            home: ClassicDraftPage(recipe: koreanClassics.first))));
    await tester.pumpAndSettle();
    expect(find.byType(YoutubeRecipeEnrichmentPage), findsNothing);
    await tester.scrollUntilVisible(
        find.byKey(const Key('classic-watch')), 250);
    await tester.tap(find.byKey(const Key('classic-watch')));
    await tester.pumpAndSettle();
    expect(find.text(homeCopy['unavailable']!.ko), findsOneWidget);
  });
}
