import 'dart:io';
import 'package:go_router/go_router.dart';
import 'dart:ui' as ui;
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:k_youtube/core/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:k_youtube/features/auth/application/auth_providers.dart';
import 'package:k_youtube/features/shopping/application/purchase_workspace.dart';
import 'package:k_youtube/features/shopping/domain/supplier_request.dart';
import 'package:k_youtube/features/shopping/presentation/supplier_requests_page.dart';
import 'package:k_youtube/features/shopping/presentation/supplier_request_editor.dart';
import 'package:k_youtube/features/suppliers/application/procurement_session.dart';
import 'package:k_youtube/features/workspace/domain/workspace_profile.dart';
import 'package:k_youtube/features/workspace/presentation/workspace_menu.dart';
import 'supplier_request_widget_test.dart' show pumpRequest, RequestRepo, show;
import 'supplier_request_test.dart' show sampleRequest;

void main() {
  testWidgets(
      'professional purchasing opens the preparation flow with its selected list',
      (tester) async {
    String? list;
    final router = GoRouter(routes: [
      GoRoute(
          path: '/',
          builder: (_, __) => const SupplierRequestsPage(listId: 'my-list')),
      GoRoute(
          path: '/shopping-preparation',
          builder: (_, state) {
            list = state.uri.queryParameters['list'];
            return const Scaffold(body: Text('준비 화면'));
          }),
    ]);
    addTearDown(router.dispose);
    await pumpRequest(tester, RequestRepo(), [], router: router);
    final start = find.byKey(const Key('professional-shopping-preparation'));
    await tester.ensureVisible(start);
    await tester.tap(start);
    await tester.pumpAndSettle();
    expect(find.text('준비 화면'), findsOneWidget);
    expect(list, 'my-list');
  });
  setUpAll(() async {
    await (FontLoader('RecipeScoutKR')
          ..addFont(rootBundle.load('assets/fonts/NanumGothic-Regular.ttf')))
        .load();
    await (FontLoader('MaterialIcons')
          ..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf')))
        .load();
  });
  for (final locale in ['ko', 'en']) {
    for (final width in [390.0, 1440.0]) {
      testWidgets(
          '$locale purchasing stays readable at $width and narrow width',
          (tester) async {
        final key = GlobalKey();
        await pumpRequest(tester, RequestRepo(), [],
            language: locale,
            home: RepaintBoundary(
                key: key,
                child: Theme(
                    data: AppTheme.light.copyWith(
                        filledButtonTheme: FilledButtonThemeData(
                            style: AppTheme.light.filledButtonTheme.style?.copyWith(
                                textStyle: WidgetStatePropertyAll(AppTheme
                                    .light.textTheme.labelLarge
                                    ?.copyWith(
                                        fontFamily: 'RecipeScoutKR',
                                        fontWeight: FontWeight.w700)))),
                        chipTheme: AppTheme.light.chipTheme.copyWith(
                            labelStyle: AppTheme.light.textTheme.labelMedium
                                ?.copyWith(fontFamily: 'RecipeScoutKR')),
                        textTheme: AppTheme.light.textTheme.apply(fontFamily: 'RecipeScoutKR'),
                        appBarTheme: AppTheme.light.appBarTheme.copyWith(titleTextStyle: AppTheme.light.appBarTheme.titleTextStyle?.copyWith(fontFamily: 'RecipeScoutKR'))),
                    child: const SupplierRequestsPage())));
        tester.view.physicalSize = Size(width, 1000);
        await tester.pumpAndSettle();
        expect(find.byKey(const Key('new-purchase-request')).hitTestable(),
            findsOneWidget);
        expect(
            find
                .byKey(const ValueKey('purchase-stage-preparing'))
                .hitTestable(),
            findsOneWidget);
        expect(tester.takeException(), isNull);
        final output = Platform.environment['SCOUT_PURCHASE_PREVIEW'];
        if (output != null) {
          await tester.runAsync(() async {
            final boundary = key.currentContext!.findRenderObject()!
                as RenderRepaintBoundary;
            final image = await boundary.toImage(pixelRatio: 1);
            final bytes =
                await image.toByteData(format: ui.ImageByteFormat.png);
            await Directory(output).create(recursive: true);
            await File('$output/purchasing-$locale-${width.toInt()}.png')
                .writeAsBytes(bytes!.buffer.asUint8List());
            image.dispose();
          });
        }
        tester.view.physicalSize = const Size(320, 720);
        // Use an explicit Theme wrapper above; system large-text behavior is covered
        // by the role navigation tests, while all purchase controls remain scrollable.
        await tester.pumpAndSettle();
        await show(
            tester, find.byKey(const ValueKey('purchase-stage-completed')));
        expect(tester.takeException(), isNull);
      });
    }
  }

  test('purchase stages preserve cancellation and search by item and reference',
      () {
    final draft = sampleRequest();
    final sent = SupplierRequest(
        id: 'sent',
        supplier: draft.supplier,
        lines: draft.lines,
        status: 'sent');
    final cancelled = SupplierRequest(
        id: 'cancelled',
        supplier: draft.supplier,
        lines: draft.lines,
        status: 'cancelled');
    expect(
        purchaseRequestsForStage(
            [draft, sent, cancelled], PurchaseStage.preparing),
        [draft]);
    expect(
        purchaseRequestsForStage([draft, sent, cancelled], PurchaseStage.active,
            query: draft.lines.first.name),
        [sent]);
    expect(
        purchaseRequestsForStage(
            [draft, sent, cancelled], PurchaseStage.completed,
            query: 'PO-CANCELLED'),
        [cancelled]);
    expect(
        purchaseRequestsForStage([draft], PurchaseStage.preparing,
            query: 'no match'),
        isEmpty);
  });

  test('all spaces use four primary destinations with task section selection',
      () {
    expect(primaryWorkspaceLinks(WorkspaceMode.personal).map((l) => l.ko),
        ['레시피 찾기', '레시피 보관함', '장보기', '더보기']);
    expect(primaryWorkspaceLinks(WorkspaceMode.professional).map((l) => l.ko),
        ['레시피 찾기', '레시피 보관함', '장보기', '더보기']);
    expect(primaryWorkspaceLinks(WorkspaceMode.supplier).map((l) => l.ko),
        ['홈', '상품·가격', '거래조건', '더보기']);
    for (final path in [
      '/supplier-requests',
      '/supplier-request-ledger',
      '/supplier-plan',
      '/kitchen'
    ]) {
      expect(
          workspaceSectionPath(path, WorkspaceMode.professional), '/shopping');
    }
    expect(workspaceStartPath(WorkspaceMode.personal), '/');
    expect(workspaceSectionPath('/supplier-plan', WorkspaceMode.personal),
        '/shopping');
    expect(workspaceSectionPath('/my-recipes', WorkspaceMode.professional),
        '/my-recipes');
  });

  test('incomplete forms and candidate sessions clear on account changes', () {
    final account = StateProvider<String?>((_) => 'buyer-a');
    final container = ProviderContainer(overrides: [
      activeAccountIdProvider.overrideWith((ref) => ref.watch(account)),
    ]);
    addTearDown(container.dispose);
    final draft = sampleRequest();
    container.read(requestEditCheckpointsProvider.notifier).state = {
      draft.id:
          RequestEditCheckpoint(request: draft, suppliers: [draft.supplier])
    };
    container.read(procurementSessionsProvider)['all'] = ProcurementSession([]);
    expect(container.read(requestEditCheckpointsProvider), isNotEmpty);
    container.read(account.notifier).state = 'buyer-b';
    expect(container.read(requestEditCheckpointsProvider), isEmpty);
    expect(container.read(procurementSessionsProvider), isEmpty);
    container.read(account.notifier).state = 'buyer-a';
    expect(container.read(requestEditCheckpointsProvider), isEmpty);
    expect(container.read(procurementSessionsProvider), isEmpty);
  });

  testWidgets('request lookup opens a request outside the first page directly',
      (tester) async {
    final repo = RequestRepo();
    final first = sampleRequest();
    repo.rows.addAll(List.generate(
        60,
        (i) => SupplierRequest(
            id: 'older-$i',
            supplier: first.supplier,
            lines: first.lines,
            buyer: 'Older buyer $i')));
    await pumpRequest(tester, repo, [],
        home: const SupplierRequestsPage(requestId: 'older-59'));
    expect(find.byType(SupplierRequestDetails), findsOneWidget);
    expect(find.textContaining('Older buyer 59'), findsOneWidget);
    expect(repo.saves, isEmpty);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'incomplete request closes and resumes without forcing server validation',
      (tester) async {
    final repo = RequestRepo();
    await pumpRequest(tester, repo, []);
    await tester.tap(find.byKey(const Key('new-purchase-request')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('직접 작성'));
    await tester.pumpAndSettle();
    final buyer = find.widgetWithText(TextFormField, '요청자 또는 사업장명');
    await show(tester, buyer);
    await tester.enterText(buyer, '이어 쓸 주방');
    tester.testTextInput.hide();
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('나중에 계속'));
    await tester.pumpAndSettle();
    expect(find.byType(SupplierRequestEditor), findsNothing);
    final resume = find.text('이어서 작성 · 현재 앱에서 임시 보관');
    await show(tester, resume);
    await tester.tap(resume);
    await tester.pumpAndSettle();
    await show(tester, buyer);
    expect(tester.widget<TextFormField>(buyer).controller!.text, '이어 쓸 주방');
    expect(repo.saves, isEmpty);
    await tester.tap(find.text('변경 버리기'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, '변경 버리기'));
    await tester.pumpAndSettle();
    expect(find.byType(SupplierRequestEditor), findsNothing);
    expect(find.text('이어서 작성 · 현재 앱에서 임시 보관'), findsNothing);
    expect(repo.rows, hasLength(1));
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'completed and in progress requests remain separate in purchasing',
      (tester) async {
    final repo = RequestRepo();
    final first = sampleRequest();
    repo.rows.addAll([
      SupplierRequest(
          id: 'active',
          supplier: const ShoppingSupplier(id: 'active-s', name: '진행 업체'),
          lines: first.lines,
          status: 'accepted'),
      SupplierRequest(
          id: 'done',
          supplier: const ShoppingSupplier(id: 'done-s', name: '완료 업체'),
          lines: first.lines,
          status: 'received'),
    ]);
    await pumpRequest(tester, repo, []);
    await show(tester, find.byKey(const ValueKey('purchase-stage-active')));
    await tester.tap(find.byKey(const ValueKey('purchase-stage-active')));
    await tester.pumpAndSettle();
    await show(tester, find.text('진행 업체'));
    expect(find.text('완료 업체'), findsNothing);
    await show(tester, find.byKey(const ValueKey('purchase-stage-completed')));
    await tester.tap(find.byKey(const ValueKey('purchase-stage-completed')));
    await tester.pumpAndSettle();
    await show(tester, find.text('완료 업체'));
    expect(find.text('진행 업체'), findsNothing);
    expect(tester.takeException(), isNull);
  });
}
