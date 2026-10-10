import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:k_youtube/core/localization/app_localizations.dart';
import 'package:k_youtube/core/theme/app_theme.dart';
import 'package:k_youtube/core/widgets/scout_navigation_bar.dart';
import 'package:k_youtube/features/auth/application/auth_providers.dart';
import 'package:k_youtube/features/membership/application/membership_providers.dart';
import 'package:k_youtube/features/membership/domain/membership.dart';
import 'package:k_youtube/features/shopping/data/supplier_request_repository.dart';
import 'package:k_youtube/features/shopping/domain/supplier_request.dart';
import 'package:k_youtube/features/workspace/application/workspace_navigation.dart';
import 'package:k_youtube/features/workspace/application/workspace_profile_controller.dart';
import 'package:k_youtube/features/workspace/domain/workspace_profile.dart';
import 'package:k_youtube/features/workspace/presentation/workspace_frame.dart';
import 'package:k_youtube/features/workspace/presentation/workspace_page.dart';
import 'package:k_youtube/features/workspace/presentation/workspace_preferences_page.dart';

WorkspaceProfile choice(WorkspaceMode mode, {bool multiple = false}) =>
    WorkspaceProfile(
        active: mode,
        enabled: multiple ? WorkspaceMode.values.toSet() : {mode});

class MemoryWorkspaceRepository implements WorkspaceProfileRepository {
  MemoryWorkspaceRepository(this.profile);
  WorkspaceProfile profile;
  final List<String?> savedAccounts = [];
  Completer<void>? pendingSave;
  bool fail = false;
  @override
  Future<WorkspaceProfile> load(String? accountId) async => profile;
  @override
  Future<void> save(String? accountId, WorkspaceProfile value) async {
    savedAccounts.add(accountId);
    if (pendingSave != null) await pendingSave!.future;
    if (fail) throw StateError('offline');
    profile = value;
  }
}

class _FakeAuth extends Fake implements GoTrueClient {
  User? user;
  Map<String, dynamic>? written;
  @override
  User? get currentUser => user;
  @override
  Future<UserResponse> getUser([String? jwt]) async =>
      UserResponse.fromJson(user!.toJson());
  @override
  Future<UserResponse> updateUser(UserAttributes attributes,
      {String? emailRedirectTo}) async {
    written = Map<String, dynamic>.from(attributes.data as Map);
    user = User(
        id: user!.id,
        appMetadata: const {},
        userMetadata: {...?user!.userMetadata, ...?written},
        aud: 'authenticated',
        createdAt: '2026-09-16');
    return UserResponse.fromJson(user!.toJson());
  }
}

