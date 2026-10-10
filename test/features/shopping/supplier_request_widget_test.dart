import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:k_youtube/features/guide/presentation/guide_help_button.dart';
import 'package:k_youtube/features/guide/presentation/product_guide_page.dart';
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:k_youtube/core/theme/app_theme.dart';
import 'package:k_youtube/features/auth/application/auth_providers.dart';
import 'package:k_youtube/features/kitchen/application/kitchen_providers.dart';
import 'package:k_youtube/features/shopping/application/supplier_request_share.dart';
import 'package:k_youtube/features/shopping/data/supplier_request_repository.dart';
import 'package:k_youtube/features/shopping/data/shopping_assistant_repository.dart';
import 'package:k_youtube/features/shopping/domain/supplier_request.dart';
import 'package:k_youtube/features/shopping/presentation/supplier_requests_page.dart';
import 'package:k_youtube/features/shopping/presentation/supplier_request_editor.dart';
import 'package:k_youtube/features/shopping/presentation/shopping_assistant_dialogs.dart';
import 'supplier_request_test.dart' show sampleRequest, sampleSupplier;

User user(String id) => User(
    id: id,
    appMetadata: {},
    userMetadata: {},
    aud: 'authenticated',
    createdAt: '2026-09-13');

class RequestRepo extends SupplierRequestRepository {
  final rows = [sampleRequest()];
  final saves = <SupplierRequest>[];
  final directory = [sampleSupplier];
  bool failOnce = false;
  @override
  Future<SupplierRequest?> request(String id) async =>
      rows.where((r) => r.id == id).firstOrNull;
  @override
  Future<List<SupplierRequest>> requests({int limit = 50}) async =>
      rows.take(limit).toList();
  @override
  Future<List<ShoppingSupplier>> suppliers() async => directory;
  @override
  Future<void> saveSupplier(ShoppingSupplier s,
      {required bool existing}) async {
    directory.removeWhere((v) => v.id == s.id);
    directory.add(s);
  }

  @override
  Future<void> deleteSupplier(String id) async =>
      directory.removeWhere((s) => s.id == id);
  @override
  Future<void> deleteDraft(SupplierRequest r) async {
    if (r.status != 'draft') throw StateError('Used');
    rows.removeWhere((row) => row.id == r.id && row.revision == r.revision);
  }

  @override
  Future<void> deleteRequest(String id) async =>
      rows.removeWhere((r) => r.id == id);
  @override
  Future<SupplierRequest> save(SupplierRequest r, {String? status}) async {
    saves.add(r);
    if (failOnce) {
      failOnce = false;
      throw TimeoutException('uncertain');
    }
    final result = SupplierRequest.fromJson({
      'id': r.id,
      'data': r.data,
      'revision': r.revision + 1,
      'status': status ?? r.status,
      'created_at': '2026-09-13T00:00:00Z'
    });
    rows.removeWhere((v) => v.id == r.id);
    rows.insert(0, result);
    return result;
  }
}

Future<void> pumpRequest(
    WidgetTester tester, RequestRepo repo, List<bool> shares,
    {String language = 'ko',
    List<Override> overrides = const [],
    GoRouter? router,
    Stream<User?>? users,
    Widget? home,
    List<Uri>? opened}) async {
  tester.view.physicalSize = const Size(360, 800);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(ProviderScope(
      overrides: [
        authUserProvider.overrideWith((_) => users ?? Stream.value(user('A'))),
        supplierRequestRepositoryProvider.overrideWithValue(repo),
        shoppingLinkLauncherProvider.overrideWithValue((uri) async {
          opened?.add(uri);
          return true;
        }),
        kitchenShoppingListsProvider.overrideWith((_) async => []),
        ...overrides,
        supplierRequestShareProvider.overrideWithValue((request,
            {required english,
            required pdf,
            required origin,
            required accountStillActive}) async {
          expect(accountStillActive(), isTrue);
          expect(origin.isEmpty, isFalse);
          shares.add(pdf);
        }),
      ],
      child: router != null
          ? Consumer(builder: (_, ref, __) {
              ref.watch(authUserProvider);
              return MaterialApp.router(
                  theme: AppTheme.light, routerConfig: router);
            })
          : MaterialApp(
              theme: AppTheme.light,
              locale: Locale(language),
              supportedLocales: const [Locale('ko'), Locale('en')],
              localizationsDelegates: const [
                GlobalMaterialLocalizations.delegate,
                GlobalWidgetsLocalizations.delegate,
                GlobalCupertinoLocalizations.delegate
              ],
              builder: (context, child) => MediaQuery(
                  data: MediaQuery.of(context)
                      .copyWith(textScaler: const TextScaler.linear(1.15)),
                  child: child!),
              home: Consumer(builder: (context, ref, _) {
                ref.watch(authUserProvider);
                return home ?? const SupplierRequestsPage();
              }))));
  await tester.pumpAndSettle();
}

