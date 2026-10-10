import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:k_youtube/core/localization/app_localizations.dart';
import 'package:k_youtube/core/theme/app_theme.dart';
import 'package:k_youtube/features/business/domain/business_workspace.dart';
import 'package:k_youtube/features/business/presentation/business_record_list.dart';
import '../workspace/workspace_reorganization_test.dart'
    show pumpShared, capturePreview;
import 'business_flow_test.dart' show MemoryBusiness, pumpBusiness;

void main() {
  setUpAll(() async {
    await (FontLoader('ReorgPreview')
          ..addFont(rootBundle.load('assets/fonts/NanumGothic-Regular.ttf')))
        .load();
    final theme = AppTheme.light;
    final families = <String>{
      if (theme.chipTheme.labelStyle?.fontFamily case final String family)
        family,
      if (theme.filledButtonTheme.style?.textStyle?.resolve({})?.fontFamily
          case final String family)
        family,
    };
    for (final family in families) {
      await (FontLoader(family)
            ..addFont(rootBundle.load('assets/fonts/NanumGothic-Regular.ttf')))
          .load();
    }
    await (FontLoader('MaterialIcons')
          ..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf')))
        .load();
  });

  for (final viewport in [(320.0, 2.0), (1100.0, 1.0)]) {
    testWidgets('records remain readable and actionable at $viewport',
        (tester) async {
      tester.view.physicalSize = Size(viewport.$1, 1000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      BusinessRecord? opened;
      final record = BusinessRecord(
          id: 'recipe',
          workspace: 'shop',
          kind: 'recipe',
          title: 'Seasonal menu recipe with a detailed descriptive name',
          data: const {},
          revision: 12,
          updatedAt: DateTime(2026, 9, 24));
      await tester.pumpWidget(MaterialApp(
          theme: AppTheme.light,
          locale: const Locale('en'),
          supportedLocales: AppLocalizations.supportedLocales,
          localizationsDelegates: const [
            AppLocalizations.delegate,
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate
          ],
          builder: (context, child) => MediaQuery(
              data: MediaQuery.of(context)
                  .copyWith(textScaler: TextScaler.linear(viewport.$2)),
              child: child!),
          home: Scaffold(
              body: SingleChildScrollView(
                  child: BusinessRecordList(
                      records: [record],
                      statusLabel: (_) => 'Recipe',
                      onOpen: (r) => opened = r)))));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(
          find.byKey(Key(viewport.$1 > 760
              ? 'business-record-table'
              : 'business-record-cards')),
          findsOneWidget);
      expect(find.text('v12'), findsOneWidget);
      expect(find.textContaining('2026'), findsOneWidget);
      await tester.tap(find.text(record.title));
      expect(opened, same(record));
    });
  }

  testWidgets('purchasing home keeps primary action and excludes finance tools',
      (tester) async {
    final repo = MemoryBusiness(businessRolePermissions['purchasing']!);
    await pumpBusiness(tester, repo, width: 320, textScale: 2);
    expect(find.text('판매 메뉴로 빠른 구매'), findsOneWidget);
    expect(find.textContaining('경영관리'), findsNothing);
    expect(find.text('구매 승인 대기 확인'), findsNothing);
    expect(tester.takeException(), isNull);
    expect(repo.writes, 0);
  });

  testWidgets('purchasing page exposes planning and tools with scoped search',
      (tester) async {
    final repo = MemoryBusiness(businessRolePermissions['purchasing']!);
    await pumpBusiness(tester, repo,
        initial: '/business-workspaces/shop?section=purchasing');
    expect(find.text('업체·재료·요청서 검색'), findsOneWidget);
    expect(find.textContaining('현재 불러온 50개'), findsOneWidget);
    expect(find.byKey(const Key('business-purchase-start')), findsOneWidget);
    expect(find.text('업소 거래처·상품'), findsOneWidget);
    expect(tester.takeException(), isNull);
    expect(repo.writes, 0);
  });
  for (final locale in ['ko', 'en']) {
    testWidgets('purchasing tools fit 320px large text in $locale',
        (tester) async {
      final repo = MemoryBusiness(businessRolePermissions['purchasing']!);
      await pumpBusiness(tester, repo,
          locale: locale,
          width: 320,
          textScale: 2,
          initial: '/business-workspaces/shop?section=purchasing');
      expect(tester.takeException(), isNull);
      await tester.scrollUntilVisible(
          find.byKey(const ValueKey('business-search-purchase')), 200,
          scrollable: find.byType(Scrollable).first);
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(repo.writes, 0);
    });
  }
  for (final scenario in [
    ('home', 1440.0),
    ('records', 1440.0),
    ('records', 390.0)
  ]) {
    testWidgets('shared design preview ${scenario.$1} ${scenario.$2}',
        (tester) async {
      final repo = MemoryBusiness(businessPermissions.toSet());
      for (final (index, title)
          in ['월요일 채소 구매', '주간 양념 재료', '판매 메뉴용 육류', '주말 추가 구매'].indexed) {
        repo.data['purchase-$index'] = BusinessRecord(
            id: 'purchase-$index',
            workspace: 'shop',
            kind: 'purchase',
            title: title,
            data: const {},
            status: ['draft', 'review', 'approved', 'sent'][index],
            revision: index + 1,
            updatedAt: DateTime(2026, 9, 24));
      }
      final key = GlobalKey();
      await pumpShared(tester,
          repo: repo,
          width: scenario.$2,
          capture: key,
          initial: scenario.$1 == 'home'
              ? '/business-workspaces/shop'
              : '/business-workspaces/shop?section=purchasing');
      if (scenario.$1 == 'records' && scenario.$2 < 1000) {
        await tester
            .ensureVisible(find.byKey(const Key('business-record-cards')));
        await tester.pumpAndSettle();
      }
      expect(tester.takeException(), isNull);
      await capturePreview(
          tester, key, 'business-${scenario.$1}-${scenario.$2.toInt()}');
    });
  }
}
