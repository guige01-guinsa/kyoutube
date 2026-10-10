import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:k_youtube/features/business/data/business_meal_repository.dart';
import 'package:k_youtube/features/business/data/business_menu_fast_repository.dart';
import 'package:k_youtube/features/business/domain/business_meal.dart';
import 'package:k_youtube/features/business/domain/business_navigation.dart';
import 'business_flow_test.dart' show MemoryBusiness, pumpBusiness;
import 'business_menu_fast_test.dart' show FastMemory;

BusinessMeal mealFixture(
        {String status = 'draft', String id = 'meal', DateTime? day}) =>
    BusinessMeal({
      'id': id,
      'workspace_id': 'shop',
      'meal_date': mealDate(day ?? DateTime.now()),
      'title': '계절 점심 한 상',
      'slot': '점심',
      'notes': '국의 염도를 확인하세요.',
      'status': status,
      'revision': 2,
      'sources': [
        {'kind': 'recipe', 'id': 'recipe', 'revision': 1, 'servings': 30}
      ],
      'snapshot': {
        'sources': [
          {
            'kind': 'recipe',
            'id': 'recipe',
            'revision': 1,
            'recipe_revision': 1,
            'title': '봄나물 비빔밥',
            'servings': 30,
            'recipe': {
              'title': '봄나물 비빔밥',
              'data': {'steps': '나물을 준비해 밥 위에 올립니다.'}
            }
          }
        ],
        'requirements': [
          {
            'key': 'onion',
            'name': '양파',
            'spec': '',
            'required': 1500,
            'unit': 'g'
          }
        ]
      }
    });

class MealMemory implements BusinessMealRepository {
  @override
  dynamic noSuchMethod(Invocation i) => super.noSuchMethod(i);
  final rows = <BusinessMeal>[];
  final copies = <Map<String, dynamic>>[], saves = <Map<String, dynamic>>[];
  final linksData = <Map<String, dynamic>>[];
  bool uncertain = false;
  @override
  Future<List<BusinessMeal>> list(
          String w, DateTime start, DateTime end) async =>
      rows
          .where((m) => !m.date.isBefore(start) && !m.date.isAfter(end))
          .toList();
  @override
  Future<List<Map<String, dynamic>>> links(String w) async => linksData;
  @override
  Future<void> copy(Map<String, dynamic> p) async {
    copies.add(Map.of(p));
    if (uncertain && copies.length == 1) {
      throw const SocketException('response lost');
    }
  }

  @override
  Future<void> save(Map<String, dynamic> p) async {
    saves.add(Map.of(p));
    if (uncertain && saves.length == 1) {
      throw const SocketException('response lost');
    }
  }

  @override
  Future<void> transition(String w, BusinessMeal m, String status) async {
    rows[rows.indexOf(m)] =
        BusinessMeal({...m.json, 'status': status, 'revision': m.revision + 1});
  }

  @override
  Future<List<Map<String, dynamic>>> recipes(
          String w, String query, int offset) async =>
      offset > 0
          ? []
          : [
              {'id': 'recipe', 'title': '봄나물 비빔밥', 'revision': 1, 'data': {}}
            ];
  @override
  Future<List<Map<String, dynamic>>> history(String w, String id) async => [
        {
          'revision': 2,
          'created_at': '2026-09-25T00:00:00Z',
          'snapshot': rows.first.json
        }
      ];
}

