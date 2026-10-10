import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:k_youtube/core/localization/app_localizations.dart';
import 'package:k_youtube/core/theme/app_theme.dart';
import 'package:k_youtube/features/auth/application/auth_providers.dart';
import 'package:k_youtube/features/auth/presentation/account_page.dart';
import 'package:k_youtube/features/membership/application/membership_providers.dart';
import 'package:k_youtube/features/membership/domain/membership.dart';
import 'package:k_youtube/features/recipes/domain/recipe.dart';
import 'package:k_youtube/features/recipes/presentation/create_creator_recipe_page.dart';
import 'package:k_youtube/features/recipes/presentation/widgets/recipe_reading_sections.dart';
import 'package:k_youtube/features/recipes/presentation/widgets/unified_recipe_detail_layout.dart';

const _user = User(
    id: 'preview',
    appMetadata: {},
    userMetadata: {},
    aud: 'authenticated',
    email: 'recipe.scout@example.com',
    createdAt: '2026-09-25');
final _recipe = Recipe(
    id: 'preview-recipe',
    title: '우리집 토마토 수프',
    summary: '잘 익은 토마토와 양파로 만드는 따뜻한 한 그릇. 재료를 준비하고 순서대로 따라 해 보세요.',
    ingredients: [
      '토마토 400 g',
      '양파 100 g',
      '올리브유 15 ml',
      '소금 2 g'
    ],
    steps: [
      '토마토와 양파를 먹기 좋은 크기로 썰어 주세요.',
      '냄비에 올리브유를 두르고 양파를 볶아 주세요.',
      '토마토를 넣고 약한 불로 15분간 끓입니다.'
    ]);

Future<void> _capture(
    WidgetTester tester, GlobalKey boundary, String name) async {
  final output = Platform.environment['SCOUT_PREVIEW_OUTPUT'] ??
      (const bool.fromEnvironment('DESIGN_COMPLETE_CAPTURE')
          ? '.artifacts/design-complete'
          : null);
  if (output == null) return;
  await tester.runAsync(() async {
    final render =
        boundary.currentContext!.findRenderObject()! as RenderRepaintBoundary;
    final image = await render.toImage(pixelRatio: 1);
    final data = await image.toByteData(format: ui.ImageByteFormat.png);
    await Directory(output).create(recursive: true);
    await File('$output/$name.png').writeAsBytes(data!.buffer.asUint8List());
    image.dispose();
  });
}

Widget _app(Widget page, GlobalKey boundary,
        {double scale = 1, bool admin = false}) =>
    ProviderScope(
        overrides: [
          authUserProvider.overrideWith((_) => Stream.value(_user)),
          membershipInfoProvider.overrideWith(
              (_) async => MembershipInfo.fromJson({'is_admin': admin})),
        ],
        child: MaterialApp(
          locale: const Locale('ko'),
          supportedLocales: AppLocalizations.supportedLocales,
          localizationsDelegates: const [
            AppLocalizations.delegate,
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate
          ],
          theme: AppTheme.light,
          builder: (context, child) => MediaQuery(
              data: MediaQuery.of(context)
                  .copyWith(textScaler: TextScaler.linear(scale)),
              child: RepaintBoundary(key: boundary, child: child!)),
          home: page,
        ));

void main() {
  setUpAll(() async {
    for (final family in ['Roboto', 'Ahem', 'RecipeScoutKR']) {
      final font = FontLoader(family)
        ..addFont(rootBundle.load('assets/fonts/NanumGothic-Regular.ttf'));
      await font.load();
    }
    final icons = FontLoader('MaterialIcons')
      ..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'));
    await icons.load();
  });

  for (final width in [320.0, 1200.0]) {
    testWidgets(
        'recipe reading adapts at width $width and keeps cooking checks usable',
        (tester) async {
      tester.view.physicalSize = Size(width, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final boundary = GlobalKey();
      await tester.pumpWidget(_app(
          UnifiedRecipeDetailLayout(recipe: _recipe, appBarTitle: '레시피'),
          boundary,
          scale: width == 320 ? 2 : 1));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      if (width == 1200) {
        final ingredient =
            tester.getTopLeft(find.byType(RecipeIngredientsSection));
        final steps = tester.getTopLeft(find.byType(RecipeStepsSection));
        expect(steps.dx, greaterThan(ingredient.dx));
        expect(steps.dy, ingredient.dy);
      }
      await _capture(tester, boundary, 'recipe-detail-${width.toInt()}');
      final firstStep = find.byKey(const ValueKey('recipe-step-0'));
      await tester.ensureVisible(firstStep);
      await tester.tap(firstStep);
      await tester.pumpAndSettle();
      expect(find.text('1 / 3단계 완료'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }

  for (final admin in [false, true]) {
    testWidgets(
        'account groups preserve admin visibility and place destructive actions last $admin',
        (tester) async {
      tester.view.physicalSize = const Size(320, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final boundary = GlobalKey();
      await tester.pumpWidget(
          _app(const AccountPage(), boundary, scale: 2, admin: admin));
      await tester.pumpAndSettle();
      expect(find.text('관리자 홈'), admin ? findsOneWidget : findsNothing);
      expect(tester.getTopLeft(find.text('로그아웃')).dy,
          greaterThan(tester.getTopLeft(find.text('계정 삭제 안내')).dy));
      expect(tester.getTopLeft(find.text('회원탈퇴')).dy,
          greaterThan(tester.getTopLeft(find.text('로그아웃')).dy));
      await tester.ensureVisible(find.text('회원탈퇴'));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('account and editor preview use bounded readable layouts',
      (tester) async {
    tester.view.physicalSize = const Size(1200, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    var boundary = GlobalKey();
    await tester.pumpWidget(_app(const AccountPage(), boundary, admin: true));
    await tester.pumpAndSettle();
    await _capture(tester, boundary, 'account-desktop');
    expect(tester.takeException(), isNull);
    boundary = GlobalKey();
    await tester.pumpWidget(
        _app(CreateCreatorRecipePage(initialRecipe: _recipe), boundary));
    await tester.pumpAndSettle();
    await _capture(tester, boundary, 'recipe-editor-desktop');
    expect(tester.getSize(find.byType(ListView)).width, lessThanOrEqualTo(880));
    expect(tester.takeException(), isNull);
  });
  testWidgets('account and editor mobile previews', (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    var boundary = GlobalKey();
    await tester.pumpWidget(_app(const AccountPage(), boundary, admin: true));
    await tester.pumpAndSettle();
    await _capture(tester, boundary, 'account-mobile');
    expect(tester.takeException(), isNull);
    boundary = GlobalKey();
    await tester.pumpWidget(
        _app(CreateCreatorRecipePage(initialRecipe: _recipe), boundary));
    await tester.pumpAndSettle();
    await _capture(tester, boundary, 'recipe-editor-mobile');
    expect(tester.takeException(), isNull);
  });
}
