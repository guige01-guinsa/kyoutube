import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:k_youtube/core/localization/app_localizations.dart';
import 'package:k_youtube/core/theme/app_theme.dart';
import 'package:k_youtube/core/widgets/official_channels_card.dart';

void main() {
  setUpAll(() async {
    await (FontLoader('MaterialIcons')
          ..addFont(Future.value(ByteData.sublistView(await File(
                  '.fvm/flutter_sdk/bin/cache/artifacts/material_fonts/MaterialIcons-Regular.otf')
              .readAsBytes()))))
        .load();
    for (final name in ['Roboto', 'Ahem']) {
      await (FontLoader(name)
            ..addFont(rootBundle.load('assets/fonts/NanumGothic-Regular.ttf')))
          .load();
    }
  });
  for (final width in [390.0, 1100.0]) {
    testWidgets('official guides preview $width', (tester) async {
      tester.view.physicalSize = Size(width, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final key = GlobalKey();
      await tester.pumpWidget(MaterialApp(
        theme: AppTheme.light,
        locale: const Locale('ko'),
        supportedLocales: AppLocalizations.supportedLocales,
        localizationsDelegates: const [
          AppLocalizations.delegate,
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate
        ],
        home: RepaintBoundary(
            key: key,
            child: Scaffold(
                appBar: AppBar(title: const Text('레시피 스카우트')),
                body: SingleChildScrollView(
                    child: Padding(
                        padding: const EdgeInsets.all(20),
                        child: OfficialChannelsCard(
                            openUrl: (_) async => true))))),
      ));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      await tester.runAsync(() async {
        final boundary =
            key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
        final image = await boundary.toImage();
        final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
        await File('.artifacts/official-channels-preview-${width.toInt()}.png')
            .writeAsBytes(bytes!.buffer.asUint8List());
        image.dispose();
      });
    });
  }
}
