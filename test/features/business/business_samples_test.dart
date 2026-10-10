import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:k_youtube/features/auth/application/auth_providers.dart';
import 'package:k_youtube/features/business/domain/business_workspace.dart';
import 'package:k_youtube/features/business/presentation/business_pages.dart';
import 'business_flow_test.dart' show MemoryBusiness, pumpBusiness;

class SampleBusiness extends MemoryBusiness {
  SampleBusiness() : super(businessPermissions.toSet());
  bool existing = true, available = true;
  int starts = 0, resets = 0, ends = 0, deletes = 0;
  Completer<void>? endWait, startWait;
  @override
  Future<List<Map<String, dynamic>>> testOptions({bool admin = false}) async =>
      [
        {
          'id': 'campaign',
          'name': '20개 업소 업무 테스트',
          'ends_at': '2026-12-31T12:00:00Z',
          'available': available,
          'workspace_id': existing ? 'shop' : null,
          'generation': 1,
          'ended': !available,
          'closed': !available,
          'audience': 'selected',
          'workspaces': deletes > 0 ? 0 : 3,
          'records': deletes > 0 ? 0 : 60,
          'participants': [
            {'id': 'staff', 'email': 'tester@example.test', 'active': true}
          ]
        }
      ];
  @override
  Future<String> startTest(
      String campaign, String language, String display) async {
    starts++;
    if (startWait != null) await startWait!.future;
    return 'shop';
  }

  @override
  Future<void> resetTest(String workspace, int generation) async {
    resets++;
  }

  @override
  Future<void> endTest(String campaign) async {
    ends++;
    if (endWait != null) await endWait!.future;
    available = false;
  }

  @override
  Future<int> cleanupTest(String campaign) async {
    deletes++;
    return 0;
  }
}

Future<void> reveal(WidgetTester tester, Finder finder) async {
  await tester.scrollUntilVisible(finder, 400,
      scrollable: find.byType(Scrollable).first);
  await tester.pumpAndSettle();
  expect(finder.hitTestable(), findsOneWidget);
  await tester.tap(finder);
  await tester.pumpAndSettle();
}

