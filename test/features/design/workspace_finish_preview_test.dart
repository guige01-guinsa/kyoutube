import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:k_youtube/core/localization/app_localizations.dart';
import 'package:k_youtube/core/theme/app_theme.dart';
import 'package:k_youtube/features/auth/application/auth_providers.dart';
import 'package:k_youtube/features/business/data/business_repository.dart';
import 'package:k_youtube/features/workspace/presentation/professional_entry.dart';
import 'package:k_youtube/features/workspace/presentation/workspace_frame.dart';

void main() {
  const capture = bool.fromEnvironment('DESIGN_COMPLETE_CAPTURE');
  setUpAll(() async {
    if (!capture) return;
    for (final family in ['Ahem', 'Roboto', 'RecipeScoutKR', 'MaterialIcons']) {
      final path = family == 'MaterialIcons'
          ? '.fvm/flutter_sdk/bin/cache/artifacts/material_fonts/MaterialIcons-Regular.otf'
          : 'assets/fonts/NanumGothic-Regular.ttf';
      await (FontLoader(family)
            ..addFont(Future.value(
                ByteData.sublistView(await File(path).readAsBytes()))))
          .load();
    }
  });
  for (final language in ['ko', 'en']) {
    for (final width in [320.0, 1440.0]) {
      testWidgets(
          'work area $language $width wraps and preserves business navigation',
          (tester) async {
        final actualWidth = capture && width == 320 ? 390.0 : width;
        tester.view.physicalSize = Size(actualWidth, 960);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        final boundary = GlobalKey();
        final router = GoRouter(initialLocation: '/workspace', routes: [
          GoRoute(
              path: '/workspace',
              builder: (_, __) => const Scaffold(
                  body: WorkspaceScope(child: ProfessionalEntry()))),
          GoRoute(
              path: '/business-workspaces/:id',
              builder: (_, state) =>
                  Scaffold(body: Text('OPEN ${state.pathParameters['id']}'))),
          GoRoute(
              path: '/business-workspaces',
              builder: (_, __) => const Scaffold(body: Text('JOIN'))),
        ]);
        addTearDown(router.dispose);
        await tester.pumpWidget(ProviderScope(
            overrides: [
              activeAccountIdProvider.overrideWithValue('test-user'),
              businessWorkspacesProvider.overrideWith((_) async => [
                    {'id': 'one', 'name': '행복식당 강남점'},
                    {'id': 'two', 'name': '레시피 연구실 — 긴 업소 이름도 표시합니다'},
                    {'id': 'three', 'name': '작은공간'},
                  ]),
            ],
            child: MaterialApp.router(
              routerConfig: router,
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
                  data: MediaQuery.of(context).copyWith(
                      textScaler:
                          TextScaler.linear(width == 320 && !capture ? 2 : 1)),
                  child: RepaintBoundary(key: boundary, child: child!)),
            )));
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        if (capture && language == 'ko') {
          await tester.runAsync(() async {
            final image = await (boundary.currentContext!.findRenderObject()!
                    as RenderRepaintBoundary)
                .toImage();
            final bytes =
                await image.toByteData(format: ui.ImageByteFormat.png);
            await Directory('.artifacts/design-complete')
                .create(recursive: true);
            await File(
                    '.artifacts/design-complete/workspace-${width == 320 ? 'mobile' : 'desktop'}.png')
                .writeAsBytes(bytes!.buffer.asUint8List());
            image.dispose();
          });
        }
        final business = find.text('행복식당 강남점');
        await tester.scrollUntilVisible(business, 200,
            scrollable: find.byType(Scrollable).first);
        await Scrollable.ensureVisible(tester.element(business), alignment: .5);
        await tester.pumpAndSettle();
        await tester.tap(business);
        await tester.pumpAndSettle();
        expect(find.text('OPEN one'), findsOneWidget);
        expect(tester.takeException(), isNull);
      });
    }
  }
}
