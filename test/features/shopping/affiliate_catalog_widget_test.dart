import 'dart:async';
import 'dart:convert';
import 'package:file_selector_platform_interface/file_selector_platform_interface.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:k_youtube/core/localization/app_localizations.dart';
import 'package:k_youtube/features/auth/application/auth_providers.dart';
import 'package:k_youtube/features/membership/application/membership_providers.dart';
import 'package:k_youtube/features/membership/domain/membership.dart';
import 'package:k_youtube/features/shopping/data/shopping_affiliate_repository.dart';
import 'package:k_youtube/features/shopping/presentation/affiliate_import_dialog.dart';
import 'package:k_youtube/features/shopping/presentation/shopping_affiliate_admin_page.dart';
import 'package:k_youtube/features/shopping/presentation/shopping_assistant_dialogs.dart';

final accountProvider = StateProvider<String?>((ref) => 'admin');

class FakeFileSelector extends FileSelectorPlatform {
  XFile? file;
  @override
  Future<XFile?> openFile({
    List<XTypeGroup>? acceptedTypeGroups,
    String? initialDirectory,
    String? confirmButtonText,
  }) async =>
      file;
}

class UnreadableFile extends XFile {
  UnreadableFile() : super('blocked.csv');
  @override
  Future<int> length() async => 100;
  @override
  Future<Uint8List> readAsBytes() async => throw StateError('blocked');
}

class FakeCatalog extends ShoppingAffiliateRepository {
  FakeCatalog()
      : super(SupabaseClient('https://example.supabase.co', 'test',
            authOptions: const AuthClientOptions(autoRefreshToken: false)));
  final imports = <List<Map<String, dynamic>>>[];
  final changes = <String>[];
  final pages = <int>[];
  Completer<List<Map<String, dynamic>>>? waiting;
  bool networkFailure = false;
  Object? previewFailure;
  @override
  Future<List<Map<String, dynamic>>> preview(
      List<Map<String, dynamic>> rows) async {
    if (previewFailure != null) throw previewFailure!;
    if (waiting != null) return waiting!.future;
    return [
      for (final row in rows)
        if (row['title'] == 'Existing')
          {'id': 'old', 'revision': 2, 'title': 'Old product', 'deleted': false}
        else if (row['title'] == 'Deleted')
          {
            'id': 'deleted',
            'revision': 3,
            'title': 'Deleted product',
            'deleted': true
          }
        else
          {}
    ];
  }

  @override
  Future<List<Map<String, dynamic>>> importRows(
      List<Map<String, dynamic>> rows) async {
    imports.add(rows);
    if (networkFailure) throw StateError('offline');
    return [
      for (final row in rows)
        {
          'status':
              (row['data'] as Map)['title'] == 'Fail' ? 'invalid' : 'saved'
        }
    ];
  }

  @override
  Future<Map<String, dynamic>> page(
      String query, String status, int offset) async {
    pages.add(offset);
    return {
      'total': 26,
      'rows': [
        {
          'id': '$offset',
          'title': 'Offer $offset',
          'revision': 1,
          'published': false,
          'expires_at': '2030-01-01T00:00:00Z'
        }
      ]
    };
  }

  @override
  Future<void> change(Map<String, dynamic> row, String action) async {
    changes.add('${row['id']}:$action');
  }
}

Future<ProviderContainer> host(WidgetTester tester, FakeCatalog repo,
    {bool adminPage = false, bool small = false}) async {
  tester.view.physicalSize =
      small ? const Size(360, 740) : const Size(1000, 1100);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(ProviderScope(
      overrides: [
        activeAccountIdProvider
            .overrideWith((ref) => ref.watch(accountProvider)),
        membershipInfoProvider.overrideWith(
            (_) async => MembershipInfo.fromJson({'is_admin': true})),
        shoppingAffiliateRepositoryProvider.overrideWithValue(repo)
      ],
      child: MaterialApp(
        locale: Locale(small ? 'en' : 'ko'),
        supportedLocales: const [Locale('ko'), Locale('en')],
        localizationsDelegates: const [
          AppLocalizations.delegate,
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate
        ],
        builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context)
                .copyWith(textScaler: TextScaler.linear(small ? 2 : 1)),
            child: child!),
        home: adminPage
            ? const ShoppingAffiliateAdminPage()
            : Scaffold(
                body: Builder(
                    builder: (context) => TextButton(
                        onPressed: () => showDialog<void>(
                            context: context,
                            barrierDismissible: false,
                            builder: (_) => const ShoppingAccountGuard(
                                child: AffiliateImportDialog())),
                        child: const Text('Open')))),
      )));
  await tester.pumpAndSettle();
  final container =
      ProviderScope.containerOf(tester.element(find.byType(Scaffold).first));
  if (!adminPage) {
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();
  }
  return container;
}

