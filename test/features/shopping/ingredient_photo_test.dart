import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:k_youtube/features/shopping/domain/ingredient_photo.dart';
import 'package:k_youtube/features/shopping/presentation/ingredient_thumbnail.dart';

void main() {
  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    final font = FontLoader('RecipeScoutKR')
      ..addFont(rootBundle.load('assets/fonts/NanumGothic-Regular.ttf'));
    await font.load();
    final icons = FontLoader('MaterialIcons')
      ..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'));
    await icons.load();
  });
  test('safe aliases preserve food identity instead of matching substrings',
      () {
    expect(IngredientPhoto.find('국내산 손질 양파')?.id, 'onion');
    expect(IngredientPhoto.find('다진 마늘')?.id, 'minced-garlic');
    expect(IngredientPhoto.find('통마늘')?.id, 'garlic');
    expect(IngredientPhoto.find('  Green Onions ')?.id, 'green-onion');
    expect(IngredientPhoto.find('고추장')?.id, 'paste');
    expect(IngredientPhoto.find('표고버섯')?.id, 'mushrooms');
    expect(IngredientPhoto.find('소고기 불고기용')?.id, 'beef-cuts');
    expect(IngredientPhoto.find('냉동 새우')?.id, 'seafood');
    expect(IngredientPhoto.find('부침가루')?.id, 'grains');
    for (final name in [
      '양파즙',
      '마늘소스',
      '감자전분',
      '토마토케첩',
      '간장게장',
      '달걀국',
      '순두부',
      '닭발',
      '고구마',
      '미등록재료'
    ]) {
      expect(IngredientPhoto.find(name), isNull, reason: name);
    }
  });

  test('all catalog photos are valid small bundled images', () async {
    TestWidgetsFlutterBinding.ensureInitialized();
    expect(IngredientPhoto.catalog.map((p) => p.id).toSet().length,
        IngredientPhoto.catalog.length);
    for (final photo in IngredientPhoto.catalog) {
      final bytes = File(photo.asset).readAsBytesSync();
      expect(bytes.length, lessThan(50000));
      final codec = await ui.instantiateImageCodec(bytes);
      final frame = await codec.getNextFrame();
      expect(frame.image.width, 256);
      expect(frame.image.height, 256);
      frame.image.dispose();
      codec.dispose();
    }
    final fallback = File(IngredientPhoto.fallbackAsset).readAsBytesSync();
    expect(fallback.length, lessThan(50000));
    final fallbackCodec = await ui.instantiateImageCodec(fallback);
    final fallbackFrame = await fallbackCodec.getNextFrame();
    expect(fallbackFrame.image.width, 256);
    expect(fallbackFrame.image.height, 256);
    fallbackFrame.image.dispose();
    fallbackCodec.dispose();
  });

  testWidgets('representative photos are labelled and fit a compact phone row',
      (tester) async {
    tester.view.physicalSize = const Size(320, 700);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final capture = GlobalKey();
    await tester.pumpWidget(MaterialApp(
        locale: const Locale('ko'),
        supportedLocales: const [Locale('ko')],
        localizationsDelegates: GlobalMaterialLocalizations.delegates,
        theme: ThemeData(fontFamily: 'RecipeScoutKR'),
        home: Scaffold(
            body: RepaintBoundary(
          key: capture,
          child: ColoredBox(
              color: const Color(0xFFF9F6F1),
              child: ListView(padding: const EdgeInsets.all(12), children: [
                for (final name in ['양파', '당근', '다진마늘', '미등록재료'])
                  Card(
                      child: Padding(
                          padding: const EdgeInsets.all(12),
                          child: Row(children: [
                            IngredientThumbnail(ingredient: name),
                            const SizedBox(width: 10),
                            Expanded(child: Text(name)),
                            FilledButton(
                                onPressed: () {}, child: const Text('구매')),
                          ]))),
              ])),
        ))));
    await tester.runAsync(() async {
      await Future<void>.delayed(const Duration(milliseconds: 250));
    });
    await tester.pumpAndSettle();
    expect(find.byType(Image), findsNWidgets(4));
    expect(find.text('대표'), findsNWidgets(4));
    expect(find.byIcon(Icons.restaurant_outlined), findsNothing);
    expect(tester.takeException(), isNull);
    if (const bool.fromEnvironment('CAPTURE_INGREDIENT_PREVIEW')) {
      await tester.runAsync(() async {
        final boundary = capture.currentContext!.findRenderObject()!
            as RenderRepaintBoundary;
        final image = await boundary.toImage(pixelRatio: 2);
        final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
        final file = File('output/ingredient-photos/phone-preview.png');
        await file.parent.create(recursive: true);
        await file.writeAsBytes(bytes!.buffer.asUint8List());
        image.dispose();
      });
    }
  });
}
