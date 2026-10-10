import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:k_youtube/core/localization/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:k_youtube/features/workspace/presentation/workspace_page.dart';
import 'package:k_youtube/features/workspace/presentation/workspace_preferences_page.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:k_youtube/core/theme/app_theme.dart';
import 'package:k_youtube/core/widgets/centered_state_view.dart';
import 'package:k_youtube/features/auth/application/auth_providers.dart';
import 'package:k_youtube/features/home/presentation/home_page.dart';
import 'package:k_youtube/features/chef/presentation/chef_hub_page.dart';
import 'package:k_youtube/features/shopping/presentation/shopping_hub_page.dart';
import 'package:k_youtube/features/shopping/domain/shopping_navigation.dart';
import 'package:k_youtube/features/recipes/application/recipe_providers.dart';
import 'package:k_youtube/features/recipes/domain/recipe.dart';
import 'package:k_youtube/features/recipes/presentation/my_recipes_page.dart';
import 'package:k_youtube/features/recipes/presentation/widgets/recipe_reading_sections.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));
  testWidgets('top-level destinations remain available to guests',
      (tester) async {
    final router = GoRouter(routes: <RouteBase>[
      GoRoute(path: '/', builder: (_, __) => const HomePage()),
      GoRoute(
          path: '/youtube',
          builder: (_, __) => const Scaffold(body: Text('영상 검색 화면'))),
      GoRoute(path: '/my-recipes', builder: (_, __) => const MyRecipesPage()),
      GoRoute(path: '/chef', builder: (_, __) => const ChefHubPage()),
      GoRoute(
          path: '/workspace-settings',
          builder: (_, __) => const WorkspacePreferencesPage()),
      GoRoute(path: '/workspace', builder: (_, __) => const WorkspacePage()),
      GoRoute(
          path: '/workspace-menu',
          builder: (_, __) => const WorkspaceMenuPage()),
      GoRoute(
          path: '/shopping',
          builder: (_, __) =>
              const ShoppingHubPage(stage: ShoppingStage.prepare)),
    ]);
    addTearDown(router.dispose);
    await tester.pumpWidget(ProviderScope(
      overrides: <Override>[
        authUserProvider.overrideWith((_) => Stream.value(null)),
        publicRecipesProvider.overrideWith((_, __) async => <Recipe>[]),
      ],
      child: MaterialApp.router(
          locale: const Locale('ko'),
          supportedLocales: AppLocalizations.supportedLocales,
          localizationsDelegates: const [
            AppLocalizations.delegate,
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate
          ],
          theme: AppTheme.light,
          routerConfig: router),
    ));
    await tester.pumpAndSettle();
    await tester.tap(find.text('레시피 보관함'));
    await tester.pumpAndSettle();
    expect(find.text('개인 레시피'), findsWidgets);
    expect(find.text('로그인하기'), findsOneWidget);
    await tester.tap(find.text('장보기'));
    await tester.pumpAndSettle();
    expect(find.text('로그인하고 장보기'), findsOneWidget);
    await tester.tap(find.text('더보기'));
    await tester.pumpAndSettle();
    expect(find.text('레시피 개발'), findsNothing);
    await tester.scrollUntilVisible(find.text('전문·공급업체 기능 설정'), 180);
    await Scrollable.ensureVisible(tester.element(find.text('전문·공급업체 기능 설정')),
        alignment: .5);
    await tester.pumpAndSettle();
    await tester.tap(find.text('전문·공급업체 기능 설정'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('purpose-professional')));
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
        find.byKey(const Key('save-workspace-purpose')), 200);
    await tester.tap(find.byKey(const Key('save-workspace-purpose')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('더보기'));
    await tester.pumpAndSettle();
    expect(router.routeInformationProvider.value.uri.path, '/workspace-menu');
    router.go('/');
    await tester.pumpAndSettle();
    expect(find.text('레시피 스카우트'), findsOneWidget);
    expect(router.canPop(), isFalse);
    await tester.scrollUntilVisible(
        find.byKey(const Key('video-recipe-entry')), 150,
        scrollable: find.byType(Scrollable).first);
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('video-recipe-entry')));
    await tester.pumpAndSettle();
    expect(find.text('영상 검색 화면'), findsOneWidget);
  });

  testWidgets('curated home works without public search or authentication',
      (tester) async {
    var publicCalls = 0;
    await tester.pumpWidget(ProviderScope(
      overrides: [
        authUserProvider.overrideWith((_) => Stream.value(null)),
        publicRecipesProvider.overrideWith((_, __) {
          publicCalls++;
          throw StateError('Public search is unavailable');
        }),
      ],
      child: MaterialApp(theme: AppTheme.light, home: const HomePage()),
    ));
    await tester.pumpAndSettle();
    expect(find.byType(TextField), findsOneWidget);
    await tester.ensureVisible(find.byKey(const Key('classic-filter-meat')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('classic-filter-meat')));
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
        find.byKey(const Key('classic-card-galbi-jjim')), 250,
        scrollable: find.byType(Scrollable).first);
    expect(find.byKey(const Key('classic-card-galbi-jjim')), findsOneWidget);
    expect(find.byKey(const Key('classic-card-bibimbap')), findsNothing);
    expect(publicCalls, 0);
    expect(tester.takeException(), isNull);
  });

  testWidgets('reading steps toggle and reset only when the content changes',
      (tester) async {
    Widget page(List<String> steps) => MaterialApp(
        theme: AppTheme.light,
        home: Scaffold(
            body: SingleChildScrollView(
                child: RecipeStepsSection(steps: steps))));
    await tester.pumpWidget(page(<String>['재료를 씻어요.', '약한 불에서 익혀요.']));
    await tester.tap(find.byKey(const ValueKey('recipe-step-0')));
    await tester.pump();
    expect(find.text('1 / 2단계 완료'), findsOneWidget);
    await tester.pumpWidget(page(<String>['재료를 씻어요.', '약한 불에서 익혀요.']));
    expect(find.text('1 / 2단계 완료'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('recipe-step-0')));
    await tester.pump();
    expect(find.text('0 / 2단계 완료'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('recipe-step-1')));
    await tester.pumpWidget(page(<String>['다른 레시피를 준비해요.']));
    expect(find.text('0 / 1단계 완료'), findsOneWidget);
  });

  testWidgets(
      'small screens and large text keep discovery and states reachable',
      (tester) async {
    tester.view.physicalSize = const Size(320, 640);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    Widget largeText(Widget child) => MaterialApp(
          theme: AppTheme.light,
          builder: (_, page) => MediaQuery(
              data: const MediaQueryData(
                  size: Size(320, 640), textScaler: TextScaler.linear(2)),
              child: page!),
          home: child,
        );
    await tester.pumpWidget(ProviderScope(
      overrides: <Override>[
        authUserProvider.overrideWith((_) => Stream.value(null)),
        publicRecipesProvider.overrideWith((_, __) async => <Recipe>[]),
      ],
      child: largeText(const HomePage()),
    ));
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
        find.byKey(const Key('video-recipe-entry')), 200,
        scrollable: find.byType(Scrollable).first);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(largeText(Scaffold(
        body: SizedBox(
            height: 250,
            child: CenteredStateView(
                icon: Icons.search,
                title: '다시 찾을 수 있어요',
                message: '글자를 크게 설정해도 다음 행동을 선택할 수 있어요.',
                actionLabel: '다시 시도',
                onAction: () {})))));
    await tester.scrollUntilVisible(find.text('다시 시도'), 150);
    expect(tester.takeException(), isNull);
  });
}