void main() {
  setUpAll(() async {
    await (FontLoader('BusinessPreview')
          ..addFont(rootBundle.load('assets/fonts/NanumGothic-Regular.ttf')))
        .load();
    await (FontLoader('MaterialIcons')
          ..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf')))
        .load();
  });
  test('server practice marker is carried through the document model', () {
    final r = BusinessRecord.fromJson({
      'id': 'id',
      'workspace_id': 'shop',
      'kind': 'purchase',
      'title': 'Practice',
      'data': {'notes': '[PRACTICE ONLY]', 'lines': []},
      'status': 'draft',
      'revision': 1,
      'is_test': true
    });
    expect(r.isTest, isTrue);
    expect(r.asPurchase(english: true).notes, contains('PRACTICE ONLY'));
  });
  testWidgets(
      'reset requires explicit confirmation and uses account-scoped workspace',
      (tester) async {
    final repo = SampleBusiness();
    await pumpBusiness(tester, repo, initial: '/business-samples');
    await reveal(tester, find.byKey(const ValueKey('sample-reset-campaign')));
    expect(find.textContaining('추가·수정한 자료를 모두 삭제'), findsOneWidget);
    await tester.tap(find.text('취소'));
    await tester.pumpAndSettle();
    expect(repo.resets, 0);
    await reveal(tester, find.byKey(const ValueKey('sample-reset-campaign')));
    await tester.tap(find.text('확인'));
    await tester.pumpAndSettle();
    expect(repo.resets, 1);
  });
  testWidgets('expired sample workspace cannot be opened or reset',
      (tester) async {
    final repo = SampleBusiness()..available = false;
    await pumpBusiness(tester, repo, initial: '/business-samples');
    expect(find.byKey(const ValueKey('sample-start-campaign')), findsNothing);
    expect(find.byKey(const ValueKey('sample-reset-campaign')), findsNothing);
  });
  testWidgets('creating samples once opens the normal team workspace',
      (tester) async {
    final repo = SampleBusiness()..existing = false;
    await pumpBusiness(tester, repo, initial: '/business-samples');
    await reveal(tester, find.byKey(const ValueKey('sample-start-campaign')));
    await tester.tap(find.text('계속'));
    await tester.pumpAndSettle();
    expect(repo.starts, 1);
    expect(find.byType(BusinessWorkspacePage), findsOneWidget);
  });
  testWidgets('sample deletion ends the campaign first and can be cancelled',
      (tester) async {
    final repo = SampleBusiness();
    await pumpBusiness(tester, repo,
        initial: '/membership/admin/business-tests');
    await reveal(tester, find.byKey(const ValueKey('sample-delete-campaign')));
    expect(
        find.descendant(
            of: find.byType(AlertDialog),
            matching: find.textContaining('현재 자료 60개')),
        findsOneWidget);
    await tester.tap(find.text('취소'));
    await tester.pumpAndSettle();
    expect(repo.ends, 0);
    expect(repo.deletes, 0);
    await reveal(tester, find.byKey(const ValueKey('sample-delete-campaign')));
    await tester.tap(find.text('확인'));
    await tester.pumpAndSettle();
    expect(repo.ends, 1);
    expect(repo.deletes, 1);
    expect(find.byKey(const ValueKey('sample-delete-campaign')), findsNothing);
  });
  testWidgets('account change after ending prevents cleanup as another account',
      (tester) async {
    final account = StateProvider<String?>((ref) => 'staff');
    final repo = SampleBusiness()..endWait = Completer<void>();
    await pumpBusiness(tester, repo,
        initial: '/membership/admin/business-tests',
        overrides: [
          activeAccountIdProvider.overrideWith((ref) => ref.watch(account))
        ]);
    final container = ProviderScope.containerOf(
        tester.element(find.byType(BusinessTestAdminPage)));
    await reveal(tester, find.byKey(const ValueKey('sample-delete-campaign')));
    await tester.tap(find.text('확인'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(repo.ends, 1);
    container.read(account.notifier).state = 'different';
    repo.endWait!.complete();
    await tester.pump();
    expect(repo.deletes, 0);
    await tester.pumpWidget(const SizedBox.shrink());
  });
  testWidgets('late sample creation cannot navigate after account changes',
      (tester) async {
    final account = StateProvider<String?>((ref) => 'staff');
    final repo = SampleBusiness()
      ..existing = false
      ..startWait = Completer<void>();
    final router = await pumpBusiness(tester, repo,
        initial: '/business-samples',
        overrides: [
          activeAccountIdProvider.overrideWith((ref) => ref.watch(account))
        ]);
    final container = ProviderScope.containerOf(
        tester.element(find.byType(BusinessSamplesPage)));
    await reveal(tester, find.byKey(const ValueKey('sample-start-campaign')));
    await tester.tap(find.text('계속'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 600));
    await tester.pump();
    container.read(account.notifier).state = 'different';
    repo.startWait!.complete();
    await tester.pump();
    expect(router.routeInformationProvider.value.uri.path, '/business-samples');
    expect(find.byType(BusinessWorkspacePage), findsNothing);
    await tester.pumpWidget(const SizedBox.shrink());
  });
  for (final locale in ['ko', 'en']) {
    for (final admin in [false, true]) {
      testWidgets(
          '$locale ${admin ? 'admin' : 'tester'} screen fits mobile and enlarged text',
          (tester) async {
        final key = GlobalKey();
        final repo = SampleBusiness();
        await pumpBusiness(tester, repo,
            locale: locale,
            initial: admin
                ? '/membership/admin/business-tests'
                : '/business-samples',
            width: 390,
            capture: key);
        expect(tester.takeException(), isNull);
        final output = Platform.environment['SCOUT_SAMPLE_PREVIEW'];
        if (output != null) {
          await tester.runAsync(() async {
            final render = key.currentContext!.findRenderObject()!
                as RenderRepaintBoundary;
            final image = await render.toImage(pixelRatio: 1);
            final bytes =
                await image.toByteData(format: ui.ImageByteFormat.png);
            await Directory(output).create(recursive: true);
            await File(
                    '$output/samples-$locale-${admin ? 'admin' : 'tester'}.png')
                .writeAsBytes(bytes!.buffer.asUint8List());
            image.dispose();
          });
        }
        tester.view.physicalSize = const Size(320, 740);
        tester.platformDispatcher.textScaleFactorTestValue = 2;
        addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        if (admin) {
          await reveal(
              tester, find.text(locale == 'ko' ? '테스터 등록' : 'Add tester'));
          expect(tester.takeException(), isNull);
        }
      });
    }
  }
}