Future<void> preview(WidgetTester tester, String text) async {
  await tester.enterText(find.byType(TextField), text);
  await tester.pump();
  await tester.tap(find.text('중복 확인·미리보기'));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('selected CSV previews; cancelling picker preserves the preview',
      (tester) async {
    final previous = FileSelectorPlatform.instance;
    final picker = FakeFileSelector()
      ..file = XFile.fromData(
        Uint8List.fromList(
            utf8.encode('상품명,제휴 링크\n양파,https://link.coupang.com/a/ONION')),
        name: 'catalog.csv',
        path: 'catalog.csv',
      );
    FileSelectorPlatform.instance = picker;
    addTearDown(() => FileSelectorPlatform.instance = previous);
    await host(tester, FakeCatalog());
    await tester.enterText(find.byType(TextField), 'Previous pasted list');
    await tester.pump();
    await tester.tap(find.text('파일 선택'));
    await tester.pumpAndSettle();
    expect(find.text('1 / 1'), findsOneWidget);
    expect(find.text('catalog.csv'), findsOneWidget);
    expect(tester.widget<TextField>(find.byType(TextField)).controller!.text,
        isEmpty);
    picker.file = null;
    await tester.tap(find.text('파일 선택'));
    await tester.pumpAndSettle();
    expect(find.text('1 / 1'), findsOneWidget);
    expect(
        tester
            .widget<FilledButton>(find.widgetWithText(FilledButton, '선택 항목 등록'))
            .onPressed,
        isNotNull);
  });
  testWidgets('failed file read releases controls and manual paste works',
      (tester) async {
    final previous = FileSelectorPlatform.instance;
    FileSelectorPlatform.instance = FakeFileSelector()..file = UnreadableFile();
    addTearDown(() => FileSelectorPlatform.instance = previous);
    await host(tester, FakeCatalog());
    await tester.tap(find.text('파일 선택'));
    await tester.pumpAndSettle();
    expect(find.textContaining('선택한 파일을 읽지 못했습니다'), findsOneWidget);
    await preview(tester, '양파 | https://link.coupang.com/a/ONION');
    expect(find.text('1 / 1'), findsOneWidget);
    expect(find.byType(LinearProgressIndicator), findsNothing);
  });
  testWidgets('clipboard button fills an empty field then common preview works',
      (tester) async {
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(SystemChannels.platform, (call) async {
      if (call.method == 'Clipboard.getData') {
        return {'text': '양파 | https://link.coupang.com/a/ONION'};
      }
      return null;
    });
    addTearDown(() =>
        messenger.setMockMethodCallHandler(SystemChannels.platform, null));
    await host(tester, FakeCatalog());
    await tester.tap(find.text('클립보드에서 붙여넣기'));
    await tester.pumpAndSettle();
    expect(tester.widget<TextField>(find.byType(TextField)).controller!.text,
        contains('양파'));
    await tester.tap(find.text('중복 확인·미리보기'));
    await tester.pumpAndSettle();
    expect(find.text('1 / 1'), findsOneWidget);
  });
  testWidgets(
      'preview timeout allows retry without stale response replacing it',
      (tester) async {
    final pending = Completer<List<Map<String, dynamic>>>();
    final repo = FakeCatalog()..waiting = pending;
    await host(tester, repo);
    await tester.enterText(
        find.byType(TextField), '양파 | https://link.coupang.com/a/ONION');
    await tester.pump();
    await tester.tap(find.text('중복 확인·미리보기'));
    await tester.pump();
    await tester.pump(const Duration(seconds: 31));
    await tester.pumpAndSettle();
    expect(find.textContaining('목록은 읽었지만 서버에서'), findsOneWidget);
    expect(find.text('0 / 1'), findsOneWidget);
    repo.waiting = null;
    await tester.tap(find.text('중복 확인 다시 시도'));
    await tester.pumpAndSettle();
    expect(find.text('1 / 1'), findsOneWidget);
    pending.complete([
      {'id': 'stale', 'revision': 1, 'title': 'Late response'}
    ]);
    await tester.pumpAndSettle();
    expect(find.text('1 / 1'), findsOneWidget);
    expect(find.textContaining('Late response'), findsNothing);
    expect(tester.takeException(), isNull);
  });
  testWidgets('blank ingredients can be previewed and saved as title aliases',
      (tester) async {
    final repo = FakeCatalog();
    await host(tester, repo);
    await preview(
        tester, '상품명,재료,분류,제휴 링크\n고추장,,,https://link.coupang.com/a/PASTE');
    await tester.tap(find.text('선택 항목 등록'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('저장'));
    await tester.pumpAndSettle();
    expect((repo.imports.single.single['data'] as Map)['ingredients'], ['고추장']);
    expect(find.text('저장 완료'), findsOneWidget);
  });
  testWidgets(
      'format, MFA and connection failures show different recovery steps',
      (tester) async {
    final repo = FakeCatalog();
    await host(tester, repo);
    await preview(tester, 'title,title,link\na,b,c');
    expect(find.textContaining('첫 행의 상품명'), findsOneWidget);
    repo.previewFailure =
        const PostgrestException(message: 'ADMIN_MFA_REQUIRED');
    await preview(tester, '상품명,제휴 링크\n고추장,https://link.coupang.com/a/PASTE');
    expect(find.text('2단계 인증을 완료해 주세요.'), findsOneWidget);
    repo.previewFailure = StateError('offline');
    await tester.tap(find.text('중복 확인 다시 시도'));
    await tester.pumpAndSettle();
    expect(find.textContaining('목록은 읽었지만 서버에서'), findsOneWidget);
    expect(
        tester
            .widget<FilledButton>(find.widgetWithText(FilledButton, '선택 항목 등록'))
            .onPressed,
        isNull);
    repo.previewFailure = null;
    await tester.tap(find.text('중복 확인 다시 시도'));
    await tester.pumpAndSettle();
    expect(
        tester
            .widget<FilledButton>(find.widgetWithText(FilledButton, '선택 항목 등록'))
            .onPressed,
        isNotNull);
    expect(tester.takeException(), isNull);
  });
  testWidgets(
      'new rows selected, existing opt in, trash blocked, partial results',
      (tester) async {
    final repo = FakeCatalog();
    await host(tester, repo);
    await preview(tester,
        '001 New https://link.coupang.com/a/A\n002 Existing https://link.coupang.com/a/B\n003 Deleted https://link.coupang.com/a/C\n004 Fail https://link.coupang.com/a/D');
    final tiles = tester
        .widgetList<CheckboxListTile>(find.byType(CheckboxListTile))
        .toList();
    expect(tiles.map((e) => e.value), [true, false, false, true]);
    expect(tiles[2].onChanged, isNull);
    await tester.tap(find.text('2. Existing'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('선택 항목 등록'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('저장'));
    await tester.pumpAndSettle();
    expect(repo.imports.single.length, 3);
    expect(repo.imports.single[1]['action'], 'update');
    expect((repo.imports.single[1]['data'] as Map)['revision'], 2);
    expect(find.text('저장 완료'), findsNWidgets(2));
    expect(find.text('입력 오류'), findsOneWidget);
    final button = tester
        .widget<FilledButton>(find.widgetWithText(FilledButton, '선택 항목 등록'));
    expect(button.onPressed, isNull);
    expect(tester.takeException(), isNull);
  });
  testWidgets('unknown network result prevents resubmission until re-preview',
      (tester) async {
    final repo = FakeCatalog()..networkFailure = true;
    await host(tester, repo);
    await preview(tester, '001 New https://link.coupang.com/a/A');
    await tester.tap(find.text('선택 항목 등록'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('저장'));
    await tester.pumpAndSettle();
    expect(find.textContaining('응답을 확인하지'), findsOneWidget);
    expect(
        tester
            .widget<FilledButton>(find.widgetWithText(FilledButton, '선택 항목 등록'))
            .onPressed,
        isNull);
  });
  testWidgets('account change discards pending import preview', (tester) async {
    final repo = FakeCatalog()..waiting = Completer();
    final container = await host(tester, repo);
    await tester.enterText(
        find.byType(TextField), '001 New https://link.coupang.com/a/A');
    await tester.pump();
    await tester.tap(find.text('중복 확인·미리보기'));
    await tester.pump();
    container.read(accountProvider.notifier).state = 'another';
    await tester.pump();
    await tester.pump();
    repo.waiting!.complete([{}]);
    await tester.pumpAndSettle();
    expect(find.byType(AffiliateImportDialog), findsNothing);
    expect(repo.imports, isEmpty);
    expect(tester.takeException(), isNull);
  });
  testWidgets('small English large text import dialog scrolls without overflow',
      (tester) async {
    await host(tester, FakeCatalog(), small: true);
    expect(find.text('Import catalog'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
  testWidgets('admin selection lifecycle and pagination use server offsets',
      (tester) async {
    final repo = FakeCatalog();
    await host(tester, repo, adminPage: true);
    await tester.ensureVisible(find.text('Offer 0'));
    await tester.tap(find.text('Offer 0'));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('공개 중단'));
    await tester.tap(find.text('공개 중단'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('확인'));
    await tester.pumpAndSettle();
    expect(repo.changes, ['0:hide']);
    final next = find.text('다음');
    for (var i = 0; i < 20 && next.hitTestable().evaluate().isEmpty; i++) {
      await tester.drag(find.byType(ListView).first, const Offset(0, -250));
      await tester.pumpAndSettle();
    }
    expect(next.hitTestable(), findsOneWidget);
    await tester.tap(next.hitTestable());
    await tester.pumpAndSettle();
    expect(repo.pages.last, 25);
    expect(find.text('Offer 25'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
