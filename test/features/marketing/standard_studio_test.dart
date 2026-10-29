import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:k_youtube/features/marketing/application/marketing_providers.dart';
import 'package:k_youtube/features/marketing/data/standard_studio_repository.dart';
import 'package:k_youtube/features/marketing/presentation/standard_studio_page.dart';
import 'package:k_youtube/features/marketing/presentation/source_recipe_dialog.dart';
import 'package:k_youtube/features/marketing/presentation/standard_studio_summary.dart';

StandardRow overview(
        {String status = 'sample_approved', bool capture = false}) =>
    {
      'config': {
        'enabled': true,
        'standard_enabled': true,
        'standard_worker_seen_at': DateTime.now().toUtc().toIso8601String(),
        'standard_capture_ready': capture,
        'revision': 1,
        'sample_usd': .1,
        'render_usd': .2
      },
      'series': [
        {'id': 'series', 'title': '검사용 시리즈'}
      ],
      'projects': [
        {
          'id': 'project',
          'food': '검사 음식',
          'status': status,
          'revision': 1,
          'plan_revision': 1
        }
      ],
      'jobs': [],
    };

void main() {
  test('recipe URLs normalize shared links without accepting other origins',
      () {
    expect(canonicalRecipeVideoUrl('https://youtu.be/abcdefghijk?si=share'),
        'https://www.youtube.com/watch?v=abcdefghijk');
    expect(
        canonicalRecipeVideoUrl(
            'https://m.youtube.com/watch?v=abcdefghijk&t=3'),
        'https://www.youtube.com/watch?v=abcdefghijk');
    for (final input in [
      'https://youtube.com.evil.test/watch?v=abcdefghijk',
      'https://user@youtube.com/watch?v=abcdefghijk',
      'http://youtube.com/watch?v=abcdefghijk',
      'https://youtu.be/bad'
    ]) {
      expect(canonicalRecipeVideoUrl(input), isNull);
    }
  });
  testWidgets(
      'source start asks only for dish and URL and returns no cost consent',
      (tester) async {
    Map<String, dynamic>? result;
    await tester.pumpWidget(MaterialApp(
        home: Builder(
            builder: (context) => Scaffold(
                body: TextButton(
                    onPressed: () async {
                      result = await showRecipeSourceStart(context);
                    },
                    child: const Text('start'))))));
    await tester.tap(find.text('start'));
    await tester.pumpAndSettle();
    expect(find.byType(TextFormField), findsNWidgets(2));
    await tester.enterText(find.byType(TextFormField).at(0), '불고기');
    await tester.enterText(
        find.byType(TextFormField).at(1), 'https://youtu.be/abcdefghijk');
    await tester.tap(find.text('원고 자동 준비'));
    await tester.pumpAndSettle();
    expect(result?['food'], '불고기');
    expect(
        result?['source_url'], 'https://www.youtube.com/watch?v=abcdefghijk');
    expect(result?.containsKey('cost_confirmed'), isFalse);
  });
  test(
      'secure request IDs are unique UUID v4; errors do not expose server bodies',
      () {
    final ids = List.generate(100, (_) => standardRequestId());
    expect(ids.toSet().length, 100);
    expect(
        ids.every((id) => RegExp(
                r'^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$')
            .hasMatch(id)),
        isTrue);
    expect(standardError(StateError('private provider response')),
        isNot(contains('private provider')));
  });
  testWidgets('non-administrator cannot load pilot data or operate production',
      (tester) async {
    var read = false;
    await tester.pumpWidget(ProviderScope(overrides: [
      marketingAdminProvider.overrideWith((ref) async => false),
      standardStudioProvider.overrideWith((ref) async {
        read = true;
        return overview();
      }),
    ], child: const MaterialApp(home: StandardStudioPage())));
    await tester.pumpAndSettle();
    expect(find.text('마케팅 관리자만 이용할 수 있습니다.'), findsOneWidget);
    expect(read, isFalse);
  });
  testWidgets(
      'missing real capture disables paid render with clear explanation',
      (tester) async {
    await tester.pumpWidget(ProviderScope(overrides: [
      marketingAdminProvider.overrideWith((ref) async => true),
      standardStudioProvider.overrideWith((ref) async => overview()),
    ], child: const MaterialApp(home: StandardStudioPage())));
    await tester.pumpAndSettle();
    expect(
        find.text('한국어 · 원본 레시피 → 원고 확인 → 음성 → 3분 이내 영상 검토'), findsOneWidget);
    final button = tester.widget<FilledButton>(
        find.widgetWithText(FilledButton, '한국어 60초 영상 제작'));
    expect(button.onPressed, isNull);
    expect(find.textContaining('실제 앱 안내 화면 준비 중'), findsOneWidget);
  });
  testWidgets('unknown outcome offers diagnosis, not automatic paid retry',
      (tester) async {
    await tester.pumpWidget(ProviderScope(overrides: [
      marketingAdminProvider.overrideWith((ref) async => true),
      standardStudioProvider
          .overrideWith((ref) async => overview(status: 'needs_review')),
    ], child: const MaterialApp(home: StandardStudioPage())));
    await tester.pumpAndSettle();
    expect(find.textContaining('자동 재시도하지 않습니다. 작업 기록'), findsOneWidget);
    expect(find.widgetWithText(FilledButton, '한국어 60초 영상 제작'), findsNothing);
  });
  testWidgets(
      'existing studio summary exposes completed video without nested menus',
      (tester) async {
    final data = overview(status: 'preview');
    (data['projects'] as List).first['preview'] = {'path': 'private/ko.mp4'};
    await tester.pumpWidget(ProviderScope(
        overrides: [
          standardStudioProvider.overrideWith((ref) async => data),
        ],
        child:
            const MaterialApp(home: Scaffold(body: StandardStudioSummary()))));
    await tester.pumpAndSettle();
    expect(find.text('검사 음식 · 완성 영상 검토'), findsOneWidget);
    expect(find.widgetWithText(OutlinedButton, '영상 미리보기'), findsOneWidget);
    expect(find.text('원고 편집·영상 제작 열기'), findsOneWidget);
  });
}
