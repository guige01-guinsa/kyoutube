import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:k_youtube/core/localization/app_localizations.dart';
import 'package:k_youtube/core/theme/app_theme.dart';
import 'package:k_youtube/features/guide/domain/guide_curriculum.dart';
import 'package:k_youtube/features/guide/application/guide_sample_store.dart';
import 'package:k_youtube/features/guide/application/guide_progress.dart';
import 'package:k_youtube/features/guide/presentation/guide_sample_page.dart';
import 'package:k_youtube/features/guide/presentation/product_guide_page.dart';
import 'package:k_youtube/features/shopping/application/supplier_request_pdf.dart';

Future<GoRouter> showSample(WidgetTester tester, String id,
    {String language = 'ko', double scale = 1}) async {
  final router = GoRouter(
      initialLocation: id == 'guide' ? '/guide' : guideSamplePath(id),
      routes: [
        GoRoute(
            path: '/guide',
            builder: (_, __) =>
                const ProductGuidePage(initialLesson: 'buy-quantity')),
        GoRoute(
            path: '/guide/practice/:lesson',
            builder: (_, s) => GuideSamplePage(
                key: ValueKey(s.pathParameters['lesson']),
                lessonId: s.pathParameters['lesson']!))
      ]);
  await tester.pumpWidget(MaterialApp.router(
      key: UniqueKey(),
      routerConfig: router,
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
          child: RepaintBoundary(
              key: const Key('sample-capture'), child: child!))));
  await tester.pumpAndSettle();
  return router;
}

Future<void> tapKey(WidgetTester t, String key) async {
  final f = find.byKey(Key(key));
  await t.ensureVisible(f);
  await t.pumpAndSettle();
  await t.tap(f);
  await t.pumpAndSettle();
}

Future<void> edit(WidgetTester t, String key, String text) async {
  final f = find.byKey(ValueKey(key));
  await t.ensureVisible(f);
  await t.enterText(f, text);
  await t.pumpAndSettle();
}

