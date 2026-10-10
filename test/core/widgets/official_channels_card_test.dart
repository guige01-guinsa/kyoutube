import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:k_youtube/core/config/official_channels.dart';
import 'package:k_youtube/core/localization/app_localizations.dart';
import 'package:k_youtube/core/widgets/official_channels_card.dart';

Future<void> showCard(WidgetTester tester,
    {String language = 'ko',
    double scale = 1,
    required Future<bool> Function(Uri) open}) async {
  await tester.pumpWidget(MaterialApp(
    locale: Locale(language),
    supportedLocales: const [Locale('ko'), Locale('en')],
    localizationsDelegates: const [
      AppLocalizations.delegate,
      GlobalMaterialLocalizations.delegate,
      GlobalWidgetsLocalizations.delegate,
      GlobalCupertinoLocalizations.delegate
    ],
    builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context)
            .copyWith(textScaler: TextScaler.linear(scale)),
        child: child!),
    home: Scaffold(
        body:
            SingleChildScrollView(child: OfficialChannelsCard(openUrl: open))),
  ));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('no eager network; taps open only the fixed public destinations',
      (tester) async {
    final urls = <Uri>[];
    await showCard(tester, open: (url) async {
      urls.add(url);
      return true;
    });
    expect(urls, isEmpty);
    for (final key in ['official-youtube', 'official-blog']) {
      await tester.tap(find.byKey(Key(key)));
      await tester.pumpAndSettle();
    }
    expect(urls.map((u) => u.toString()).toList(), [
      'https://www.youtube.com/@guige01',
      'https://blog.naver.com/toktoknr'
    ]);
    expect(
        urls.every((u) =>
            u.scheme == 'https' &&
            !u.hasQuery &&
            !u.hasFragment &&
            u.userInfo.isEmpty),
        isTrue);
  });
  for (final throws in [false, true]) {
    testWidgets(
        'launcher failure ($throws) offers the public URL without exception details',
        (tester) async {
      await showCard(tester, open: (_) async {
        if (throws) throw StateError('private platform detail');
        return false;
      });
      await tester.tap(find.byKey(const Key('official-blog')));
      await tester.pumpAndSettle();
      expect(find.text('링크를 열지 못했어요'), findsOneWidget);
      expect(find.text(OfficialChannel.blog.url), findsOneWidget);
      expect(find.textContaining('private platform detail'), findsNothing);
      await tester.tap(find.text('닫기'));
      await tester.pumpAndSettle();
      expect(find.byType(AlertDialog), findsNothing);
    });
  }
  testWidgets('pending launch blocks duplicate taps and tolerates disposal',
      (tester) async {
    final pending = Completer<bool>();
    var calls = 0;
    await showCard(tester, open: (_) {
      calls++;
      return pending.future;
    });
    await tester.tap(find.byKey(const Key('official-youtube')));
    await tester.pump();
    await tester.tap(find.byKey(const Key('official-blog')));
    await tester.pump();
    expect(calls, 1);
    await tester.pumpWidget(const SizedBox());
    pending.complete(false);
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });
  for (final language in ['ko', 'en']) {
    testWidgets('$language stays usable at 320px and 200% text',
        (tester) async {
      tester.view.physicalSize = const Size(320, 1200);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await showCard(tester,
          language: language, scale: 2, open: (_) async => true);
      final blog = find.byKey(const Key('official-blog'));
      await tester.ensureVisible(blog);
      await tester.pumpAndSettle();
      expect(blog.hitTestable(), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }
}
