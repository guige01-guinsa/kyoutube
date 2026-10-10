import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:k_youtube/features/workspace/presentation/workspace_menu.dart';
import 'package:k_youtube/features/workspace/domain/workspace_profile.dart';
import 'package:k_youtube/core/localization/app_localizations.dart';
import 'package:k_youtube/features/auth/application/auth_providers.dart';
import 'package:k_youtube/features/business/data/business_repository.dart';
import 'package:k_youtube/features/business/domain/business_workspace.dart';
import 'package:k_youtube/features/business/presentation/business_recipe_collection.dart';
import 'package:k_youtube/features/recipes/application/recipe_library_provider.dart';
import 'package:k_youtube/features/recipes/application/recipe_providers.dart';
import 'package:k_youtube/features/recipes/domain/recipe.dart';
import 'package:k_youtube/features/recipes/domain/recipe_library_name.dart';

final _account = StateProvider<String?>((ref) => 'cook');

class CollectionRepository implements BusinessRepository {
  bool writable = true;
  final List<(String, String)> copies = [];
  BusinessContext get business => BusinessContext(
      id: 'shop',
      name: '작은공간',
      owner: false,
      paid: true,
      approval: true,
      permissions: {'recipes.read', if (writable) 'recipes.write'});
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
  @override
  Future<BusinessContext> context(String id) async => business;
  @override
  Future<BusinessRecord> importRecipe(String workspace, String source) async {
    copies.add((workspace, source));
    return BusinessRecord(
        id: 'copied',
        workspace: workspace,
        kind: 'recipe',
        title: '검토할 국',
        data: {});
  }
}

Future<GoRouter> pumpCollection(WidgetTester tester, CollectionRepository repo,
    {String language = 'ko'}) async {
  tester.view.physicalSize = const Size(390, 1000);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  final router = GoRouter(initialLocation: '/collect', routes: [
    GoRoute(
        path: '/collect',
        builder: (_, __) =>
            BusinessRecipeCollectionPage(business: repo.business)),
    GoRoute(
        path: '/', builder: (_, __) => const Scaffold(body: Text('DISCOVERY'))),
    GoRoute(
        path: '/business-workspaces/shop/records/copied',
        builder: (_, __) => const Scaffold(body: Text('SHARED REVIEW COPY'))),
  ]);
  addTearDown(router.dispose);
  await tester.pumpWidget(ProviderScope(
      overrides: [
        activeAccountIdProvider.overrideWith((ref) => ref.watch(_account)),
        recipeOwnerNameProvider.overrideWithValue('홍길동'),
        businessRepositoryProvider.overrideWithValue(repo),
        creatorRecipesProvider.overrideWith((ref, query) async => [
              Recipe(
                  id: 'personal-1',
                  title: '검토할 국',
                  summary: '',
                  ingredients: ['무'],
                  steps: ['끓이기']),
            ]),
      ],
      child: MaterialApp.router(
          routerConfig: router,
          locale: Locale(language),
          supportedLocales: AppLocalizations.supportedLocales,
          localizationsDelegates: const [
            AppLocalizations.delegate,
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate
          ])));
  await tester.pumpAndSettle();
  return router;
}

Future<void> chooseRecipe(WidgetTester tester) async {
  await tester.tap(find.byKey(const Key('business-collect-import')));
  await tester.pumpAndSettle();
  await tester.tap(find.text('검토할 국'));
  await tester.pumpAndSettle();
}

void main() {
  test('search and public recipe routes stay in the collection destination',
      () {
    for (final mode in [WorkspaceMode.personal, WorkspaceMode.professional]) {
      for (final path in [
        '/',
        '/search',
        '/youtube',
        '/ingredient-search/results',
        '/classics/bibimbap',
        '/recipes/public'
      ]) {
        expect(workspaceSectionPath(path, mode), '/');
        expect(
            primaryWorkspaceLinks(
                    mode)[workspaceDestinationIndex(Uri.parse(path), mode)]
                .path,
            '/');
      }
      expect(workspaceSectionPath('/my-recipes', mode), '/my-recipes');
    }
  });

  test(
      'library names distinguish business, personal, missing and invalid metadata',
      () {
    expect(
        recipeOwnerName({'display_name': '  ', 'full_name': ' 홍길동 '}), '홍길동');
    expect(
        recipeOwnerName({'display_name': 12, 'email': 'private@example.com'}),
        isNull);
    expect(recipeLibraryName(owner: '홍길동'), '홍길동님 레시피');
    expect(recipeLibraryName(owner: '작은공간', business: true), '작은공간 레시피');
    expect(recipeLibraryName(), '개인 레시피');
    expect(recipeLibraryName(english: true), 'Personal recipes');
  });

  testWidgets('read-only staff can discover but cannot copy to a business',
      (tester) async {
    final repo = CollectionRepository()..writable = false;
    await pumpCollection(tester, repo);
    expect(find.byKey(const Key('business-collect-import')), findsNothing);
    await tester.tap(find.byKey(const Key('business-collect-search')));
    await tester.pumpAndSettle();
    expect(find.text('DISCOVERY'), findsOneWidget);
    expect(repo.copies, isEmpty);
  });

  testWidgets(
      'copy requires confirmation of destination and preserves private source',
      (tester) async {
    final repo = CollectionRepository();
    await pumpCollection(tester, repo);
    await chooseRecipe(tester);
    expect(find.text('작은공간 레시피'), findsWidgets);
    expect(repo.copies, isEmpty);
    await tester.tap(find.text('취소'));
    await tester.pumpAndSettle();
    expect(repo.copies, isEmpty);
    await chooseRecipe(tester);
    await tester.tap(find.byKey(const Key('confirm-business-recipe-copy')));
    await tester.pumpAndSettle();
    expect(repo.copies, [('shop', 'personal-1')]);
    expect(find.text('SHARED REVIEW COPY'), findsOneWidget);
  });

  testWidgets('revoked write permission is rechecked before copying',
      (tester) async {
    final repo = CollectionRepository();
    await pumpCollection(tester, repo);
    await chooseRecipe(tester);
    repo.writable = false;
    await tester.tap(find.byKey(const Key('confirm-business-recipe-copy')));
    await tester.pumpAndSettle();
    expect(repo.copies, isEmpty);
    expect(find.text('이 업소에 레시피를 저장할 권한이 없습니다.'), findsOneWidget);
  });

  testWidgets('account change cancels pending sharing', (tester) async {
    final repo = CollectionRepository();
    await pumpCollection(tester, repo);
    await chooseRecipe(tester);
    final container = ProviderScope.containerOf(
        tester.element(find.byType(BusinessRecipeCollectionPage)));
    container.read(_account.notifier).state = 'another-user';
    await tester.pumpAndSettle();
    expect(repo.copies, isEmpty);
    expect(find.byKey(const Key('confirm-business-recipe-copy')), findsNothing);
  });

  testWidgets('English collection screen fits a narrow screen with large text',
      (tester) async {
    await pumpCollection(tester, CollectionRepository(), language: 'en');
    tester.view.physicalSize = const Size(320, 1000);
    tester.platformDispatcher.textScaleFactorTestValue = 2;
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    await tester.pumpAndSettle();
    expect(find.text('Collect recipes'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