ByteData? captureFont;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() async {
    if (!const bool.fromEnvironment('GUIDE_SAMPLE_CAPTURE')) return;
    final bytes = ByteData.sublistView(
        await File('assets/fonts/NanumGothic-Regular.ttf').readAsBytes());
    captureFont = bytes;
    final icons = FontLoader('MaterialIcons')
      ..addFont(Future.value(ByteData.sublistView(await File(
              '.fvm/flutter_sdk/bin/cache/artifacts/material_fonts/MaterialIcons-Regular.otf')
          .readAsBytes())));
    await icons.load();

    for (final family in ['Ahem', 'Roboto', 'RecipeScoutKR']) {
      final loader = FontLoader(family)..addFont(Future.value(bytes));
      await loader.load();
    }
  });

  setUp(() => SharedPreferences.setMockInitialValues(
      {'real-business-data': 'untouched'}));
  for (final language in ['ko', 'en']) {
    testWidgets(
        '$language all 24 sample lessons open and save at 320px / 200% without login or Supabase',
        (tester) async {
      tester.view.physicalSize = const Size(320, 860);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      for (final lesson in guideLessons) {
        final router =
            await showSample(tester, lesson.id, language: language, scale: 2);
        expect(tester.takeException(), isNull, reason: lesson.id);
        await tapKey(tester, 'sample-save');
        expect(find.byKey(const Key('sample-saved')), findsOneWidget,
            reason: lesson.id);
        expect(tester.takeException(), isNull, reason: lesson.id);
        await tester.pumpWidget(const SizedBox());
        router.dispose();
      }
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString('real-business-data'), 'untouched');
      final data = await GuideSampleStore(language == 'en').load();
      expect(data.practiced.length, 24);
    });
  }
  testWidgets(
      'tutorial entry returns with actual sample completion and saved quantities',
      (tester) async {
    final router = await showSample(tester, 'guide');
    await tapKey(tester, 'guide-sample-workspace');
    await edit(tester, '0-shopping-carrot', '2');
    await tapKey(tester, 'sample-save');
    await tester.tap(find.byTooltip('튜토리얼로 돌아가기'));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('guide-result')), findsOneWidget);
    expect((await GuideSampleStore(false).load()).purchase.quantities['carrot'],
        2);
    await tester.pumpWidget(const SizedBox());
    router.dispose();
  });
  testWidgets(
      'invalid quantities cannot overwrite the saved record; valid edits resume and reset',
      (tester) async {
    var router = await showSample(tester, 'buy-quantity');
    await edit(tester, '0-shopping-carrot', 'NaN');
    await tapKey(tester, 'sample-save');
    expect(find.byKey(const Key('sample-saved')), findsNothing);
    expect((await GuideSampleStore(false).load()).purchase.quantities['carrot'],
        1);
    await edit(tester, '0-shopping-carrot', '4');
    await tapKey(tester, 'sample-create-shopping');
    await tester.pumpWidget(const SizedBox());
    router.dispose();
    router = await showSample(tester, 'buy-quantity');
    expect(
        tester
            .widget<TextFormField>(
                find.byKey(const ValueKey('0-shopping-carrot')))
            .initialValue,
        '4');
    await tapKey(tester, 'sample-reset');
    await tester.tap(find.text('확인'));
    await tester.pumpAndSettle();
    expect((await GuideSampleStore(false).load()).purchase.quantities['carrot'],
        1);
    expect(
        (await SharedPreferences.getInstance()).getString('real-business-data'),
        'untouched');
    await tester.pumpWidget(const SizedBox());
    router.dispose();
  });
  testWidgets(
      'comparison creates editable drafts and simulated sending stays local',
      (tester) async {
    final store = GuideSampleStore(true), d = await store.load();
    d.purchase.quantity('carrot', 2);
    await store.save(d);
    final router = await showSample(tester, 'buy-compare', language: 'en');
    await tapKey(tester, 'sample-create-requests');
    await edit(tester, '0-request-buyer', 'Sample training kitchen');
    await tapKey(tester, 'sample-request-review');
    await tapKey(tester, 'sample-send');
    final saved = await store.load();
    expect(saved.request.status, 'sent');
    expect(saved.request.buyer, 'Sample training kitchen');
    await edit(tester, '0-request-address', 'Sample new address');
    expect(
        tester
            .widget<FilledButton>(find.byKey(const Key('sample-send')))
            .onPressed,
        isNull);
    expect(
        (await SharedPreferences.getInstance()).getString('real-business-data'),
        'untouched');
    await tester.pumpWidget(const SizedBox());
    router.dispose();
  });
  testWidgets(
      'supplier image and pack edits persist; publication requires review and stays local',
      (tester) async {
    var router = await showSample(tester, 'supplier-product');
    await tapKey(tester, 'sample-photo-tofu');
    await edit(tester, '0-product-name', '샘플 두부 상품');
    await tapKey(tester, 'sample-save');
    expect((await GuideSampleStore(false).load()).products.first.image, 'tofu');
    await tester.pumpWidget(const SizedBox());
    router.dispose();
    router = await showSample(tester, 'supplier-publish');
    expect(
        tester
            .widget<FilledButton>(find.byKey(const Key('sample-publish')))
            .onPressed,
        isNull);
    await tapKey(tester, 'sample-publish-review');
    await tapKey(tester, 'sample-publish');
    expect((await GuideSampleStore(false).load()).published, isTrue);
    expect(
        (await SharedPreferences.getInstance()).getString('real-business-data'),
        'untouched');
    await tester.pumpWidget(const SizedBox());
    router.dispose();
  });
  testWidgets(
      'leaving unsaved work needs a choice and preserves previous saved copy',
      (tester) async {
    final router = await showSample(tester, 'guide');
    await tapKey(tester, 'guide-sample-workspace');
    await edit(tester, '0-shopping-tofu', '7');
    await tester.tap(find.byTooltip('튜토리얼로 돌아가기'));
    await tester.pumpAndSettle();
    expect(find.byType(AlertDialog), findsOneWidget);
    await tester.tap(find.text('취소'));
    await tester.pumpAndSettle();
    expect(find.byType(GuideSamplePage), findsOneWidget);
    await tester.tap(find.byTooltip('튜토리얼로 돌아가기'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('확인'));
    await tester.pumpAndSettle();
    expect(
        (await GuideSampleStore(false).load()).purchase.quantities['tofu'], 1);
    await tester.pumpWidget(const SizedBox());
    router.dispose();
  });
  testWidgets(
      'purchase kg to g preserves quantity and never changes cooking amounts',
      (tester) async {
    final router = await showSample(tester, 'buy-quantity');
    final before = (await GuideSampleStore(false).load())
        .recipe
        .ingredients
        .first
        .quantity;
    final unit = find.byKey(const ValueKey('0-shopping-unit-carrot'));
    await tester.ensureVisible(unit);
    await tester.tap(unit);
    await tester.pumpAndSettle();
    await tester.tap(find.text('g').last);
    await tester.pumpAndSettle();
    expect(
        tester
            .widget<TextFormField>(
                find.byKey(const ValueKey('1-shopping-carrot')))
            .initialValue,
        '1000');
    await edit(tester, '1-shopping-carrot', '2500');
    await tapKey(tester, 'sample-save');
    final saved = await GuideSampleStore(false).load();
    expect(saved.purchase.quantities['carrot'], 2.5);
    expect(saved.purchaseUnits['carrot'], 'g');
    expect(saved.recipe.ingredients.first.quantity, before);
    await tester.pumpWidget(const SizedBox());
    router.dispose();
  });
  testWidgets('visual review and real sample PDF rendering', (tester) async {
    if (!const bool.fromEnvironment('GUIDE_SAMPLE_CAPTURE')) return;
    final font = captureFont!;
    final out = Directory('.artifacts/tutorial-samples');
    await tester.runAsync(() => out.create(recursive: true));
    for (final language in ['ko', 'en']) {
      for (final id in ['buy-compare', 'supplier-product', 'pro-pricing']) {
        tester.view.physicalSize = id == 'buy-compare'
            ? const Size(1100, 1100)
            : const Size(390, 1000);
        tester.view.devicePixelRatio = 1;
        final router = await showSample(tester, id, language: language);
        // Capture the practical content below the concise safety banner.
        await tester.drag(
            find.byType(SingleChildScrollView).first, const Offset(0, -430));
        await tester.pumpAndSettle();
        final boundary = tester.renderObject<RenderRepaintBoundary>(
            find.byKey(const Key('sample-capture')));
        await tester.runAsync(() async {
          final image = await boundary.toImage();
          final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
          await File('${out.path}/$id-$language.png')
              .writeAsBytes(bytes!.buffer.asUint8List());
          image.dispose();
        });
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox());
        router.dispose();
      }
      final data = await GuideSampleStore(language == 'en').load();
      final bytes = (await tester.runAsync(() => supplierRequestPdf(
          data.request, font,
          english: language == 'en', practice: true)))!;
      await tester.runAsync(
          () => File('${out.path}/practice-$language.pdf').writeAsBytes(bytes));
      expect(bytes.take(4).toList(), [37, 80, 68, 70]);
    }
    tester.view.resetPhysicalSize();
    tester.view.resetDevicePixelRatio();
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getStringList(GuideProgress.storageKey), isNull);
  });
}
