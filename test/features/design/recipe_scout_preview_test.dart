// Render real Flutter screens with local fixtures, without backend credentials.
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:k_youtube/core/theme/app_theme.dart';
import 'package:k_youtube/core/localization/app_localizations.dart';
import 'package:k_youtube/features/auth/application/auth_providers.dart';
import 'package:k_youtube/features/home/presentation/home_page.dart';
import 'package:k_youtube/features/kitchen/application/kitchen_providers.dart';
import 'package:k_youtube/features/kitchen/application/shopping_persistence_controllers.dart';
import 'package:k_youtube/features/kitchen/data/kitchen_api.dart';
import 'package:k_youtube/features/kitchen/domain/kitchen_models.dart';
import 'package:k_youtube/features/kitchen/presentation/kitchen_page.dart';
import 'package:k_youtube/features/kitchen/presentation/shopping_review_page.dart';
import 'package:k_youtube/features/recipes/application/recipe_providers.dart';
import 'package:k_youtube/features/recipes/application/unified_recipe_providers.dart';
import 'package:k_youtube/features/recipes/data/unified_recipe_mappers.dart';
import 'package:k_youtube/features/recipes/domain/recipe.dart';
import 'package:k_youtube/features/recipes/domain/recipe_identity.dart';
import 'package:k_youtube/features/recipes/presentation/my_recipes_page.dart';
import 'package:k_youtube/features/recipes/presentation/creator_recipe_detail_page.dart';

final _recipe = Recipe(
  id: 'preview-recipe',
  title: '포근한 한 그릇, 토마토 달걀볶음',
  summary: '부드러운 달걀과 촉촉한 토마토. 따뜻한 밥 위에 올려 가볍게 즐기는 한 끼예요.',
  ingredients: <String>['토마토 2개', '달걀 3개', '대파 1대', '간장 1큰술', '식용유 1큰술'],
  steps: <String>[
    '토마토는 한입 크기로 썰고, 달걀은 잘 풀어주세요.',
    '팬에 식용유를 두르고 달걀을 부드럽게 익힌 뒤 덜어두세요.',
    '대파와 토마토를 볶다가 달걀과 간장을 넣어 가볍게 섞으면 완성이에요.'
  ],
  sourceType: 'manual',
);

