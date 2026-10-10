import 'package:k_youtube/features/recipes/presentation/my_recipes_page.dart';
import 'package:k_youtube/features/recipes/application/recipe_image_service.dart';
import 'package:k_youtube/features/recipes/application/recipe_providers.dart';
import 'package:k_youtube/features/recipes/data/recipe_repository.dart';
import 'package:k_youtube/features/recipes/domain/recipe.dart';
import 'package:k_youtube/features/recipes/presentation/create_creator_recipe_page.dart';
import 'package:k_youtube/core/router/app_router.dart';
import 'dart:async';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:k_youtube/core/auth/oauth_callback_handler.dart';
import 'package:k_youtube/core/auth/oauth_redirect.dart';
import 'package:k_youtube/core/localization/app_localizations.dart';
import 'package:k_youtube/core/theme/app_theme.dart';
import 'package:k_youtube/features/auth/application/auth_providers.dart';
import 'package:k_youtube/features/workspace/application/workspace_navigation.dart';
import 'package:k_youtube/features/workspace/presentation/workspace_frame.dart';
import 'package:k_youtube/features/workspace/presentation/workspace_page.dart';
import '../chef/chef_workbench_test.dart' as chef;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));
  testWidgets(
      'successful recipe save closes the protected editor without discarding',
      (tester) async {
    final navigation = WorkspaceNavigation();
    final repository = _SaveRepository();
    final router = GoRouter(routes: [
      GoRoute(
          path: '/',
          builder: (context, _) => Scaffold(
              body: TextButton(
                  onPressed: () => context.push('/edit'),
                  child: const Text('OPEN EDITOR')))),
      GoRoute(
          path: '/edit',
          onExit: (_, __) => navigation.confirmLeave(),
          builder: (_, __) => CreateCreatorRecipePage(
              initialRecipe: Recipe(
                  id: 'draft',
                  title: 'Carrots',
                  ingredients: const ['Carrots 800 g'],
                  steps: const ['Roast.']))),
    ]);
    addTearDown(router.dispose);
    await tester.pumpWidget(ProviderScope(overrides: [
      workspaceNavigationProvider.overrideWithValue(navigation),
      activeAccountIdProvider.overrideWithValue(null),
      recipeRepositoryProvider.overrideWithValue(repository),
      recipeImageServiceProvider.overrideWithValue(_UnusedImageService()),
    ], child: MaterialApp.router(routerConfig: router)));
    await tester.tap(find.text('OPEN EDITOR'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(EditableText).first, 'Updated carrots');
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(find.text('레시피 저장'), 400,
        scrollable: find
            .byWidgetPredicate(
                (w) => w is Scrollable && w.axisDirection == AxisDirection.down)
            .first);
    await tester.pumpAndSettle();
    final saveButton = find.text('레시피 저장');
    for (var i = 0; i < 6 && saveButton.hitTestable().evaluate().isEmpty; i++) {
      await tester.drag(
          find
              .byWidgetPredicate((w) =>
                  w is Scrollable && w.axisDirection == AxisDirection.down)
              .first,
          const Offset(0, -160));
      await tester.pumpAndSettle();
    }
    expect(saveButton.hitTestable(), findsOneWidget);
    await tester.tap(saveButton);
    await tester.pumpAndSettle();
    expect(repository.savedTitle, 'Updated carrots');
    expect(find.text('OPEN EDITOR'), findsOneWidget);
    expect(find.text('저장하지 않고 나갈까요?'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  test('application router can construct every route', () {
    expect(AppRouter.router.configuration.routes, isNotEmpty);
  });
  test('web OAuth accepts only its deployment origin and callback path',
      () async {
    var exchanges = 0;
    final handler = OAuthCallbackHandler(
        webCallbackUri: Uri.parse('https://app.example.test/work/'),
        exchangeSessionFromUri: (_) async {
          exchanges++;
          return null;
        });
    for (final url in [
      'https://evil.test/work/?code=x',
      'https://app.example.test/other/?code=x',
      'http://app.example.test/work/?code=x',
      'io.supabase.kyoutube://login-callback/?code=x'
    ]) {
      expect((await handler.handle(Uri.parse(url))).outcome,
          OAuthCallbackOutcome.ignored);
    }
    final callback = Uri.parse('https://app.example.test/work/?code=ok');
    expect((await handler.handle(callback)).outcome,
        OAuthCallbackOutcome.exchanged);
    expect((await handler.handle(callback)).outcome,
        OAuthCallbackOutcome.duplicate);
    expect(exchanges, 1);
    expect(
        webOAuthRedirectUri(Uri.parse(
            'https://app.example.test/work/?redirect=evil#/chef/123')),
        'https://app.example.test/work/');
  });
  test('web OAuth permits a loopback development callback', () async {
    final handler = OAuthCallbackHandler(
        webCallbackUri: Uri.parse('http://127.0.0.1:8766/'),
        exchangeSessionFromUri: (_) async => null);
    expect(
        (await handler.handle(Uri.parse('http://127.0.0.1:8766/?code=ok')))
            .outcome,
        OAuthCallbackOutcome.exchanged);
    expect(
        (await handler.handle(Uri.parse('http://127.0.0.1:8767/?code=ok')))
            .outcome,
        OAuthCallbackOutcome.ignored);
  });
  test('navigation stops on cancellation and does not open duplicate prompts',
      () async {
    final navigation = WorkspaceNavigation();
    final pending = Completer<bool>();
    navigation.register('editor', () => pending.future);
    final first = navigation.confirmLeave();
    expect(await navigation.confirmLeave(), isFalse);
    pending.complete(false);
    expect(await first, isFalse);
    navigation.remove('editor');
    expect(await navigation.confirmLeave(), isTrue);
  });
  for (final lang in ['ko', 'en']) {
    for (final width in [390.0, 1440.0]) {
      testWidgets('$lang workspace fits width $width and navigates',
          (tester) async {
        tester.view.physicalSize = Size(width, 1000);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        final router = GoRouter(initialLocation: '/workspace', routes: [
          ShellRoute(
              builder: (context, state, child) =>
                  WorkspaceFrame(location: state.uri.path, child: child),
              routes: [
                GoRoute(
                    path: '/workspace',
                    builder: (_, __) => const WorkspacePage()),
                GoRoute(
                    path: '/my-recipes',
                    builder: (_, __) => const MyRecipesPage()),
                GoRoute(
                    path: '/login',
                    builder: (_, __) =>
                        const Scaffold(body: Text('LOGIN DESTINATION')))
              ])
        ]);
        addTearDown(router.dispose);
        await tester.pumpWidget(ProviderScope(
            overrides: [
              authUserProvider.overrideWith((ref) => Stream.value(null))
            ],
            child: MaterialApp.router(
                routerConfig: router,
                theme: AppTheme.light,
                locale: Locale(lang),
                supportedLocales: AppLocalizations.supportedLocales,
                localizationsDelegates: const [
                  AppLocalizations.delegate,
                  GlobalMaterialLocalizations.delegate,
                  GlobalWidgetsLocalizations.delegate,
                  GlobalCupertinoLocalizations.delegate
                ])));
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        expect(find.byType(WorkspaceScope), findsOneWidget);
        router.go('/my-recipes');
        await tester.pumpAndSettle();
        await tester.tap(find.text(lang == 'en' ? 'Sign in' : '로그인하기'));
        await tester.pumpAndSettle();
        expect(find.text('LOGIN DESTINATION'), findsOneWidget);
      });
    }
    testWidgets(
        '$lang desktop chef table edits quantity and saves shared calculation',
        (tester) async {
      tester.view.physicalSize = const Size(1440, 1000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final repo = chef.MemoryChefRepository(chef.example(lang));
      await chef.showChef(tester, lang, repo);
      expect(find.byType(DataTable), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.enterText(
          find.byKey(const ValueKey('chef-targetServings-1')), '20');
      await tester.pumpAndSettle();
      await tester.tap(find.text(lang == 'en' ? 'Save work' : '작업 저장').last);
      await tester.pumpAndSettle();
      expect(repo.document.targetServings, 20);
      expect(repo.document.ingredients.first.quantity! * repo.document.ratio!,
          4000);
      expect(tester.takeException(), isNull);
    });
  }
  testWidgets(
      'router preserves a dirty editor after cancel and releases guard after leaving',
      (tester) async {
    final navigation = WorkspaceNavigation();
    final router = GoRouter(initialLocation: '/edit', routes: [
      GoRoute(
          path: '/edit',
          onExit: (_, __) => navigation.confirmLeave(),
          builder: (context, _) => WorkspaceEditGuard(
              dirty: true,
              busy: false,
              confirmLeave: () => confirmWorkspaceDiscard(context),
              child: Scaffold(
                  body: TextButton(
                      onPressed: () => context.go('/next'),
                      child: const Text('NEXT'))))),
      GoRoute(
          path: '/next',
          builder: (_, __) => const Scaffold(body: Text('LEFT'))),
    ]);
    addTearDown(router.dispose);
    await tester.pumpWidget(ProviderScope(overrides: [
      workspaceNavigationProvider.overrideWithValue(navigation),
      activeAccountIdProvider.overrideWithValue(null)
    ], child: MaterialApp.router(routerConfig: router)));
    await tester.tap(find.text('NEXT'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('계속 편집'));
    await tester.pumpAndSettle();
    expect(find.text('NEXT'), findsOneWidget);
    await tester.tap(find.text('NEXT'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('나가기'));
    await tester.pumpAndSettle();
    expect(find.text('LEFT'), findsOneWidget);
    expect(await navigation.confirmLeave(), isTrue);
  });
}

class _SaveRepository implements RecipeRepository {
  String? savedTitle;
  @override
  Future<Recipe> createCreatorRecipe(
      {required String title,
      String? summary,
      required List<String> ingredients,
      required List<String> steps,
      String? tips,
      String? imagePath,
      String? youtubeUrl,
      Map<String, dynamic> contentStyles = const {}}) async {
    savedTitle = title;
    return Recipe(
        id: 'saved', title: title, ingredients: ingredients, steps: steps);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _UnusedImageService implements RecipeImageService {
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
