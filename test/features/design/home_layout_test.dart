import 'dart:io';
import 'dart:convert';
import 'package:flutter/services.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:k_youtube/core/localization/app_localizations.dart';
import 'package:k_youtube/core/theme/app_theme.dart';
import 'package:k_youtube/features/auth/application/auth_providers.dart';
import 'package:k_youtube/features/home/presentation/home_page.dart';
import 'package:k_youtube/features/home/domain/korean_classics.dart';
import 'package:k_youtube/features/home/presentation/classic_recipe_widgets.dart';
import 'package:k_youtube/features/workspace/presentation/workspace_frame.dart';
import 'package:k_youtube/features/workspace/presentation/workspace_menu.dart';

void main() {
  const capture = bool.fromEnvironment('HOME_DESIGN_CAPTURE');
  const captureDirectory = bool.fromEnvironment('DESIGN_COMPLETE_CAPTURE')
      ? '.artifacts/design-complete'
      : '.artifacts/design-refresh';
  setUp(() => SharedPreferences.setMockInitialValues(capture
      ? {
          'scout_workspace_guest_v1':
              '{"schema":1,"active":"personal","enabled":["personal"]}',
        }
      : {}));
  final fixtureImages = <String, Uint8List>{};
  final emptyImage = base64Decode(
      'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVQIHWP4z8DwHwAFgAI/ScLbtAAAAABJRU5ErkJggg==');
  if (capture) {
    setUpAll(() async {
      // Offline layout fixtures show each dish, not a live source thumbnail.
      for (final recipe in koreanClassics) {
        final image = File('.artifacts/${recipe.videoId}.jpg');
        if (await image.exists()) {
          final bytes = await image.readAsBytes();
          fixtureImages[recipe.videoFor('ko').thumbnailUrl] = bytes;
          fixtureImages[recipe.videoFor('en').thumbnailUrl] = bytes;
        }
      }
      for (final family in [
        'Ahem',
        'Roboto',
        'RecipeScoutKR',
        'MaterialIcons'
      ]) {
        final path = family == 'MaterialIcons'
            ? '.fvm/flutter_sdk/bin/cache/artifacts/material_fonts/MaterialIcons-Regular.otf'
            : 'assets/fonts/NanumGothic-Regular.ttf';
        final loader = FontLoader(family);
        loader.addFont(
            Future.value(ByteData.sublistView(await File(path).readAsBytes())));
        await loader.load();
      }
      await Directory(captureDirectory).create(recursive: true);
    });
  }

  Future<void> pumpHome(WidgetTester tester,
      {Size size = const Size(390, 844),
      double textScale = 1,
      bool framed = false,
      String language = 'ko',
      GoRouter? router}) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    Widget scale(BuildContext context, Widget? child) => MediaQuery(
        data: MediaQuery.of(context)
            .copyWith(textScaler: TextScaler.linear(textScale)),
        child: child!);
    const delegates = <LocalizationsDelegate<dynamic>>[
      AppLocalizations.delegate,
      GlobalMaterialLocalizations.delegate,
      GlobalWidgetsLocalizations.delegate,
      GlobalCupertinoLocalizations.delegate,
    ];
    await tester.pumpWidget(ProviderScope(
      overrides: [
        authUserProvider.overrideWith((_) => Stream.value(null)),
        if (capture)
          classicImageProvider.overrideWith(
              (_, url) => MemoryImage(fixtureImages[url] ?? emptyImage)),
      ],
      child: router == null
          ? MaterialApp(
              debugShowCheckedModeBanner: false,
              theme: AppTheme.light,
              locale: Locale(language),
              localizationsDelegates: delegates,
              supportedLocales: AppLocalizations.supportedLocales,
              builder: scale,
              home: framed
                  ? const WorkspaceScope(child: HomePage())
                  : const HomePage())
          : MaterialApp.router(
              debugShowCheckedModeBanner: false,
              theme: AppTheme.light,
              locale: Locale(language),
              localizationsDelegates: delegates,
              supportedLocales: AppLocalizations.supportedLocales,
              builder: scale,
              routerConfig: router),
    ));
    await tester.pumpAndSettle();
  }

  testWidgets('search and recipe actions precede the curated collection',
      (tester) async {
    await pumpHome(tester);
    final search = find.byKey(const Key('home-recipe-search'));
    final video = find.byKey(const Key('video-recipe-entry'));
    final saved = find.byKey(const Key('saved-recipe-entry'));
    final collection = find.byKey(const Key('home-curated-heading'));
    expect(tester.getTopLeft(search).dy, lessThan(350));
    expect(tester.getBottomLeft(video).dy,
        lessThan(tester.getTopLeft(collection).dy));
    expect(tester.getBottomLeft(saved).dy,
        lessThan(tester.getTopLeft(collection).dy));
    expect(
        find.byKey(const Key('collection-save-destination')), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('desktop shell owns the role selector without a duplicate',
      (tester) async {
    await pumpHome(tester, size: const Size(1280, 900), framed: true);
    expect(find.byType(WorkspaceModeButton), findsNothing);
    expect(find.byKey(const Key('home-recipe-search')), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'search preserves query and saved recipes uses the existing route',
      (tester) async {
    String? searchQuery;
    final router = GoRouter(routes: [
      GoRoute(path: '/', builder: (_, __) => const HomePage()),
      GoRoute(
          path: '/search',
          builder: (_, state) {
            searchQuery = state.uri.queryParameters['q'];
            return const Scaffold(body: Text('SEARCH'));
          }),
      GoRoute(
          path: '/my-recipes',
          builder: (_, __) => const Scaffold(body: Text('SAVED'))),
    ]);
    addTearDown(router.dispose);
    await pumpHome(tester, router: router);
    await tester.enterText(
        find.byKey(const Key('home-recipe-search')), '  tofu soup  ');
    await tester.testTextInput.receiveAction(TextInputAction.search);
    await tester.pumpAndSettle();
    expect(searchQuery, 'tofu soup');
    expect(find.text('SEARCH'), findsOneWidget);
    router.go('/');
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('saved-recipe-entry')));
    await tester.pumpAndSettle();
    expect(find.text('SAVED'), findsOneWidget);
    expect(router.canPop(), isFalse);
  });

  testWidgets(
      'new hero actions open import and require sign-in before creating',
      (tester) async {
    final router = GoRouter(routes: [
      GoRoute(path: '/', builder: (_, __) => const HomePage()),
      GoRoute(
          path: '/youtube',
          builder: (_, __) => const Scaffold(body: Text('IMPORT'))),
      GoRoute(
          path: '/login',
          builder: (_, __) => const Scaffold(body: Text('SIGN IN'))),
      GoRoute(
          path: '/creator/new',
          builder: (_, __) => const Scaffold(body: Text('EDITOR'))),
    ]);
    addTearDown(router.dispose);
    await pumpHome(tester, router: router);
    await tester.ensureVisible(find.byKey(const Key('video-recipe-entry')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('video-recipe-entry')));
    await tester.pumpAndSettle();
    expect(find.text('IMPORT'), findsOneWidget);
    router.go('/');
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.byKey(const Key('home-create-recipe')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('home-create-recipe')));
    await tester.pumpAndSettle();
    expect(find.text('SIGN IN'), findsOneWidget);
    expect(find.text('EDITOR'), findsNothing);
  });

  for (final language in ['ko', 'en']) {
    testWidgets('$language narrow large text keeps actions and filters usable',
        (tester) async {
      await pumpHome(tester,
          size: const Size(320, 740), textScale: 2, language: language);
      for (final key in [
        'video-recipe-entry',
        'ingredient-recipe-entry',
        'saved-recipe-entry',
        'classic-filter-snack'
      ]) {
        await tester.ensureVisible(find.byKey(Key(key)));
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
      }
      await tester.tap(find.byKey(const Key('classic-filter-snack')));
      await tester.pumpAndSettle();
      await tester.scrollUntilVisible(
          find.byKey(const Key('classic-card-tteokbokki')), 200,
          scrollable: find.byType(Scrollable).first);
      expect(find.byKey(const Key('classic-card-tteokbokki')), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }
  if (capture) {
    for (final size in [const Size(390, 844), const Size(1440, 1000)]) {
      testWidgets('fixture home capture ${size.width.toInt()}', (tester) async {
        final router = GoRouter(routes: [
          GoRoute(
              path: '/',
              builder: (_, __) =>
                  const WorkspaceFrame(location: '/', child: HomePage())),
        ]);
        addTearDown(router.dispose);
        await pumpHome(tester, size: size, router: router);
        // Image decoding runs outside the fake test clock. Wait for the actual
        // local fixture before recording the first (mobile) frame.
        await tester.runAsync(() async {
          final context = tester.element(find.byType(HomePage));
          for (final bytes in fixtureImages.values) {
            await precacheImage(MemoryImage(bytes), context);
          }
        });
        await tester.pumpAndSettle();
        await expectLater(
            find.byType(MaterialApp),
            matchesGoldenFile(
                File('$captureDirectory/home-${size.width.toInt()}-ko.png')
                    .absolute
                    .uri));
        expect(tester.takeException(), isNull);
      });
    }
  }
}
