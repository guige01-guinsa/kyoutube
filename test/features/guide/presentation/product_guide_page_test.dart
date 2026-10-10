import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:k_youtube/core/localization/app_localizations.dart';
import 'package:k_youtube/core/theme/app_theme.dart';
import 'package:k_youtube/features/guide/domain/guide_curriculum.dart';
import 'package:k_youtube/features/guide/application/guide_progress.dart';
import 'package:k_youtube/features/guide/presentation/guide_help_button.dart';
import 'package:k_youtube/features/guide/presentation/product_guide_page.dart';

Future<void> showGuide(WidgetTester tester, String language,
    {double scale = 1, GuideAudience? audience, String? lesson}) async {
  await tester.pumpWidget(MaterialApp(
    debugShowCheckedModeBanner: false,
    theme: const bool.fromEnvironment('GUIDE_CAPTURE')
        ? AppTheme.light.copyWith(
            textTheme:
                AppTheme.light.textTheme.apply(fontFamily: 'GuidePreview'))
        : AppTheme.light,
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
    home: ProductGuidePage(initialAudience: audience, initialLesson: lesson),
  ));
  await tester.pumpAndSettle();
}

Future<void> tapVisible(WidgetTester tester, String key) async {
  final finder = find.byKey(Key(key));
  await tester.ensureVisible(finder);
  await tester.pumpAndSettle();
  await tester.tap(finder);
  await tester.pumpAndSettle();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() async {
    if (!const bool.fromEnvironment('GUIDE_CAPTURE')) return;
    final path = Platform.environment['GUIDE_FONT_PATH'];
    if (path == null) throw StateError('Set GUIDE_FONT_PATH for captures.');
    for (final entry in {
      'GuidePreview': path,
      'Ahem': path,
      'Roboto': path,
      'MaterialIcons':
          '.fvm/flutter_sdk/bin/cache/artifacts/material_fonts/MaterialIcons-Regular.otf',
    }.entries) {
      final loader = FontLoader(entry.key);
      loader.addFont(Future.value(
          ByteData.sublistView(await File(entry.value).readAsBytes())));
      await loader.load();
    }
  });
  setUp(() => SharedPreferences.setMockInitialValues({}));

  for (final language in ['ko', 'en']) {
    testWidgets(
        '$language recommends three tasks and separates all role tracks',
        (tester) async {
      await showGuide(tester, language);
      expect(find.textContaining('0 / 14'), findsOneWidget);
      expect(
          find.byKey(const Key('guide-lesson-buy-quantity')), findsOneWidget);
      expect(find.byKey(const Key('guide-lesson-buy-request')), findsNothing);
      await tapVisible(tester, 'guide-show-all');
      expect(find.byKey(const Key('guide-lesson-buy-ledger')), findsOneWidget);
      await tapVisible(tester, 'guide-track-cooking');
      expect(
          find.byKey(const Key('guide-lesson-pro-standard')), findsOneWidget);
      await tapVisible(tester, 'guide-audience-home');
      expect(find.textContaining('0 / 5'), findsOneWidget);
      await tapVisible(tester, 'guide-audience-supplier');
      expect(find.byKey(const Key('guide-lesson-supplier-profile')),
          findsOneWidget);
      expect(find.byKey(const Key('guide-lesson-home-search')), findsNothing);
      await tester.pumpWidget(const SizedBox());
      await showGuide(tester, language);
      expect(find.byKey(const Key('guide-lesson-supplier-profile')),
          findsOneWidget);
      expect(tester.takeException(), isNull);
    });
    testWidgets(
        '$language quiz is optional and completion, skip and replay stay separate',
        (tester) async {
      await showGuide(tester, language, lesson: 'buy-quantity');
      final complete = find.byKey(const Key('guide-complete'));
      expect(tester.widget<FilledButton>(complete).onPressed, isNull);
      for (var i = 0; i < guideLessonById('buy-quantity')!.steps.length; i++) {
        await tapVisible(tester, 'guide-step-$i');
      }
      expect(tester.widget<FilledButton>(complete).onPressed, isNotNull);
      await tapVisible(tester, 'guide-complete');
      expect(find.byKey(const Key('guide-result')), findsOneWidget);
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getStringList(GuideProgress.storageKey),
          contains('buy-quantity.done'));
      expect(prefs.getStringList(GuideProgress.storageKey),
          isNot(contains('buy-quantity.quiz')));
      await tapVisible(tester, 'guide-next');
      await tapVisible(tester, 'guide-skip');
      expect(prefs.getStringList(GuideProgress.storageKey),
          contains('buy-suppliers.skipped'));
      expect(prefs.getStringList(GuideProgress.storageKey),
          isNot(contains('buy-suppliers.done')));
      await tapVisible(tester, 'guide-overview');
      await tapVisible(tester, 'guide-show-all');
      await tapVisible(tester, 'guide-lesson-buy-quantity');
      await tapVisible(tester, 'guide-restart');
      expect(prefs.getStringList(GuideProgress.storageKey),
          isNot(contains('buy-quantity.done')));
      expect(prefs.getStringList(GuideProgress.storageKey),
          contains('buy-suppliers.skipped'));
    });
    testWidgets(
        '$language all 24 lessons and examples fit 320px with double text',
        (tester) async {
      tester.view.physicalSize = const Size(320, 740);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      for (final l in guideLessons) {
        await tester.pumpWidget(const SizedBox());
        await showGuide(tester, language, scale: 2, lesson: l.id);
        await tapVisible(tester, 'guide-try-example');
        await tapVisible(tester, 'guide-quiz-${l.id}');
        await tester.ensureVisible(find.byKey(const Key('guide-complete')));
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull, reason: l.id);
        if (language == 'en') {
          final texts = tester
              .widgetList<Text>(find.byType(Text))
              .map((w) => w.data ?? '')
              .join();
          expect(RegExp(r'[가-힣]').hasMatch(texts), isFalse, reason: l.id);
        }
      }
    });
    testWidgets('$language calculations are tried separately from real work',
        (tester) async {
      await showGuide(tester, language, lesson: 'pro-scale');
      expect(find.byKey(const Key('guide-example-usage')), findsNothing);
      await tapVisible(tester, 'guide-try-example');
      await tapVisible(tester, 'guide-example-servings-20');
      expect(
          tester
              .widget<Text>(find.byKey(const Key('guide-example-usage')))
              .data,
          '4,000 g');
      await tapVisible(tester, 'guide-complete');
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getStringList(GuideProgress.storageKey),
          contains('pro-scale.done'));
      expect(prefs.getKeys().every((k) => k.startsWith('guide_')), isTrue);
      await tester.pumpWidget(const SizedBox());
      await showGuide(tester, language, lesson: 'pro-yield');
      await tapVisible(tester, 'guide-try-example');
      tester
          .widget<Slider>(find.byKey(const Key('guide-example-yield')))
          .onChanged!(100);
      await tester.pumpAndSettle();
      expect(
          tester
              .widget<Text>(find.byKey(const Key('guide-example-purchase')))
              .data,
          '800 g');
      await tester.pumpWidget(const SizedBox());
      await showGuide(tester, language, lesson: 'pro-pricing');
      await tapVisible(tester, 'guide-try-example');
      tester
          .widget<Slider>(find.byKey(const Key('guide-example-markup')))
          .onChanged!(100);
      await tester.pumpAndSettle();
      expect(
          tester
              .widget<Text>(find.byKey(const Key('guide-example-price')))
              .data,
          'KRW 6,000');
    });
    if (const bool.fromEnvironment('GUIDE_CAPTURE')) {
      testWidgets(
          '$language visual review of mobile and desktop roles and purchase comparison',
          (tester) async {
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        for (final width in [390.0, 1440.0]) {
          tester.view.physicalSize = Size(width, 1000);
          for (final a in GuideAudience.values) {
            await tester.pumpWidget(const SizedBox());
            await showGuide(tester, language, audience: a);
            await expectLater(
                find.byType(MaterialApp),
                matchesGoldenFile(File(
                        '.artifacts/tutorial-v3-${a.name}-$language-${width.toInt()}.png')
                    .absolute
                    .uri));
          }
        }
        tester.view.physicalSize = const Size(390, 1000);
        for (final id in ['buy-compare', 'supplier-pack']) {
          await tester.pumpWidget(const SizedBox());
          await showGuide(tester, language, lesson: id);
          await tapVisible(tester, 'guide-try-example');
          await tester.ensureVisible(find.byKey(const Key('guide-training')));
          await tester.pumpAndSettle();
          await expectLater(
              find.byType(MaterialApp),
              matchesGoldenFile(File('.artifacts/tutorial-v3-$id-$language.png')
                  .absolute
                  .uri));
        }
      });
    }
  }
  testWidgets(
      'candidate cap is per ingredient and comparison shares in-memory choices',
      (tester) async {
    await showGuide(tester, 'en', lesson: 'buy-candidates');
    await tapVisible(tester, 'guide-try-example');
    await tapVisible(tester, 'guide-candidate-carrot-C');
    expect(
        find.text(
            'Up to three per ingredient. Deselect another candidate first.'),
        findsOneWidget);
    expect(
        tester
            .widget<CheckboxListTile>(
                find.byKey(const Key('guide-candidate-carrot-C')))
            .value,
        isFalse);
    await tapVisible(tester, 'guide-candidate-carrot-D');
    await tapVisible(tester, 'guide-candidate-carrot-C');
    expect(
        tester
            .widget<CheckboxListTile>(
                find.byKey(const Key('guide-candidate-carrot-C')))
            .value,
        isTrue);
    expect(
        tester
            .widget<CheckboxListTile>(
                find.byKey(const Key('guide-candidate-tofu-D')))
            .value,
        isTrue);
    await tapVisible(tester, 'guide-skip');
    await tapVisible(tester, 'guide-try-example');
    final cheapest = find.text('Lowest purchase price');
    await tester.ensureVisible(cheapest);
    await tester.tap(cheapest);
    await tester.pumpAndSettle();
    expect(find.textContaining('KRW 8,000'), findsOneWidget);
    expect(find.textContaining('Requests: 2'), findsOneWidget);
    await tapVisible(tester, 'guide-skip');
    await tapVisible(tester, 'guide-try-example');
    await tester.enterText(find.byType(TextField), 'Training buyer');
    final review =
        find.text('Confirm quantities, supplier and desired delivery date');
    await tester.ensureVisible(review);
    await tester.tap(review);
    await tester.pumpAndSettle();
    final preview = find.text('Preview example');
    await tester.ensureVisible(preview);
    await tester.tap(preview);
    await tester.pumpAndSettle();
    expect(find.textContaining('Sample supplier B'), findsOneWidget);
    expect(find.textContaining('Sample supplier C'), findsOneWidget);
    expect(find.textContaining('Training buyer'), findsWidgets);
  });
  testWidgets('buying and cooking practice tracks survive switching courses',
      (tester) async {
    await showGuide(tester, 'en', lesson: 'buy-compare');
    await tapVisible(tester, 'guide-overview');
    await tapVisible(tester, 'guide-audience-home');
    await tapVisible(tester, 'guide-continue');
    await tapVisible(tester, 'guide-overview');
    await tapVisible(tester, 'guide-audience-professional');
    expect(
        tester
            .widget<ChoiceChip>(find.byKey(const Key('guide-track-purchasing')))
            .selected,
        isTrue);
  });
  testWidgets(
      'supplier publication exercise requires review and never writes business records',
      (tester) async {
    await showGuide(tester, 'en', lesson: 'supplier-publish');
    await tapVisible(tester, 'guide-try-example');
    final practice = find.text('Practice publication');
    await tester.ensureVisible(practice);
    await tester.tap(practice);
    await tester.pumpAndSettle();
    expect(find.text('Review the public information first.'), findsOneWidget);
    final review =
        find.text('Review sample profile, product photo and pack size');
    await tester.ensureVisible(review);
    await tester.tap(review);
    await tester.pumpAndSettle();
    await tester.ensureVisible(practice);
    await tester.tap(practice);
    await tester.pumpAndSettle();
    expect(
        find.textContaining('No real listing was published.'), findsOneWidget);
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getKeys().every((k) => k.startsWith('guide_')), isTrue);
    await tapVisible(tester, 'guide-complete');
    expect(prefs.getStringList(GuideProgress.storageKey),
        contains('supplier-publish.done'));
  });
  testWidgets('real work navigation returns to the same lesson and checklist',
      (tester) async {
    final router = GoRouter(initialLocation: '/guide', routes: [
      GoRoute(
          path: '/guide',
          builder: (_, __) =>
              const ProductGuidePage(initialLesson: 'pro-standard')),
      GoRoute(
          path: '/my-recipes',
          builder: (context, _) => Scaffold(
              body: TextButton(
                  onPressed: () => context.pop(), child: const Text('Return'))))
    ]);
    addTearDown(router.dispose);
    await tester.pumpWidget(MaterialApp.router(routerConfig: router));
    await tester.pumpAndSettle();
    await tapVisible(tester, 'guide-step-0');
    await tapVisible(tester, 'guide-practice');
    await tester.tap(find.text('Return'));
    await tester.pumpAndSettle();
    expect(
        tester
            .widget<CheckboxListTile>(find.byKey(const Key('guide-step-0')))
            .value,
        isTrue);
  });
  testWidgets(
      'context help appears over an editor and back preserves its unsaved input',
      (tester) async {
    final controller = TextEditingController(text: 'Unsaved order');
    addTearDown(controller.dispose);
    final router = GoRouter(routes: [
      ShellRoute(builder: (_, __, child) => child, routes: [
        GoRoute(
            path: '/',
            builder: (context, _) => Scaffold(
                body: TextButton(
                    child: const Text('Edit'),
                    onPressed: () => showDialog<void>(
                        context: context,
                        builder: (dialogContext) => Dialog.fullscreen(
                            child: Scaffold(
                                appBar: AppBar(actions: const [
                                  GuideHelpButton(lesson: 'buy-request')
                                ]),
                                body: TextField(controller: controller)))))))
      ]),
      GoRoute(
          path: '/guide',
          builder: (_, state) => ProductGuidePage(
              initialLesson: state.uri.queryParameters['lesson']))
    ]);
    addTearDown(router.dispose);
    await tester.pumpWidget(MaterialApp.router(routerConfig: router));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Edit'));
    await tester.pumpAndSettle();
    await tester.tap(find.byType(GuideHelpButton));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('guide-try-example')), findsOneWidget);
    expect(find.byType(TextField), findsNothing);
    await tester.tap(find.byIcon(Icons.arrow_back));
    await tester.pumpAndSettle();
    expect(find.byType(TextField), findsOneWidget);
    expect(controller.text, 'Unsaved order');
    expect(find.byKey(const Key('guide-try-example')), findsNothing);
  });
  testWidgets(
      'explicit role overrides saved role and invalid lesson opens overview',
      (tester) async {
    SharedPreferences.setMockInitialValues({
      GuideProgress.audienceKey: 'home',
      GuideProgress.storageKey: ['home-search.done']
    });
    await showGuide(tester, 'en',
        audience: GuideAudience.professional, lesson: 'invalid');
    expect(find.textContaining('0 / 14'), findsOneWidget);
    await tapVisible(tester, 'guide-audience-home');
    expect(find.textContaining('1 / 5'), findsOneWidget);
  });
}
