import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:k_youtube/core/localization/app_localizations.dart';
import 'package:k_youtube/features/operations/presentation/integration_readiness_card.dart';

void main() {
  for(final width in [320.0,1100.0]) {
    testWidgets('Spanish readiness is usable at $width and large text', (tester) async {
      tester.view.physicalSize=Size(width,900);tester.view.devicePixelRatio=1;
      addTearDown(tester.view.resetPhysicalSize);addTearDown(tester.view.resetDevicePixelRatio);
      var calls=0;
      await tester.pumpWidget(ProviderScope(overrides:[
        integrationReadinessProvider.overrideWith((ref) async {calls++;return {'recipe_ai':true,'coupang':false};}),
      ],child:MaterialApp(locale:const Locale('es','419'),
        supportedLocales:AppLocalizations.supportedLocales,
        localizationsDelegates:const[AppLocalizations.delegate,...GlobalMaterialLocalizations.delegates],
        home:MediaQuery(data:MediaQueryData(size:Size(width,900),textScaler:const TextScaler.linear(2)),
          child:const Scaffold(body:SingleChildScrollView(child:IntegrationReadinessCard()))))));
      await tester.pumpAndSettle();
      const es=AppLocalizations(Locale('es','419'));
      expect(find.text(es.translate('External service connections')),findsOneWidget);
      expect(find.textContaining(es.translate('Configured · Live verification required')),findsOneWidget);
      expect(find.textContaining(es.translate('Setup required')),findsNWidgets(6));
      final refresh=find.text(es.translate('Recheck connections'));
      await tester.ensureVisible(refresh);await tester.tap(refresh);await tester.pumpAndSettle();
      expect(calls,2);expect(tester.takeException(),isNull);
    });
  }
}
