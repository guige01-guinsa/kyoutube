import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:k_youtube/features/auth/application/auth_providers.dart';
import 'package:k_youtube/features/business/domain/business_workspace.dart';
import 'business_flow_test.dart' show MemoryBusiness, pumpBusiness;

class StaffBusiness extends MemoryBusiness {
  StaffBusiness({bool owner = true}) : super({'recipes.read'}) {
    business = BusinessContext(
        id: 'shop',
        name: 'Test Kitchen',
        owner: owner,
        paid: true,
        approval: true,
        permissions: {'recipes.read'});
  }
  final staff = <Map<String, dynamic>>[
    {
      'user_id': 'staff',
      'display_name': 'Owner',
      'active': true,
      'permissions': businessPermissions,
      'profile_revision': 1,
      'job_title': 'Owner',
      'work_contact': ''
    },
    {
      'user_id': 'buyer',
      'display_name': 'Buyer',
      'active': true,
      'permissions': ['recipes.read', 'purchasing.read', 'purchasing.write'],
      'profile_revision': 1,
      'job_title': 'Purchasing lead',
      'work_contact': 'buyer@example.test'
    },
    {
      'user_id': 'former',
      'display_name': 'Former',
      'active': false,
      'permissions': ['recipes.read'],
      'profile_revision': 1,
      'job_title': 'Former chef',
      'work_contact': ''
    }
  ];
  bool staleProfile = false;
  int profileWrites = 0;
  final accessWrites = <bool>[];
  @override
  Future<List<Map<String, dynamic>>> members(String workspace) async =>
      staff.map((m) => {...m}).toList();
  @override
  Future<List<Map<String, dynamic>>> invites(String workspace) async => [];
  @override
  Future<List<Map<String, dynamic>>> accessEvents(String workspace) async => [];
  @override
  Future<void> memberProfile(String workspace, String user,
      {required String displayName,
      required String jobTitle,
      required String workContact,
      required int revision}) async {
    if (staleProfile) throw const PostgrestException(message: 'BUSINESS_STALE');
    profileWrites++;
    final m = staff.firstWhere((m) => m['user_id'] == user);
    m.addAll({
      'display_name': displayName.trim(),
      'job_title': jobTitle.trim(),
      'work_contact': workContact.trim(),
      'profile_revision': revision + 1
    });
  }

  @override
  Future<void> member(String workspace, String user, Set<String> permissions,
      bool active) async {
    accessWrites.add(active);
    staff.firstWhere((m) => m['user_id'] == user)
      ..['permissions'] = permissions.toList()
      ..['active'] = active;
  }
}

Future<void> openStaffAction(WidgetTester tester, String key) async {
  final button = find.byKey(ValueKey(key));
  for (var attempt = 0;
      attempt < 50 && button.hitTestable().evaluate().isEmpty;
      attempt++) {
    final direction =
        button.evaluate().isNotEmpty && tester.getRect(button).bottom < 0
            ? 350.0
            : -350.0;
    await tester.drag(find.byType(Scrollable).first, Offset(0, direction));
    await tester.pumpAndSettle();
  }
  expect(button.hitTestable(), findsOneWidget);
  await tester.tap(button);
  await tester.pumpAndSettle();
}

