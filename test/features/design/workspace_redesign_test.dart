import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:k_youtube/core/localization/app_localizations.dart';
import 'package:k_youtube/core/theme/app_theme.dart';
import 'package:k_youtube/features/auth/application/auth_providers.dart';
import 'package:k_youtube/features/chef/data/chef_access.dart';
import 'package:k_youtube/features/chef/presentation/chef_hub_page.dart';
import 'package:k_youtube/features/recipes/application/recipe_providers.dart';
import 'package:k_youtube/features/recipes/domain/recipe.dart';
import 'package:k_youtube/features/shopping/presentation/shopping_workspace_links.dart';

const user = User(
    id: 'test-chef',
    appMetadata: {},
    userMetadata: {},
    aud: 'authenticated',
    createdAt: '2026-09-13');

void main() {
  setUpAll(() async {
    final font = FontLoader('Roboto')
      ..addFont(rootBundle.load('assets/fonts/NanumGothic-Regular.ttf'));
    final icons = FontLoader('MaterialIcons')
      ..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'));
    await font.load();
    await icons.load();
  });

  for (final en in [false, true]) {
    testWidgets(
        'chef hub ${en ? 'English' : 'Korean'} opens recipe and scales to large type',
        (tester) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final boundary = GlobalKey();
      final router = GoRouter(routes: [
        GoRoute(path: '/', builder: (_, __) => const ChefHubPage()),
        GoRoute(
            path: '/chef/:id',
            builder: (_, state) => Scaffold(
                body: Text('workspace:${state.pathParameters['id']}'))),
      ]);
      addTearDown(router.dispose);
      await tester.pumpWidget(ProviderScope(
          overrides: [
            authUserProvider.overrideWith((_) => Stream.value(user)),
            chefPaidAccessProvider.overrideWith((_) async => true),
            creatorRecipesProvider.overrideWith((_, search) async => [
                  Recipe(
                      id: 'owned-recipe',
                      title: en ? 'Mushroom risotto' : '버섯 리소토',
                      ingredients: [],
                      steps: []),
                ]),
          ],
          child: MaterialApp.router(
            locale: Locale(en ? 'en' : 'ko'),
            supportedLocales: AppLocalizations.supportedLocales,
            localizationsDelegates: const [
              AppLocalizations.delegate,
              GlobalMaterialLocalizations.delegate,
              GlobalWidgetsLocalizations.delegate,
              GlobalCupertinoLocalizations.delegate
            ],
            theme: AppTheme.light,
            routerConfig: router,
            builder: (_, child) =>
                RepaintBoundary(key: boundary, child: child!),
          )));
      await tester.pumpAndSettle();
      expect(find.text(en ? 'Sales overview' : '매출 현황'), findsOneWidget);
      expect(tester.takeException(), isNull);
      final output = Platform.environment['SCOUT_PREVIEW_OUTPUT'];
      if (output != null) {
        await tester.runAsync(() async {
          final render = boundary.currentContext!.findRenderObject()!
              as RenderRepaintBoundary;
          final picture = await render.toImage(pixelRatio: 2);
          final bytes =
              await picture.toByteData(format: ui.ImageByteFormat.png);
          await Directory(output).create(recursive: true);
          await File('$output/chef-${en ? 'en' : 'ko'}.png')
              .writeAsBytes(bytes!.buffer.asUint8List());
          picture.dispose();
        });
      }
      tester.view.physicalSize = const Size(320, 640);
      tester.platformDispatcher.textScaleFactorTestValue = 2;
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
      await tester.pumpAndSettle();
      await tester.scrollUntilVisible(
          find.byKey(const ValueKey('chef-recipe-owned-recipe')), 240,
          scrollable: find.byType(Scrollable).first);
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      await tester.tap(find.byKey(const ValueKey('chef-recipe-owned-recipe')));
      await tester.pumpAndSettle();
      expect(find.text('workspace:owned-recipe'), findsOneWidget);
    });
  }

  testWidgets(
      'free access preserves recipe work and logout clears private rows',
      (tester) async {
    final users = StreamController<User?>();
    addTearDown(users.close);
    await tester.pumpWidget(ProviderScope(overrides: [
      authUserProvider.overrideWith((_) => users.stream),
      chefPaidAccessProvider.overrideWith((_) async => false),
      creatorRecipesProvider.overrideWith((_, __) async => [
            Recipe(
                id: 'private',
                title: 'Private recipe',
                ingredients: [],
                steps: []),
          ]),
    ], child: MaterialApp(theme: AppTheme.light, home: const ChefHubPage())));
    users.add(user);
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(find.text('Private recipe'), 220,
        scrollable: find.byType(Scrollable).first);
    expect(find.text('매출 현황'), findsNothing);
    users.add(null);
    await tester.pumpAndSettle();
    expect(find.text('Private recipe'), findsNothing);
    expect(find.text('로그인하고 시작'), findsOneWidget);
  });

  testWidgets(
      'shopping destinations remain reachable without a list at 200% type',
      (tester) async {
    tester.view.physicalSize = const Size(320, 640);
    tester.view.devicePixelRatio = 1;
    tester.platformDispatcher.textScaleFactorTestValue = 2;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    final router = GoRouter(routes: [
      GoRoute(
          path: '/',
          builder: (_, __) => const Scaffold(
              body: SingleChildScrollView(child: ShoppingWorkspaceLinks()))),
      for (final path in ['/shopping', '/shopping-stores'])
        GoRoute(
            path: path,
            builder: (_, state) => Scaffold(body: Text(state.uri.path))),
    ]);
    addTearDown(router.dispose);
    await tester.pumpWidget(MaterialApp.router(
      locale: const Locale('ko'),
      supportedLocales: AppLocalizations.supportedLocales,
      localizationsDelegates: const [
        AppLocalizations.delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      theme: AppTheme.light,
      routerConfig: router,
    ));
    for (final item in [
      ('장보기', '/shopping'),
      ('거래처', '/shopping-stores'),
    ]) {
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      await tester.tap(find.text(item.$1));
      await tester.pumpAndSettle();
      expect(find.text(item.$2), findsOneWidget);
      router.pop();
    }
  });
}
