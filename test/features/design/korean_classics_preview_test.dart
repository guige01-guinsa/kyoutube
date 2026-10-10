// Optional rendered review using original video thumbnails in ignored .artifacts.
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:k_youtube/core/localization/app_localizations.dart';
import 'package:k_youtube/core/theme/app_theme.dart';
import 'package:k_youtube/features/auth/application/auth_providers.dart';
import 'package:k_youtube/features/home/domain/korean_classics.dart';
import 'package:k_youtube/features/home/presentation/classic_recipe_widgets.dart';
import 'package:k_youtube/features/home/presentation/home_page.dart';

void main() {
  if (!const bool.fromEnvironment('HOME_CAPTURE')) return;
  final images = <String, Uint8List>{};
  setUpAll(() async {
    for (final family in ['Ahem', 'Roboto', 'HomePreview', 'MaterialIcons']) {
      final path = family == 'MaterialIcons'
          ? '.fvm/flutter_sdk/bin/cache/artifacts/material_fonts/MaterialIcons-Regular.otf'
          : 'C:/Windows/Fonts/malgun.ttf';
      final loader = FontLoader(family);
      loader.addFont(
          Future.value(ByteData.sublistView(await File(path).readAsBytes())));
      await loader.load();
    }
    for (final video
        in koreanClassics.expand((r) => [r.videoFor('ko'), r.videoFor('en')])) {
      final file = File('.artifacts/${video.videoId}.jpg');
      if (await file.exists()) {
        images[video.thumbnailUrl] = await file.readAsBytes();
      }
    }
  });
  for (final language in ['ko', 'en']) {
    testWidgets('$language home visual capture', (tester) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(ProviderScope(
          overrides: [
            authUserProvider.overrideWith((_) => Stream.value(null)),
            classicImageProvider.overrideWith((_, url) =>
                images.containsKey(url)
                    ? MemoryImage(images[url]!)
                    : NetworkImage(url)),
          ],
          child: MaterialApp(
            debugShowCheckedModeBanner: false,
            theme: AppTheme.light.copyWith(
                textTheme:
                    AppTheme.light.textTheme.apply(fontFamily: 'HomePreview')),
            locale: Locale(language),
            supportedLocales: AppLocalizations.supportedLocales,
            localizationsDelegates: const [
              AppLocalizations.delegate,
              GlobalMaterialLocalizations.delegate,
              GlobalWidgetsLocalizations.delegate,
              GlobalCupertinoLocalizations.delegate
            ],
            home: const HomePage(),
          )));
      await tester.pumpAndSettle();
      await tester.runAsync(
          () async => Future<void>.delayed(const Duration(milliseconds: 150)));
      await tester.pumpAndSettle();
      await expectLater(
          find.byType(MaterialApp),
          matchesGoldenFile(
              File('.artifacts/home-$language.png').absolute.uri));
      await tester.drag(find.byType(CustomScrollView), const Offset(0, -590));
      await tester.pumpAndSettle();
      await tester.runAsync(
          () async => Future<void>.delayed(const Duration(milliseconds: 150)));
      await tester.pumpAndSettle();
      await expectLater(
          find.byType(MaterialApp),
          matchesGoldenFile(
              File('.artifacts/home-collection-$language.png').absolute.uri));
      expect(tester.takeException(), isNull);
    });
  }
}
