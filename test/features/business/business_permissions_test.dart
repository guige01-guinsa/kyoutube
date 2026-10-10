import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:k_youtube/core/localization/app_localizations.dart';
import 'package:k_youtube/core/theme/app_theme.dart';
import 'package:k_youtube/features/business/domain/business_workspace.dart';
import 'package:k_youtube/features/business/presentation/business_pages.dart';

BusinessContext member(Set<String> p,
        {bool paid = true, bool approval = true}) =>
    BusinessContext(
        id: 'workspace',
        name: 'Team kitchen',
        owner: false,
        paid: paid,
        approval: approval,
        permissions: p);
BusinessRecord purchase(String status) => BusinessRecord(
    id: 'request',
    workspace: 'workspace',
    kind: 'purchase',
    title: 'Tofu',
    data: const {},
    status: status,
    revision: 1);
void main() {
  test(
      'purchaser cannot view finance or approve but can confirm sharing but must receive through the item workflow',
      () {
    final p = member(businessRolePermissions['purchasing']!);
    expect(p.can('finance.read'), isFalse);
    expect(p.can('purchases.approve'), isFalse);
    expect(businessNextStatuses(p, purchase('draft')), ['review', 'cancelled']);
    expect(businessNextStatuses(p, purchase('review')), ['draft', 'cancelled']);
    expect(businessNextStatuses(p, purchase('approved')), contains('sent'));
    expect(
        businessNextStatuses(p, purchase('sent')), isNot(contains('received')));
    expect(businessNextStatuses(p, purchase('received')), isEmpty);
  });
  test(
      'culinary staff can research recipes but cannot alter purchasing or sales',
      () {
    final p = member(businessRolePermissions['culinary']!);
    expect(p.can('recipes.write'), isTrue);
    expect(p.can('purchasing.read'), isTrue);
    expect(p.can('purchasing.write'), isFalse);
    expect(p.can('finance.read'), isFalse);
    expect(businessNextStatuses(p, purchase('draft')), isEmpty);
  });
  test('manager approves purchases without impersonating the purchaser', () {
    final p = member(businessRolePermissions['management']!);
    expect(businessNextStatuses(p, purchase('review')), contains('approved'));
    expect(
        businessNextStatuses(p, purchase('approved')), isNot(contains('sent')));
    expect(p.can('finance.write'), isTrue);
  });
  test(
      'read-only grants and expired entitlement cannot become write or financial access',
      () {
    final p = member({'recipes.read', 'purchasing.read'});
    expect(p.can('recipes.write'), isFalse);
    expect(businessNextStatuses(p, purchase('review')), isEmpty);
    final expired = member(businessPermissions.toSet(), paid: false);
    expect(expired.can('finance.read'), isFalse);
    expect(expired.can('recipes.write'), isFalse);
    expect(expired.can('purchasing.read'), isTrue);
  });
  test('owner-disabled approval lets the purchaser finalize a draft', () {
    final p = member(businessRolePermissions['purchasing']!, approval: false);
    expect(
        businessNextStatuses(p, purchase('draft')), ['approved', 'cancelled']);
  });
  for (final language in ['ko', 'en']) {
    testWidgets(
        '$language permission selection maintains read/write dependencies at large text',
        (tester) async {
      tester.view.physicalSize = const Size(360, 850);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      var result = <String>{};
      await tester.pumpWidget(ProviderScope(
          child: MaterialApp(
              theme: AppTheme.light,
              locale: Locale(language),
              supportedLocales: AppLocalizations.supportedLocales,
              localizationsDelegates: const [
                AppLocalizations.delegate,
                GlobalMaterialLocalizations.delegate,
                GlobalWidgetsLocalizations.delegate,
                GlobalCupertinoLocalizations.delegate
              ],
              home: Scaffold(
                  body: SingleChildScrollView(
                      child: BusinessPermissionPicker(
                          initial: const {}, onChanged: (v) => result = v))))));
      final writer = find.byKey(const ValueKey('permission-recipes.write'));
      await tester.ensureVisible(writer);
      await tester.tap(writer);
      await tester.pump();
      expect(result, containsAll(['recipes.read', 'recipes.write']));
      final reader = find.byKey(const ValueKey('permission-recipes.read'));
      await tester.ensureVisible(reader);
      await tester.tap(reader);
      await tester.pump();
      expect(result, isNot(contains('recipes.write')));
      tester.platformDispatcher.textScaleFactorTestValue = 2;
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
      await tester.pump();
      expect(tester.takeException(), isNull);
    });
  }
}
