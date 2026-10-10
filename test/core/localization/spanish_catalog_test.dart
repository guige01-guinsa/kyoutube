import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:k_youtube/core/localization/app_localizations.dart';
import 'package:k_youtube/core/localization/localized_text.dart';
import 'package:k_youtube/core/localization/spanish_ui_translations.dart';
import 'package:k_youtube/core/localization/spanish_translation.dart';
import 'package:k_youtube/core/localization/ui_translations.dart';

void main() {
  const es=AppLocalizations(Locale('es','419'));
  test('every English catalog phrase has a Spanish translation', () {
    expect(koreanUiTranslations.values.where((s)=>s.trim().isNotEmpty &&
      !spanishUiTranslations.containsKey(s)).toSet(), isEmpty);
  });
  test('dynamic Spanish labels preserve quantities and original user values', () {
    expect(translateSpanish('3 ingredients · 4 steps'),'3 ingredientes · 4 pasos');
    expect(translateSpanish('3 ingredients · 4 need review'),'3 ingredientes · 4 requieren revisión');
    expect(es.bilingual('다시 시도', 'Try again'),'Intentar de nuevo');
    // The source is neither an interface phrase nor a template: leave it alone.
    expect(translateSpanish('Mi receta personal de 김치 {1}'),'Mi receta personal de 김치 {1}');
    const source='Edit ingredient details for 김치 {1}';
    expect(translateSpanish(source),contains('김치 {1}'));
    expect(translateSpanish(source),isNot(source));
  });
  testWidgets('Spanish fixed copy wraps at a narrow width with large text', (tester) async {
    await tester.binding.setSurfaceSize(const Size(320,640));
    addTearDown(()=>tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(MaterialApp(locale:const Locale('es','419'),
      supportedLocales:AppLocalizations.supportedLocales,
      localizationsDelegates:const [AppLocalizations.delegate,...GlobalMaterialLocalizations.delegates],
      home:MediaQuery(data:const MediaQueryData(textScaler:TextScaler.linear(1.5)),
        child:Scaffold(body:ListView(children:const [
          LocalizedText('External service connections'),
          LocalizedText('Another device changed this list. Your edits are kept on this device.'),
          LocalizedText('3 ingredients · 4 steps'),
        ])))));
    await tester.pumpAndSettle();
    expect(find.text('3 ingredientes · 4 pasos'),findsOneWidget);
    expect(find.text('External service connections'),findsNothing);
    expect(tester.takeException(),isNull);
  });
}