Future<GoRouter> pumpRole(
    WidgetTester tester, MemoryWorkspaceRepository repository,
    {String locale = 'ko',
    double width = 390,
    String initial = '/workspace',
    String? account,
    bool navigationEnabled = true,
    List<Override> overrides = const [],
    WorkspaceNavigation? navigation,
    GlobalKey? imageKey}) async {
  tester.view.physicalSize = Size(width, 1000);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  final router = GoRouter(initialLocation: initial, routes: [
    ShellRoute(
      builder: (_, state, child) =>
          WorkspaceFrame(location: state.uri.toString(), child: child),
      routes: [
        GoRoute(
            path: '/workspace',
            builder: (_, state) => WorkspacePage(
                personalStudio:
                    state.uri.queryParameters['area'] == 'personal')),
        GoRoute(
            path: '/workspace-settings',
            builder: (_, __) => const WorkspacePreferencesPage()),
        GoRoute(
            path: '/workspace-menu',
            builder: (_, __) => const WorkspaceMenuPage()),
        GoRoute(
            path: '/workspace-switch/:mode',
            builder: (_, state) =>
                WorkspaceSwitchPage(mode: state.pathParameters['mode']!)),
        GoRoute(
            path: '/edit',
            onExit: (_, __) => navigation!.confirmLeave(),
            builder: (_, __) => const Scaffold(body: Text('UNSAVED EDITOR'))),
        for (final path in [
          '/',
          '/login',
          '/account',
          '/supplier-business',
          '/supplier-directory',
          '/my-recipes',
          '/chef',
          '/kitchen',
          '/supplier-requests',
          '/purchases',
          '/shopping-stores',
          '/supplier-request-ledger',
          '/chef-sales',
          '/guide',
          '/membership',
          '/membership/admin'
        ])
          GoRoute(
              path: path,
              builder: (_, state) => Scaffold(
                  bottomNavigationBar:
                      {'/', '/my-recipes', '/chef', '/kitchen'}.contains(path)
                          ? ScoutNavigationBar(
                              selectedIndex: 0, enabled: navigationEnabled)
                          : null,
                  body: Text('DESTINATION ${state.uri.path}'))),
      ],
    )
  ]);
  addTearDown(router.dispose);
  await tester.pumpWidget(ProviderScope(
      overrides: [
        activeAccountIdProvider.overrideWithValue(account),
        ...overrides,
        workspaceProfileRepositoryProvider.overrideWithValue(repository),
        if (navigation != null)
          workspaceNavigationProvider.overrideWithValue(navigation),
      ],
      child: MaterialApp.router(
        routerConfig: router,
        theme: AppTheme.light.copyWith(
            textTheme:
                AppTheme.light.textTheme.apply(fontFamily: 'RecipeScoutKR'),
            navigationBarTheme: AppTheme.light.navigationBarTheme.copyWith(
                labelTextStyle: WidgetStatePropertyAll(
                    AppTheme.light.textTheme.labelMedium?.copyWith(
                        fontFamily: 'RecipeScoutKR',
                        fontWeight: FontWeight.w700))),
            appBarTheme: AppTheme.light.appBarTheme.copyWith(
                titleTextStyle: AppTheme.light.appBarTheme.titleTextStyle
                    ?.copyWith(fontFamily: 'RecipeScoutKR'))),
        locale: Locale(locale),
        supportedLocales: AppLocalizations.supportedLocales,
        localizationsDelegates: const [
          AppLocalizations.delegate,
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate
        ],
        builder: (_, child) => RepaintBoundary(key: imageKey, child: child!),
      )));
  await tester.pumpAndSettle();
  return router;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));
  setUpAll(() async {
    await (FontLoader('RecipeScoutKR')
          ..addFont(rootBundle.load('assets/fonts/NanumGothic-Regular.ttf')))
        .load();
    await (FontLoader('MaterialIcons')
          ..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf')))
        .load();
  });
  test(
      'presentation preference validates active membership and never grants an authorization role',
      () {
    expect(
        WorkspaceProfile.fromJson({
          'schema': 1,
          'active': 'admin',
          'enabled': ['admin']
        }).configured,
        isFalse);
    expect(
        WorkspaceProfile.fromJson({
          'schema': 1,
          'active': 'supplier',
          'enabled': ['personal']
        }).configured,
        isFalse);
    final p = WorkspaceProfile.fromJson({
      'schema': 1,
      'active': 'supplier',
      'enabled': ['supplier', 'admin', 'supplier']
    });
    expect(p.enabled, {WorkspaceMode.supplier});
    expect(p.toJson().keys, unorderedEquals(['schema', 'active', 'enabled']));
    expect(() => p.activate(WorkspaceMode.professional), throwsArgumentError);
  });
  test(
      'guest preferences are not inherited by a signed-in account and only one metadata key is written',
      () async {
    final auth = _FakeAuth()
      ..user = const User(
          id: 'member-a',
          appMetadata: {},
          userMetadata: {'full_name': 'Tester'},
          aud: 'authenticated',
          createdAt: '2026-09-16');
    final repo = SavedWorkspaceProfileRepository(() => auth);
    await repo.save(null, choice(WorkspaceMode.supplier));
    expect((await repo.load(null)).active, WorkspaceMode.supplier);
    expect((await repo.load('member-a')).configured, isFalse);
    await repo.save('member-a', choice(WorkspaceMode.professional));
    expect(auth.written!.keys, [WorkspaceProfile.metadataKey]);
    expect(auth.user!.userMetadata!['full_name'], 'Tester');
    auth.user = const User(
        id: 'member-b',
        userMetadata: {},
        appMetadata: {},
        aud: 'authenticated',
        createdAt: '2026-09-16');
    expect((await repo.load('member-b')).configured, isFalse);
    expect(() => repo.save('member-a', choice(WorkspaceMode.personal)),
        throwsStateError);
  });
  test('account changes and a failed save cannot replace another workspace',
      () async {
    final repo = MemoryWorkspaceRepository(choice(WorkspaceMode.personal));
    var owner = 'a';
    final controller =
        WorkspaceProfileController(repo, 'a', () => owner == 'a');
    await controller.reload();
    repo.pendingSave = Completer<void>();
    final pending = controller.save(choice(WorkspaceMode.supplier));
    owner = 'b';
    repo.pendingSave!.complete();
    expect(await pending, isFalse);
    expect(controller.state.requireValue.active, WorkspaceMode.personal);
    owner = 'a';
    repo.pendingSave = null;
    repo.fail = true;
    expect(await controller.save(choice(WorkspaceMode.professional)), isFalse);
    expect(controller.state.requireValue.active, WorkspaceMode.personal);
    controller.dispose();
  });
  for (final locale in ['ko', 'en']) {
    for (final mode in WorkspaceMode.values) {
      for (final width in [390.0, 1440.0]) {
        testWidgets(
            '$locale ${mode.name} shows focused menus at $width and large text',
            (tester) async {
          final repo = MemoryWorkspaceRepository(choice(mode));
          final key = GlobalKey();
          await pumpRole(tester, repo,
              locale: locale, width: width, imageKey: key);
          final bar = find.byType(NavigationBar);
          if (width < 1100) {
            final labels = tester
                .widget<NavigationBar>(bar)
                .destinations
                .cast<NavigationDestination>()
                .map((d) => d.label);
            expect(labels.length, 4);
            if (mode == WorkspaceMode.personal) {
              expect(labels, isNot(contains(locale == 'ko' ? '셰프' : 'Chef')));
            }
            if (mode == WorkspaceMode.supplier) {
              expect(labels,
                  isNot(contains(locale == 'ko' ? '요청하기' : 'Requests')));
            }
          } else {
            expect(bar, findsNothing);
          }
          expect(find.byTooltip(locale == 'ko' ? '사용 공간 선택' : 'Choose space'),
              findsOneWidget);
          expect(tester.takeException(), isNull);
          final output = Platform.environment['SCOUT_ROLE_PREVIEW'];
          if (output != null) {
            await tester.runAsync(() async {
              final render = key.currentContext!.findRenderObject()!
                  as RenderRepaintBoundary;
              final image = await render.toImage(pixelRatio: 1);
              final bytes =
                  await image.toByteData(format: ui.ImageByteFormat.png);
              await Directory(output).create(recursive: true);
              await File('$output/${mode.name}-$locale-${width.toInt()}.png')
                  .writeAsBytes(bytes!.buffer.asUint8List());
              image.dispose();
            });
          }
          final next = switch (mode) {
            WorkspaceMode.personal => '/my-recipes',
            WorkspaceMode.professional => '/my-recipes',
            WorkspaceMode.supplier => '/supplier-business?section=products',
          };
          if (width < 1100) {
            await tester.tap(find.byType(NavigationDestination).at(1));
          } else {
            await tester.tap(find.byKey(ValueKey('workspace-nav-$next')));
          }
          await tester.pumpAndSettle();
          expect(
              find.text('DESTINATION ${Uri.parse(next).path}'), findsOneWidget);
          if (width < 1100) {
            expect(
                tester
                    .widget<NavigationBar>(find.byType(NavigationBar))
                    .selectedIndex,
                1);
          }
          GoRouter.of(tester
                  .element(find.text('DESTINATION ${Uri.parse(next).path}')))
              .go('/workspace');
          await tester.pumpAndSettle();
          tester.view.physicalSize = const Size(320, 720);
          tester.platformDispatcher.textScaleFactorTestValue = 2;
          addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
          await tester.pumpAndSettle();
          expect(tester.takeException(), isNull);
        });
      }
    }
  }
  testWidgets(
      'multiple-purpose selector fits English desktop and enlarged mobile text',
      (tester) async {
    await pumpRole(
        tester,
        MemoryWorkspaceRepository(
            choice(WorkspaceMode.professional, multiple: true)),
        locale: 'en',
        width: 1440);
    expect(tester.takeException(), isNull);
    tester.view.physicalSize = const Size(320, 720);
    tester.platformDispatcher.textScaleFactorTestValue = 2;
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    await tester.tap(find.byTooltip('Choose space'));
    await tester.pumpAndSettle();
    expect(find.widgetWithText(CheckedPopupMenuItem<String>, 'Supplier space'),
        findsOneWidget);
    expect(tester.takeException(), isNull);
  });
  testWidgets('failed preference save retains the choices for retry',
      (tester) async {
    final repo = MemoryWorkspaceRepository(const WorkspaceProfile())
      ..fail = true;
    await pumpRole(tester, repo, initial: '/workspace-settings');
    await tester.tap(find.byKey(const ValueKey('purpose-supplier')));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.byKey(const Key('save-workspace-purpose')));
    await tester.tap(find.byKey(const Key('save-workspace-purpose')));
    await tester.pumpAndSettle();
    expect(repo.profile.configured, isFalse);
    expect(find.text('설정을 저장하지 못했어요. 연결 상태를 확인하고 다시 시도해 주세요.'), findsOneWidget);
    expect(
        tester
            .widget<CheckboxListTile>(
                find.byKey(const ValueKey('purpose-supplier')))
            .value,
        isTrue);
    repo.fail = false;
    await tester.ensureVisible(find.byKey(const Key('save-workspace-purpose')));
    await tester.tap(find.byKey(const Key('save-workspace-purpose')));
    await tester.pumpAndSettle();
    expect(repo.profile.active, WorkspaceMode.supplier);
    expect(tester.takeException(), isNull);
  });
  testWidgets(
      'professional home prioritizes tasks and opens the selected request directly',
      (tester) async {
    final key = GlobalKey();
    await pumpRole(
        tester, MemoryWorkspaceRepository(choice(WorkspaceMode.professional)),
        width: 1440,
        account: 'buyer-a',
        initial: '/workspace?area=personal',
        imageKey: key,
        overrides: [
          supplierRequestsProvider.overrideWith((_) async => const [
                SupplierRequest(
                    id: 'request-a',
                    supplier:
                        ShoppingSupplier(id: 'supplier-a', name: '테스트 농산물'),
                    lines: [],
                    status: 'accepted'),
                SupplierRequest(
                    id: 'request-b',
                    supplier:
                        ShoppingSupplier(id: 'supplier-b', name: '테스트 수산'),
                    lines: [],
                    status: 'draft'),
              ]),
        ]);
    expect(find.text('테스트 농산물'), findsOneWidget);
    expect(find.text('수락 확인 · 입고 내역을 확인해 주세요.'), findsOneWidget);
    expect(find.text('저장한 초안 · 수정 후 보내기'), findsOneWidget);
    expect(find.text('내 계정'), findsWidgets);
    final output = Platform.environment['SCOUT_ROLE_PREVIEW'];
    if (output != null) {
      await tester.runAsync(() async {
        final render =
            key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
        final image = await render.toImage(pixelRatio: 1);
        final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
        await Directory(output).create(recursive: true);
        await File('$output/professional-ko-1440-signed-in.png')
            .writeAsBytes(bytes!.buffer.asUint8List());
        image.dispose();
      });
    }
    await tester.ensureVisible(find.text('테스트 농산물'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('테스트 농산물'));
    await tester.pumpAndSettle();
    expect(find.text('DESTINATION /purchases'), findsOneWidget);
    expect(
        GoRouterState.of(tester.element(find.text('DESTINATION /purchases')))
            .uri
            .queryParameters['request'],
        'request-a');
    expect(tester.takeException(), isNull);
  });
  testWidgets('mobile frame preserves a page navigation lock while saving',
      (tester) async {
    await pumpRole(
        tester, MemoryWorkspaceRepository(choice(WorkspaceMode.personal)),
        initial: '/kitchen', navigationEnabled: false);
    expect(find.byType(NavigationBar), findsOneWidget);
    expect(
        tester
            .widget<NavigationBar>(find.byType(NavigationBar))
            .onDestinationSelected,
        isNull);
  });
  testWidgets('first-use selection saves purposes and settings retain them',
      (tester) async {
    final repo = MemoryWorkspaceRepository(const WorkspaceProfile());
    final router = await pumpRole(tester, repo, initial: '/workspace-settings');
    expect(
        tester
            .widget<FilledButton>(
                find.byKey(const Key('save-workspace-purpose')))
            .onPressed,
        isNull);
    await tester.tap(find.byKey(const ValueKey('purpose-professional')));
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
        find.byKey(const Key('save-workspace-purpose')), 300,
        scrollable: find.byType(Scrollable).first);
    await tester.tap(find.byKey(const Key('save-workspace-purpose')));
    await tester.pumpAndSettle();
    expect(repo.profile.active, WorkspaceMode.professional);
    router.go('/workspace-settings');
    await tester.pumpAndSettle();
    expect(
        tester
            .widget<CheckboxListTile>(
                find.byKey(const ValueKey('purpose-professional')))
            .value,
        isTrue);
    expect(tester.takeException(), isNull);
  });
  testWidgets(
      'switching purposes honors the editor cancellation before any preference write',
      (tester) async {
    final repo = MemoryWorkspaceRepository(
        choice(WorkspaceMode.personal, multiple: true));
    final nav = WorkspaceNavigation();
    var allow = false, prompts = 0;
    nav.register('editor', () async {
      prompts++;
      return allow;
    });
    final router = await pumpRole(tester, repo,
        width: 1440, initial: '/edit', navigation: nav);
    await tester.tap(find.byTooltip('사용 공간 선택'));
    await tester.pumpAndSettle();
    await tester
        .tap(find.widgetWithText(CheckedPopupMenuItem<String>, '공급업체 공간'));
    await tester.pumpAndSettle();
    expect(router.routeInformationProvider.value.uri.path, '/edit');
    expect(repo.savedAccounts, isEmpty);
    expect(prompts, 1);
    allow = true;
    await tester.tap(find.byTooltip('사용 공간 선택'));
    await tester.pumpAndSettle();
    await tester
        .tap(find.widgetWithText(CheckedPopupMenuItem<String>, '공급업체 공간'));
    await tester.pumpAndSettle();
    expect(router.routeInformationProvider.value.uri.path, '/workspace');
    expect(repo.profile.active, WorkspaceMode.supplier);
    expect(prompts, 2);
  });
  testWidgets('supplier can return to personal space after guarded exit',
      (tester) async {
    final repo = MemoryWorkspaceRepository(choice(WorkspaceMode.supplier));
    final nav = WorkspaceNavigation();
    var allow = false;
    nav.register('editor', () async => allow);
    final router = await pumpRole(tester, repo,
        width: 1440, initial: '/edit', navigation: nav);
    Future<void> choosePersonal() async {
      await tester.tap(find.byTooltip('사용 공간 선택'));
      await tester.pumpAndSettle();
      await tester
          .tap(find.widgetWithText(CheckedPopupMenuItem<String>, '개인 공간'));
      await tester.pumpAndSettle();
    }

    await choosePersonal();
    expect(router.routeInformationProvider.value.uri.path, '/edit');
    expect(repo.savedAccounts, isEmpty);
    allow = true;
    await choosePersonal();
    expect(router.routeInformationProvider.value.uri.path, '/');
    expect(repo.profile.active, WorkspaceMode.personal);
    expect(repo.profile.enabled,
        containsAll([WorkspaceMode.personal, WorkspaceMode.supplier]));
    expect(repo.savedAccounts, hasLength(1));
  });
  testWidgets('administrator sees admin home in more menu', (tester) async {
    final router = await pumpRole(
      tester,
      MemoryWorkspaceRepository(choice(WorkspaceMode.professional)),
      initial: '/workspace-menu',
      overrides: [
        membershipInfoProvider.overrideWith(
          (ref) async => const MembershipInfo(
            planCode: 'free',
            displayName: '관리자',
            status: 'active',
            priceKrw: 0,
            billingPeriod: 'none',
            recipeModel: 'gpt-4o-mini',
            dailyLimit: 0,
            weeklyLimit: 0,
            monthlyLimit: 0,
            dailyUsed: 0,
            weeklyUsed: 0,
            monthlyUsed: 0,
            autoRenews: false,
            isAdmin: true,
          ),
        ),
      ],
    );

    await tester.pumpAndSettle();
    expect(find.text('관리자 홈'), findsOneWidget);

    await tester.tap(find.text('관리자 홈'));
    await tester.pumpAndSettle();
    expect(router.routeInformationProvider.value.uri.path, '/membership/admin');
  });
  testWidgets('more keeps management tools outside the shopping flow',
      (tester) async {
    await pumpRole(
        tester, MemoryWorkspaceRepository(choice(WorkspaceMode.professional)),
        initial: '/workspace-menu');
    expect(find.text('구매요청 대장'), findsNothing);
    await tester.scrollUntilVisible(find.text('매출 현황'), 200,
        scrollable: find.byType(Scrollable).first);
    await tester.tap(find.text('매출 현황'));
    await tester.pumpAndSettle();
    expect(find.text('DESTINATION /chef-sales'), findsOneWidget);
  });
}