class _PreviewKitchenApi extends KitchenApi {
  @override
  Future<List<KitchenIngredient>> listIngredients({String? query}) async =>
      const <KitchenIngredient>[];
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() async {
    final icons = FontLoader('MaterialIcons');
    icons.addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'));
    await icons.load();
    final fontPath = Platform.environment['SCOUT_PREVIEW_FONT'];
    if (fontPath != null) {
      final loader = FontLoader('Roboto');
      loader.addFont(Future.value(
          ByteData.sublistView(await File(fontPath).readAsBytes())));
      await loader.load();
    }
  });

  for (final screen in <String>[
    'home',
    'notebook',
    'notebook-en',
    'detail',
    'detail-en',
    'steps',
    'shopping',
    'review'
  ]) {
    testWidgets('render $screen with fixture data', (tester) async {
      SharedPreferences.setMockInitialValues(<String, Object>{});
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final boundary = GlobalKey();
      const user = User(
          id: 'preview-user',
          appMetadata: {},
          userMetadata: {},
          aud: 'authenticated',
          createdAt: '2026-09-09T00:00:00Z');
      final overrides = <Override>[
        authUserProvider.overrideWith((_) => Stream.value(user)),
        publicRecipesProvider.overrideWith((_, __) async => <Recipe>[_recipe]),
        recipeByIdProvider.overrideWith((_, __) async => _recipe),
        creatorRecipeByIdProvider.overrideWith((_, __) async => _recipe),
        recipeSearchExclusionsProvider.overrideWith((_) async => []),
        myUnifiedRecipesProvider.overrideWith((_, __) async => [
              mapRecipeToUnifiedRecipe(
                  recipe: _recipe,
                  identity: const RecipeIdentity(
                      sourceType: 'creator', sourceId: 'preview-recipe'))
            ]),
        kitchenApiProvider.overrideWithValue(_PreviewKitchenApi()),
        shoppingReviewDraftControllerProvider.overrideWith((ref) async =>
            ShoppingReviewDraftController(
                store: await ref.watch(shoppingReviewDraftStoreProvider.future),
                currentUserId: () async => user.id)),
        kitchenSummaryProvider.overrideWith((_) async => <String, int>{
              'ingredient_count': 8,
              'expiring_soon_count': 1,
              'active_shopping_list_count': 1,
              'open_shopping_item_count': 3
            }),
        kitchenShoppingListsProvider
            .overrideWith((_) async => <KitchenShoppingList>[
                  KitchenShoppingList(
                      id: 'preview-list',
                      status: 'active',
                      title: '토마토 달걀볶음',
                      openItemCount: 3,
                      items: [
                        for (var i = 0; i < 3; i++)
                          KitchenShoppingItem(
                              id: 'item-$i',
                              listId: 'preview-list',
                              name: ['토마토', '달걀', '대파'][i],
                              ingredientText: _recipe.ingredients[i],
                              status: KitchenShoppingItemStatus.pending,
                              reviewStatus:
                                  KitchenShoppingItemReviewStatus.confirmed,
                              needsReview: false,
                              isChecked: false,
                              revision: 1,
                              updatedAt: DateTime(2026, 9, 9),
                              quantity: 2,
                              unit: 'ea'),
                      ]),
                ]),
        kitchenCompletedShoppingListsProvider.overrideWith((_) async => []),
        kitchenCookSessionsProvider.overrideWith((_) async => []),
      ];
      const detail = CreatorRecipeDetailPage(recipeId: 'preview-recipe');
      final page = switch (screen) {
        'home' => const HomePage(),
        'notebook' || 'notebook-en' => const MyRecipesPage(),
        'shopping' => const KitchenPage(),
        'review' => const ShoppingReviewPage(
            sourceRecipeReference: 'public:preview-recipe'),
        _ => detail,
      };
      final router =
          GoRouter(routes: [GoRoute(path: '/', builder: (_, __) => page)]);
      addTearDown(router.dispose);
      await tester.pumpWidget(RepaintBoundary(
          key: boundary,
          child: ProviderScope(
              overrides: overrides,
              child: MaterialApp.router(
                  debugShowCheckedModeBanner: false,
                  locale: Locale(screen.endsWith('-en') ? 'en' : 'ko'),
                  supportedLocales: AppLocalizations.supportedLocales,
                  localizationsDelegates: const [
                    AppLocalizations.delegate,
                    GlobalMaterialLocalizations.delegate,
                    GlobalWidgetsLocalizations.delegate,
                    GlobalCupertinoLocalizations.delegate,
                  ],
                  theme: AppTheme.light,
                  routerConfig: router))));
      await tester.pumpAndSettle();
      if (screen == 'steps') {
        await tester.scrollUntilVisible(find.text('조리 순서'), 240,
            scrollable: find.byType(Scrollable).first);
        await tester.pumpAndSettle();
      }
      expect(tester.takeException(), isNull);
      if (screen == 'review') expect(find.text('장볼 재료 선택'), findsOneWidget);
      final output = Platform.environment['SCOUT_PREVIEW_OUTPUT'];
      if (output != null) {
        await tester.runAsync(() async {
          final render = boundary.currentContext!.findRenderObject()!
              as RenderRepaintBoundary;
          final picture = await render.toImage(pixelRatio: 2);
          final bytes =
              await picture.toByteData(format: ui.ImageByteFormat.png);
          await Directory(output).create(recursive: true);
          await File('$output/$screen.png')
              .writeAsBytes(bytes!.buffer.asUint8List());
          picture.dispose();
        });
      }
      // The same real pages must also lay out with a narrow viewport and 200% type.
      tester.view.physicalSize = const Size(320, 640);
      tester.platformDispatcher.textScaleFactorTestValue = 2;
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    });
  }
}
