import 'package:k_youtube/features/chef/data/chef_access.dart';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:k_youtube/core/localization/app_localizations.dart';
import 'package:k_youtube/core/theme/app_theme.dart';
import 'package:k_youtube/features/chef/data/chef_repository.dart';
import 'package:k_youtube/features/chef/domain/chef_recipe.dart';
import 'package:k_youtube/features/chef/presentation/chef_workbench_page.dart';
import 'package:k_youtube/features/recipes/domain/recipe.dart';

const capture = bool.fromEnvironment('CHEF_CAPTURE');

class MemoryChefRepository implements ChefRepository {
  MemoryChefRepository(this.document);
  ChefRecipe document;
  int revision = 1;
  bool conflict = false;
  final history = <ChefVersion>[];
  @override
  Future<ChefWorkspace?> load(String id) async =>
      ChefWorkspace(document, revision);
  @override
  Future<List<ChefVersion>> versions(String id, {int? beforeVersion}) async =>
      history.reversed
          .where((v) => beforeVersion == null || v.number < beforeVersion)
          .take(20)
          .toList(growable: false);
  @override
  Future<int> save(String id, ChefRecipe doc, int expected,
      {String? versionLabel, String versionNote = ''}) async {
    if (conflict || revision != expected) {
      throw StateError('CHEF_REVISION_CONFLICT');
    }
    document = ChefRecipe.fromJson(doc.toJson());
    if (versionLabel != null) {
      history.add(ChefVersion(
          number: history.length + 1,
          label: versionLabel,
          note: versionNote,
          createdAt: DateTime.utc(2026, 9, 12),
          document: ChefRecipe.fromJson(doc.toJson())));
    }
    return ++revision;
  }
}

ChefRecipe example(String lang) => ChefRecipe(
        title: lang == 'en' ? 'Roasted carrots' : '당근구이',
        baseServings: 4,
        targetServings: 10,
        extraCost: 1000,
        inputWeight: 1000,
        outputWeight: 750,
        steps: lang == 'en'
            ? 'Trim the carrots.\nRoast until tender.'
            : '당근을 손질합니다.\n부드러워질 때까지 굽습니다.',
        ingredients: [
          ChefIngredient(
              id: 'carrots',
              name: lang == 'en' ? 'Carrots' : '당근',
              quantity: 800,
              unit: ChefUnit.g,
              yieldPercent: 80,
              purchaseQuantity: 1,
              purchaseUnit: ChefUnit.kg,
              purchasePrice: 8000)
        ]);

Future<void> showChef(
    WidgetTester tester, String lang, MemoryChefRepository repo,
    {double scale = 1, bool paid = true}) async {
  await tester.pumpWidget(ProviderScope(
      overrides: [
        chefPaidAccessProvider.overrideWith((ref) async => paid),
        chefRepositoryProvider.overrideWithValue(repo),
      ],
      child: MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: AppTheme.light,
        locale: Locale(lang),
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
        home: ChefWorkbenchPage(
            recipeId: 'test',
            initialRecipe: Recipe(
                id: 'test',
                title: repo.document.title,
                ingredients: const ['Carrots 800 g'],
                steps: const ['Cook.'])),
      )));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('free workspace keeps scaling while hiding financial controls',
      (tester) async {
    await showChef(tester, 'en', MemoryChefRepository(example('en')),
        paid: false);
    expect(
        find.text(
            'Cost, pricing and sales tools require an active Business membership.'),
        findsOneWidget);
    expect(find.text('Quick price edit'), findsNothing);
    await tester.scrollUntilVisible(
        find.byKey(const ValueKey('chef-baseServings-1')), 250,
        scrollable: find
            .byWidgetPredicate(
                (w) => w is Scrollable && w.axisDirection == AxisDirection.down)
            .first);
    expect(find.byKey(const ValueKey('chef-baseServings-1')), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
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
    testWidgets(
        '$lang supports narrow screen large text and ingredient editing',
        (tester) async {
      tester.view.physicalSize = const Size(320, 800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final repo = MemoryChefRepository(example(lang));
      await showChef(tester, lang, repo, scale: 2);
      expect(tester.takeException(), isNull);
      final edit = find.text(lang == 'en' ? 'Edit ingredient' : '재료 수정');
      final vertical = find
          .byWidgetPredicate((widget) =>
              widget is Scrollable &&
              widget.axisDirection == AxisDirection.down)
          .first;
      for (var i = 0; i < 30 && edit.hitTestable().evaluate().isEmpty; i++) {
        await tester.drag(vertical, const Offset(0, -250));
        await tester.pumpAndSettle();
      }
      expect(edit.hitTestable(), findsOneWidget);
      await tester.tap(edit.hitTestable());
      await tester.pumpAndSettle();
      expect(find.byType(AlertDialog), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.tap(find.text(lang == 'en' ? 'Cancel' : '취소'));
      await tester.pumpAndSettle();
      await tester.tap(find.text(lang == 'en' ? 'Versions' : '버전 관리').first);
      await tester.pumpAndSettle();
      expect(
          find.text(
              lang == 'en' ? 'Save your first version.' : '첫 버전을 기록해 보세요.'),
          findsOneWidget);
      expect(tester.takeException(), isNull);
    });
    if (capture) {
      testWidgets('$lang chef visual capture', (tester) async {
        tester.view.physicalSize = const Size(420, 960);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        await showChef(tester, lang, MemoryChefRepository(example(lang)));
        await expectLater(find.byType(Scaffold),
            matchesGoldenFile('../../../.artifacts/chef-studio-$lang.png'));
      });
    }
  }
  testWidgets(
      'saves snapshots, compares changes and restores without overwriting history',
      (tester) async {
    tester.view.physicalSize = const Size(800, 1200);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final repo = MemoryChefRepository(example('en'));
    await repo.save('test', repo.document, 1, versionLabel: 'Original');
    final updated =
        ChefRecipe.fromJson({...repo.document.toJson(), 'targetServings': 20});
    await repo.save('test', updated, 2, versionLabel: 'Banquet');
    await showChef(tester, 'en', repo);
    await tester.tap(find.text('Versions').first);
    await tester.pumpAndSettle();
    expect(find.text('v2 · Banquet'), findsWidgets);
    await tester.tap(find.text('Restore to workspace').last);
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    final target = find.widgetWithText(TextFormField, '10');
    expect(target, findsOneWidget);
    await tester.tap(find.text('Save a version'));
    await tester.pumpAndSettle();
    await tester.enterText(
        find.byType(AlertDialog).evaluate().isNotEmpty
            ? find
                .descendant(
                    of: find.byType(AlertDialog),
                    matching: find.byType(TextFormField))
                .first
            : find.byType(TextFormField).first,
        'Restored');
    await tester.tap(find.descendant(
        of: find.byType(AlertDialog),
        matching: find.widgetWithText(FilledButton, 'Save a version')));
    await tester.pumpAndSettle();
    expect(repo.history.length, 3);
    expect(repo.history[1].document.targetServings, 20);
    expect(repo.history.last.document.targetServings, 10);
    expect(tester.takeException(), isNull);
  });
  testWidgets('save conflicts retain edits and show a reload action',
      (tester) async {
    final repo = MemoryChefRepository(example('en'))..conflict = true;
    await showChef(tester, 'en', repo);
    await tester.tap(find.text('Save work'));
    await tester.pumpAndSettle();
    expect(
        find.text(
            'This workspace changed elsewhere. Reload and review before saving.'),
        findsOneWidget);
    expect(find.text('Reload'), findsOneWidget);
  });
}