Future<void> saveDialog(WidgetTester tester, {String label = '저장'}) async {
  final button = find.widgetWithText(FilledButton, label);
  await tester.ensureVisible(button);
  await tester.tap(button);
  await tester.pumpAndSettle();
  await tester.pump(const Duration(milliseconds: 300));
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
  for (final language in ['ko', 'en']) {
    testWidgets(
        '$language owner can edit staff profile on a narrow screen with large text',
        (tester) async {
      final repo = StaffBusiness();
      final preview = GlobalKey();
      await pumpBusiness(tester, repo,
          initial: '/business-workspaces/shop/members',
          locale: language,
          width: 320,
          textScale: 2,
          capture: preview);
      await openStaffAction(tester, 'staff-profile-buyer');
      final output = Platform.environment['SCOUT_STAFF_PREVIEW'];
      if (output != null) {
        await tester.runAsync(() async {
          final render = preview.currentContext!.findRenderObject()!
              as RenderRepaintBoundary;
          final image = await render.toImage(pixelRatio: 1);
          final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
          await Directory(output).create(recursive: true);
          await File('$output/staff-profile-$language.png')
              .writeAsBytes(bytes!.buffer.asUint8List());
          image.dispose();
        });
      }

      await tester.enterText(
          find.byKey(const ValueKey('staff-profile-name')), 'New Buyer');
      await tester.enterText(
          find.byKey(const ValueKey('staff-profile-title')), 'Lead');
      await tester.enterText(
          find.byKey(const ValueKey('staff-profile-contact')),
          'office@example.test');
      await saveDialog(tester, label: language == 'ko' ? '저장' : 'Save');
      expect(repo.profileWrites, 1);
      expect(repo.staff[1]['display_name'], 'New Buyer');
      expect(repo.staff[1]['work_contact'], 'office@example.test');
      expect(repo.staff[1]['active'], isTrue);
      expect(repo.accessWrites, isEmpty);
      expect(tester.takeException(), isNull);
    });
  }
  testWidgets('search and access filters isolate the requested staff member',
      (tester) async {
    final repo = StaffBusiness();
    await pumpBusiness(tester, repo,
        initial: '/business-workspaces/shop/members');
    await tester.enterText(
        find.byKey(const ValueKey('staff-search')), 'buyer@example.test');
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('staff-card-buyer')), findsOneWidget);
    expect(find.byKey(const ValueKey('staff-card-staff')), findsNothing);
    await tester.enterText(find.byKey(const ValueKey('staff-search')), '');
    await tester.pumpAndSettle();
    await openStaffAction(tester, 'staff-filter-inactive');
    expect(find.byKey(const ValueKey('staff-card-former')), findsOneWidget);
    expect(find.byKey(const ValueKey('staff-card-buyer')), findsNothing);
  });
  testWidgets('editing suspended staff permissions does not restore access',
      (tester) async {
    final repo = StaffBusiness();
    await pumpBusiness(tester, repo,
        initial: '/business-workspaces/shop/members');
    await openStaffAction(tester, 'staff-permissions-former');
    expect(find.text('권한을 수정해도 이용 중지 상태는 유지됩니다.'), findsOneWidget);
    await saveDialog(tester);
    expect(repo.accessWrites, [false]);
    expect(repo.staff[2]['active'], isFalse);
  });
  testWidgets('restore is a separate explicit action with a permissions review',
      (tester) async {
    final repo = StaffBusiness();
    await pumpBusiness(tester, repo,
        initial: '/business-workspaces/shop/members');
    await openStaffAction(tester, 'staff-restore-former');
    expect(find.text('저장하면 아래 권한으로 업소 이용이 다시 허용됩니다.'), findsOneWidget);
    expect(repo.accessWrites, isEmpty);
    await saveDialog(tester);
    expect(repo.accessWrites, [true]);
  });
  testWidgets('suspension needs confirmation and retains member profile',
      (tester) async {
    final repo = StaffBusiness();
    await pumpBusiness(tester, repo,
        initial: '/business-workspaces/shop/members');
    await openStaffAction(tester, 'staff-suspend-buyer');
    expect(repo.accessWrites, isEmpty);
    await tester.tap(find.widgetWithText(FilledButton, '확인'));
    await tester.pumpAndSettle();
    expect(repo.accessWrites, [false]);
    expect(repo.staff[1]['work_contact'], 'buyer@example.test');
  });
  testWidgets(
      'profile validation rejects blank name and surfaces conflicts without overwriting',
      (tester) async {
    final repo = StaffBusiness()..staleProfile = true;
    await pumpBusiness(tester, repo,
        initial: '/business-workspaces/shop/members');
    await openStaffAction(tester, 'staff-profile-buyer');
    await tester.enterText(
        find.byKey(const ValueKey('staff-profile-name')), ' ');
    await saveDialog(tester);
    expect(find.text('이름을 입력해 주세요.'), findsOneWidget);
    expect(repo.profileWrites, 0);
    await tester.enterText(
        find.byKey(const ValueKey('staff-profile-name')), 'Attempt');
    await saveDialog(tester);
    expect(find.textContaining('다른 담당자가 수정했습니다.'), findsOneWidget);
    expect(repo.staff[1]['display_name'], 'Buyer');
    expect(find.byKey(const ValueKey('staff-profile-save')), findsOneWidget);
    await tester.tap(find.widgetWithText(TextButton, '취소'));
    await tester.pumpAndSettle();
    await tester.pump(const Duration(milliseconds: 300));
  });
  testWidgets('non-owner cannot open staff management controls',
      (tester) async {
    await pumpBusiness(tester, StaffBusiness(owner: false),
        initial: '/business-workspaces/shop/members');
    expect(find.text('사장만 직원 권한을 관리할 수 있습니다.'), findsOneWidget);
    expect(find.byKey(const ValueKey('staff-profile-buyer')), findsNothing);
  });
  testWidgets(
      'legacy database keeps permissions without unavailable profile editor',
      (tester) async {
    final repo = StaffBusiness();
    for (final member in repo.staff) {
      member.remove('profile_revision');
    }
    await pumpBusiness(tester, repo,
        initial: '/business-workspaces/shop/members');
    expect(find.byKey(const ValueKey('staff-profile-buyer')), findsNothing);
    await openStaffAction(tester, 'staff-permissions-buyer');
    expect(find.byType(AlertDialog), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
  testWidgets('account switch closes the staff profile editor without saving',
      (tester) async {
    final repo = StaffBusiness();
    final account = StateProvider<String?>((ref) => 'staff');
    await pumpBusiness(tester, repo,
        initial: '/business-workspaces/shop/members',
        overrides: [
          activeAccountIdProvider.overrideWith((ref) => ref.watch(account))
        ]);
    await openStaffAction(tester, 'staff-profile-buyer');
    final container =
        ProviderScope.containerOf(tester.element(find.byType(AlertDialog)));
    container.read(account.notifier).state = 'different-account';
    await tester.pumpAndSettle();
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.byKey(const ValueKey('staff-profile-save')), findsNothing);
    expect(repo.profileWrites, 0);
  });
}
