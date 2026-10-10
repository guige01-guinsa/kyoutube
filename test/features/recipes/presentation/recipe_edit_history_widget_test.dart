import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:k_youtube/core/localization/app_localizations.dart';
import 'package:k_youtube/core/theme/app_theme.dart';
import 'package:k_youtube/features/recipes/domain/recipe.dart';
import 'package:k_youtube/features/recipes/presentation/create_creator_recipe_page.dart';

const capture = bool.fromEnvironment('EDIT_CAPTURE');
Future<void> showEditor(WidgetTester tester, String language,
    {double scale = 1}) async {
  await tester.pumpWidget(ProviderScope(
      child: MaterialApp(
    debugShowCheckedModeBanner: false,
    theme: AppTheme.light,
    locale: Locale(language),
    supportedLocales: AppLocalizations.supportedLocales,
    localizationsDelegates: const [
      AppLocalizations.delegate,
      GlobalMaterialLocalizations.delegate,
      GlobalWidgetsLocalizations.delegate,
      GlobalCupertinoLocalizations.delegate
    ],
    builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context)
            .copyWith(textScaler: TextScaler.linear(scale)),
        child: child!),
    home: CreateCreatorRecipePage(
        initialRecipe: Recipe(
            id: 'draft',
            title: language == 'en' ? 'Roasted carrots' : '당근구이',
            summary: language == 'en'
                ? 'A simple roasted vegetable dish.'
                : '향긋하게 구운 당근 요리',
            ingredients: language == 'en'
                ? const ['Carrots 300 g', 'Olive oil 15 ml', 'Salt 2 g']
                : const ['당근 300 g', '올리브유 15 ml', '소금 2 g'],
            steps: language == 'en'
                ? const [
                    'Cut the carrots.',
                    'Toss with oil and salt.',
                    'Roast at 200 C for 20 minutes.'
                  ]
                : const ['당근을 자릅니다.', '올리브유와 소금을 넣고 섞습니다.', '200도에서 20분 굽습니다.'],
            sourceType: 'ai_enrichment_draft')),
  )));
  await tester.pumpAndSettle();
}

void main() {
  setUpAll(() async {
    if (!capture) return;
    for (final entry in {
      'Ahem': 'C:/Windows/Fonts/malgun.ttf',
      'Roboto': 'C:/Windows/Fonts/malgun.ttf',
      'MaterialIcons':
          '.fvm/flutter_sdk/bin/cache/artifacts/material_fonts/MaterialIcons-Regular.otf',
    }.entries) {
      final loader = FontLoader(entry.key);
      loader.addFont(Future.value(
          ByteData.sublistView(await File(entry.value).readAsBytes())));
      await loader.load();
    }
  });
  for (final lang in ['ko', 'en']) {
    testWidgets('$lang undo redo icons restore draft editing at narrow width',
        (tester) async {
      tester.view.physicalSize = const Size(320, 800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await showEditor(tester, lang, scale: 2);
      final undo = find.byKey(const Key('recipe-edit-undo')),
          redo = find.byKey(const Key('recipe-edit-redo'));
      expect(tester.widget<IconButton>(undo).onPressed, isNull);
      expect(tester.widget<IconButton>(redo).onPressed, isNull);
      await tester.scrollUntilVisible(
          find.byKey(const Key('creator-recipe-title')), 200);
      final first = find.byType(TextFormField).first;
      final controller = tester.widget<TextFormField>(first).controller!;
      final original = controller.text;
      await tester.ensureVisible(first);
      await tester.enterText(first, 'Edited carrots');
      await tester.pumpAndSettle();
      expect(tester.widget<IconButton>(undo).tooltip,
          lang == 'en' ? 'Undo' : '실행 취소');
      await tester.tap(undo);
      await tester.pumpAndSettle();
      expect(controller.text, original);
      await tester.tap(redo);
      await tester.pumpAndSettle();
      expect(controller.text, 'Edited carrots');
      expect(tester.takeException(), isNull);
    });
    if (capture) {
      testWidgets('$lang editor visual capture', (tester) async {
        tester.view.physicalSize = const Size(420, 900);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        await showEditor(tester, lang);
        final title = tester
            .widget<TextFormField>(find.byType(TextFormField).first)
            .controller!;
        title.text = lang == 'en' ? 'Golden roasted carrots' : '노릇한 당근구이';
        await tester.pumpAndSettle();
        await expectLater(find.byType(Scaffold),
            matchesGoldenFile('../../../../.artifacts/draft-edit-$lang.png'));
      });
    }
  }
}