Future<void> show(WidgetTester tester, Finder finder) async {
  if (finder.evaluate().isEmpty) {
    await tester.scrollUntilVisible(finder, 250,
        scrollable: find
            .descendant(
                of: find.byType(ListView).last,
                matching: find.byType(Scrollable))
            .first);
  }
  await tester.ensureVisible(finder);
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('request editor help returns without discarding or saving edits',
      (tester) async {
    SharedPreferences.setMockInitialValues({});
    final repo = RequestRepo();
    final router = GoRouter(routes: [
      ShellRoute(builder: (_, __, child) => child, routes: [
        GoRoute(
            path: '/',
            builder: (context, _) => Scaffold(
                body: TextButton(
                    child: const Text('Open'),
                    onPressed: () => showDialog<SupplierRequest>(
                        context: context,
                        builder: (_) => ShoppingAccountGuard(
                            child: SupplierRequestEditor(
                                suppliers: const [sampleSupplier],
                                groups: const [],
                                request: sampleRequest()))))))
      ]),
      GoRoute(
          path: '/guide',
          builder: (_, state) => ProductGuidePage(
              initialLesson: state.uri.queryParameters['lesson']))
    ]);
    addTearDown(router.dispose);
    await pumpRequest(tester, repo, [], router: router);
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();
    final field = find.byType(TextFormField).first;
    await tester.ensureVisible(field);
    await tester.enterText(field, 'Tutorial return test');
    await tester.pumpAndSettle();
    final help = find.descendant(
        of: find.byType(AppBar), matching: find.byType(GuideHelpButton));
    expect(help, findsOneWidget);
    await tester.tap(help);
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('guide-try-example')), findsOneWidget);
    await tester.tap(find.byIcon(Icons.arrow_back));
    await tester.pumpAndSettle();
    expect(find.byType(SupplierRequestEditor), findsOneWidget);
    expect(
        tester
            .widget<TextFormField>(find.byType(TextFormField).first)
            .controller!
            .text,
        'Tutorial return test');
    expect(repo.saves, isEmpty);
    expect(tester.takeException(), isNull);
  });

  testWidgets('repeating a deleted supplier requires an explicit replacement',
      (tester) async {
    final repo = RequestRepo();
    await pumpRequest(tester, repo, [],
        home: Builder(
            builder: (context) => Scaffold(
                body: TextButton(
                    child: const Text('Open'),
                    onPressed: () => showDialog<SupplierRequest>(
                        context: context,
                        builder: (_) => ShoppingAccountGuard(
                                child: SupplierRequestEditor(
                                    suppliers: const [
                                  ShoppingSupplier(
                                      id: 'different', name: 'Another supplier')
                                ],
                                    groups: const [],
                                    request: sampleRequest().repeat())))))));
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('저장하고 미리보기'));
    await tester.pumpAndSettle();
    expect(repo.saves, isEmpty);
    expect(find.text('협력업체를 선택해 주세요.'), findsWidgets);
    expect(find.text('Another supplier'), findsNothing);
  });
  for (final language in ['ko', 'en']) {
    testWidgets(
        '$language narrow request shares text/PDF without status changes',
        (tester) async {
      final repo = RequestRepo();
      final shares = <bool>[];
      await pumpRequest(tester, repo, shares, language: language);
      await show(tester, find.text(sampleSupplier.name));
      await tester.tap(find.text(sampleSupplier.name));
      await tester.pumpAndSettle();
      await tester.tap(find.text(language == 'ko' ? '텍스트 공유' : 'Share text'));
      await tester.pumpAndSettle();
      await tester
          .tap(find.text(language == 'ko' ? 'PDF 파일 공유' : 'Share PDF file'));
      await tester.pumpAndSettle();
      expect(shares, [false, true]);
      expect(repo.saves, isEmpty);
      expect(repo.rows.single.status, 'draft');
      expect(tester.takeException(), isNull);
    });
  }
  testWidgets('only manual confirmation advances a request and freezes editing',
      (tester) async {
    final repo = RequestRepo();
    await pumpRequest(tester, repo, []);
    await show(tester, find.text(sampleSupplier.name));
    await tester.tap(find.text(sampleSupplier.name));
    await tester.pumpAndSettle();
    await show(tester, find.text('전달 확인'));
    await tester.tap(find.text('전달 확인'));
    await tester.pumpAndSettle();
    expect(repo.saves, isEmpty);
    await tester.tap(find.text('확인'));
    await tester.pumpAndSettle();
    expect(repo.rows.single.status, 'sent');
    expect(find.text('내용 수정'), findsNothing);
    expect(tester.takeException(), isNull);
  });
  testWidgets('account change dismisses private preview', (tester) async {
    final users = StreamController<User?>.broadcast();
    addTearDown(users.close);
    final repo = RequestRepo();
    await pumpRequest(tester, repo, [], users: users.stream);
    users.add(user('A'));
    await tester.pumpAndSettle();
    await show(tester, find.text(sampleSupplier.name));
    await tester.tap(find.text(sampleSupplier.name));
    await tester.pumpAndSettle();
    users.add(null);
    await tester.pumpAndSettle();
    expect(find.byType(SupplierRequestDetails), findsNothing);
    expect(find.textContaining('예시로'), findsNothing);
    expect(repo.saves, isEmpty);
  });
  testWidgets('uncertain draft retry preserves request id and snapshot',
      (tester) async {
    final repo = RequestRepo()..failOnce = true;
    await pumpRequest(tester, repo, [],
        home: Builder(
            builder: (context) => Scaffold(
                body: TextButton(
                    child: const Text('Open'),
                    onPressed: () => showDialog<SupplierRequest>(
                        context: context,
                        builder: (_) => ShoppingAccountGuard(
                            child: SupplierRequestEditor(
                                suppliers: const [sampleSupplier],
                                groups: const [],
                                request: sampleRequest().repeat())))))));
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('저장하고 미리보기'));
    await tester.pumpAndSettle();
    expect(repo.saves, hasLength(1));
    await tester.tap(find.text('저장하고 미리보기'));
    await tester.pumpAndSettle();
    expect(repo.saves, hasLength(2));
    expect(repo.saves[0].id, repo.saves[1].id);
    expect(repo.saves[0].data, repo.saves[1].data);
  });
  testWidgets('new request requires quantities for selected ingredients',
      (tester) async {
    final repo = RequestRepo();
    await pumpRequest(tester, repo, []);
    await tester.tap(find.text('새 구매요청'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('직접 작성'));
    await tester.pumpAndSettle();
    await tester.enterText(
        find.widgetWithText(TextFormField, '요청자 또는 사업장명'), '테스트 키친');
    await tester.tap(find.text('저장하고 미리보기'));
    await tester.pumpAndSettle();
    expect(repo.saves, isEmpty);
    await show(tester, find.text('품목 직접 추가'));
    await tester.tap(find.text('품목 직접 추가'));
    await tester.pumpAndSettle();
    await tester.enterText(find.widgetWithText(TextFormField, '재료명'), '두부');
    await tester.enterText(find.widgetWithText(TextFormField, '구매 요청 수량'), '2');
    await tester.enterText(
        find.widgetWithText(TextFormField, '구매 단위 (직접 입력 가능)'), '팩');
    tester.testTextInput.hide();
    await tester.pumpAndSettle();
    await tester.tap(find.text('확인'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('저장하고 미리보기'));
    await tester.pumpAndSettle();
    expect(repo.saves, hasLength(1));
    expect(repo.saves.single.lines.single.unit, '팩');
    expect(repo.saves.single.lines.single.quantity, 2);
    expect(find.byType(SupplierRequestDetails), findsOneWidget);
  });
}