const permissions = {
  'recipes.read',
  'recipes.write',
  'purchasing.read',
  'purchasing.write',
  'menus.approve'
};
Future<void> visibleTap(WidgetTester t, Finder f) async {
  await t.ensureVisible(f.first);
  await t.tap(f.first);
  await t.pumpAndSettle();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() async {
    await (FontLoader('BusinessPreview')
          ..addFont(rootBundle.load('assets/fonts/NanumGothic-Regular.ttf')))
        .load();
    await (FontLoader('MaterialIcons')
          ..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf')))
        .load();
  });
  test('calendar week crosses months and years without time components', () {
    expect(mealWeek(DateTime(2027, 1, 1, 23)), DateTime(2026, 12, 28));
    expect(mealDate(mealDay(DateTime(2026, 9, 25, 18))), '2026-09-25');
    expect(
        businessLocationSection(Uri.parse('/business-workspaces/shop/meals')),
        BusinessSection.recipes);
  });
  testWidgets('mobile calendar and editor fit enlarged text', (t) async {
    final meals = MealMemory()..rows.add(mealFixture());
    await pumpBusiness(t, MemoryBusiness(permissions),
        initial: '/business-workspaces/shop/meals',
        width: 360,
        textScale: 1.4,
        overrides: [businessMealRepositoryProvider.overrideWithValue(meals)]);
    expect(find.text('식단 달력'), findsOneWidget);
    expect(t.takeException(), isNull);
    await visibleTap(t, find.text('식단 추가'));
    expect(find.text('식단 작성'), findsOneWidget);
    expect(t.takeException(), isNull);
    await t.pumpWidget(const SizedBox());
  });
  testWidgets(
      'draft editor saves selected recipe and servings; uncertain retry keeps identity',
      (t) async {
    final meals = MealMemory()..uncertain = true;
    await pumpBusiness(t, MemoryBusiness(permissions),
        initial: '/business-workspaces/shop/meals',
        width: 900,
        overrides: [businessMealRepositoryProvider.overrideWithValue(meals)]);
    await visibleTap(t, find.text('식단 추가'));
    await visibleTap(t, find.text('점심'));
    final fields = find.byType(TextFormField);
    await t.enterText(fields.at(1), '점심 식단');
    await visibleTap(t, find.text('공동 레시피 추가'));
    await visibleTap(t, find.text('봄나물 비빔밥'));
    await t.enterText(find.byType(TextFormField).at(2), '25');
    await visibleTap(t, find.text('초안 저장'));
    expect(meals.saves.single['p_sources'], [
      {'kind': 'recipe', 'id': 'recipe', 'revision': 1, 'servings': 25.0}
    ]);
    await visibleTap(t, find.text('같은 요청 재확인'));
    expect(meals.saves[0], meals.saves[1]);
    expect(find.text('식단 작성'), findsNothing);
    expect(t.takeException(), isNull);
    await t.pumpWidget(const SizedBox());
  });
  testWidgets(
      'copy dialog preserves request identity after an uncertain response',
      (t) async {
    final meals = MealMemory()
      ..rows.add(mealFixture())
      ..uncertain = true;
    await pumpBusiness(t, MemoryBusiness(permissions),
        initial: '/business-workspaces/shop/meals',
        width: 900,
        overrides: [businessMealRepositoryProvider.overrideWithValue(meals)]);
    await visibleTap(t, find.text('이 기간 복사'));
    await visibleTap(t, find.text('복사'));
    await visibleTap(t, find.text('복사'));
    expect(meals.copies.length, 2);
    expect(meals.copies[0], meals.copies[1]);
    expect(t.takeException(), isNull);
    await t.pumpWidget(const SizedBox());
  });
  testWidgets(
      'cook can draft but cannot confirm; manager can confirm without write permission',
      (t) async {
    final meals = MealMemory()..rows.add(mealFixture());
    await pumpBusiness(t, MemoryBusiness({'recipes.read', 'recipes.write'}),
        initial: '/business-workspaces/shop/meals',
        width: 1400,
        overrides: [businessMealRepositoryProvider.overrideWithValue(meals)]);
    expect(find.text('식단 확정'), findsNothing);
    expect(find.text('식단 추가'), findsOneWidget);
    await t.pumpWidget(const SizedBox());
    await pumpBusiness(t, MemoryBusiness({'recipes.read', 'menus.approve'}),
        initial: '/business-workspaces/shop/meals',
        width: 1400,
        overrides: [businessMealRepositoryProvider.overrideWithValue(meals)]);
    expect(find.text('식단 추가'), findsNothing);
    await visibleTap(t, find.text('식단 확정'));
    await visibleTap(t, find.text('확인'));
    expect(meals.rows.single.status, 'confirmed');
    await t.pumpWidget(const SizedBox());
  });
  testWidgets(
      'confirmed selection enters purchasing with immutable meal source',
      (t) async {
    final meals = MealMemory()..rows.add(mealFixture(status: 'confirmed'));
    final fast = FastMemory();
    await pumpBusiness(t, MemoryBusiness(permissions),
        initial: '/business-workspaces/shop/meals',
        width: 1400,
        overrides: [
          businessMealRepositoryProvider.overrideWithValue(meals),
          businessMenuFastRepositoryProvider.overrideWithValue(fast)
        ]);
    await visibleTap(t, find.text('구매 준비에 포함'));
    await visibleTap(t, find.text('선택 식단 구매 준비 (1/20)'));
    expect(find.text('확정 식단 구매 준비'), findsWidgets);
    await visibleTap(t, find.text('재료·구매량 계산'));
    expect(find.text('구매 기준·수량 확인'), findsOneWidget);
    expect(t.takeException(), isNull);
    await t.pumpWidget(const SizedBox());
  });
  testWidgets('linked meals cannot be selected a second time', (t) async {
    final meals = MealMemory()
      ..rows.add(mealFixture(status: 'confirmed'))
      ..linksData.add({'meal_id': 'meal', 'batch_id': 'batch'});
    await pumpBusiness(t, MemoryBusiness(permissions),
        initial: '/business-workspaces/shop/meals',
        width: 1400,
        overrides: [businessMealRepositoryProvider.overrideWithValue(meals)]);
    expect(find.text('구매 준비에 포함'), findsNothing);
    expect(find.text('구매 준비 내역'), findsOneWidget);
    await t.pumpWidget(const SizedBox());
  });
  testWidgets('desktop weekly calendar screenshot and English layout',
      (t) async {
    final meals = MealMemory();
    final week = mealWeek(DateTime.now());
    for (var i = 0; i < 7; i++) {
      meals.rows.add(mealFixture(
          id: 'meal$i',
          day: DateTime(week.year, week.month, week.day + i),
          status: i < 2
              ? 'cooked'
              : i < 4
                  ? 'confirmed'
                  : 'draft'));
    }
    final key = GlobalKey();
    await pumpBusiness(t, MemoryBusiness(permissions),
        initial: '/business-workspaces/shop/meals',
        width: 1440,
        capture: key,
        overrides: [businessMealRepositoryProvider.overrideWithValue(meals)]);
    expect(t.takeException(), isNull);
    await t.runAsync(() async {
      final boundary =
          key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
      final image = await boundary.toImage(pixelRatio: 1);
      final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
      await File('.artifacts/meal-calendar-desktop.png')
          .writeAsBytes(bytes!.buffer.asUint8List());
      image.dispose();
    });
    await t.pumpWidget(const SizedBox());
    await pumpBusiness(t, MemoryBusiness(permissions),
        initial: '/business-workspaces/shop/meals',
        width: 390,
        capture: key,
        overrides: [businessMealRepositoryProvider.overrideWithValue(meals)]);
    expect(t.takeException(), isNull);
    await t.runAsync(() async {
      final boundary =
          key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
      final image = await boundary.toImage(pixelRatio: 1);
      final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
      await File('.artifacts/meal-calendar-mobile.png')
          .writeAsBytes(bytes!.buffer.asUint8List());
      image.dispose();
    });
    await t.pumpWidget(const SizedBox());
    await pumpBusiness(t, MemoryBusiness(permissions),
        initial: '/business-workspaces/shop/meals',
        width: 390,
        locale: 'en',
        overrides: [businessMealRepositoryProvider.overrideWithValue(meals)]);
    expect(find.text('Meal calendar'), findsOneWidget);
    expect(t.takeException(), isNull);
    await t.pumpWidget(const SizedBox());
  });
}
