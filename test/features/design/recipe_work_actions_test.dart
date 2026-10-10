import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:k_youtube/core/localization/app_localizations.dart';
import 'package:k_youtube/core/theme/app_theme.dart';
import 'package:k_youtube/features/auth/application/auth_providers.dart';
import 'package:k_youtube/features/recipes/application/unified_recipe_providers.dart';
import 'package:k_youtube/features/recipes/application/recipe_providers.dart';
import 'package:k_youtube/features/recipes/presentation/my_recipes_page.dart';
import 'package:k_youtube/features/recipes/presentation/widgets/recipe_work_actions.dart';

const _delegates = <LocalizationsDelegate<dynamic>>[
  AppLocalizations.delegate,
  GlobalMaterialLocalizations.delegate,
  GlobalWidgetsLocalizations.delegate,
  GlobalCupertinoLocalizations.delegate,
];

void main() {
  for (final language in ['ko', 'en']) {
    for (final largeText in [false, true]) {
      testWidgets(
          '$language equal actions and independent taps, large=$largeText',
          (tester) async {
        tester.view.physicalSize = Size(largeText ? 320 : 390, 844);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        var chef = 0;
        var shopping = 0;
        await tester.pumpWidget(MaterialApp(
          theme: AppTheme.light,
          locale: Locale(language),
          supportedLocales: AppLocalizations.supportedLocales,
          localizationsDelegates: _delegates,
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context)
                .copyWith(textScaler: TextScaler.linear(largeText ? 2 : 1)),
            child: child!,
          ),
          home: Scaffold(
              body: SingleChildScrollView(
            padding: const EdgeInsets.all(20),
            child: RecipeWorkActions(
                onChef: () => chef++, onShopping: () => shopping++),
          )),
        ));
        await tester.pumpAndSettle();
        final chefButton = find.byKey(const Key('recipe-chef-action'));
        final shoppingButton = find.byKey(const Key('recipe-shopping-action'));
        final chefRect = tester.getRect(chefButton);
        final shoppingRect = tester.getRect(shoppingButton);
        expect(chefRect.size, shoppingRect.size);
        expect(chefRect.height, lessThan(largeText ? 150 : 90));
        expect(chefRect.height, greaterThanOrEqualTo(48));
        expect(chefRect.overlaps(shoppingRect), isFalse);
        if (largeText) {
          expect(chefRect.left, shoppingRect.left);
          expect(shoppingRect.top, greaterThan(chefRect.bottom));
        } else {
          expect(chefRect.top, shoppingRect.top);
        }
        await tester.tap(chefButton);
        expect(chef, 1);
        expect(shopping, 0);
        await tester.tap(shoppingButton);
        expect(chef, 1);
        expect(shopping, 1);
        expect(tester.takeException(), isNull);
      });
    }

    testWidgets('$language app bar creation stays reachable and refreshes list',
        (tester) async {
      const user = User(
          id: 'test-user',
          appMetadata: {},
          userMetadata: {},
          aud: 'authenticated',
          createdAt: '2026-09-13T00:00:00Z');
      var reads = 0;
      final router = GoRouter(routes: [
        GoRoute(path: '/', builder: (_, __) => const MyRecipesPage()),
        GoRoute(
            path: '/creator/new',
            builder: (context, _) => Scaffold(
                body: TextButton(
                    onPressed: () => context.pop(true),
                    child: const Text('SAVE TEST RECIPE')))),
      ]);
      addTearDown(router.dispose);
      await tester.pumpWidget(ProviderScope(
          overrides: [
            authUserProvider.overrideWith((_) => Stream.value(user)),
            recipeSearchExclusionsProvider.overrideWith((_) async => []),
            myUnifiedRecipesProvider.overrideWith((_, __) async {
              reads++;
              return [];
            }),
          ],
          child: MaterialApp.router(
            theme: AppTheme.light,
            routerConfig: router,
            locale: Locale(language),
            supportedLocales: AppLocalizations.supportedLocales,
            localizationsDelegates: _delegates,
          )));
      await tester.pumpAndSettle();
      expect(find.byType(FloatingActionButton), findsNothing);
      final add = find.byKey(const Key('create-recipe-action'));
      expect(find.ancestor(of: add, matching: find.byType(AppBar)),
          findsOneWidget);
      expect(
          find.descendant(
              of: add,
              matching: find.text(language == 'en' ? 'New recipe' : '새 레시피')),
          findsOneWidget);
      final before = reads;
      await tester.tap(add);
      await tester.pumpAndSettle();
      await tester.tap(find.text('SAVE TEST RECIPE'));
      await tester.pumpAndSettle();
      expect(reads, greaterThan(before));
      expect(add, findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }
}
