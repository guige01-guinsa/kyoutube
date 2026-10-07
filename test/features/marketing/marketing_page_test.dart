import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:k_youtube/features/marketing/application/marketing_providers.dart';
import 'package:k_youtube/features/marketing/presentation/marketing_page.dart';

void main() {
  testWidgets('non-admin cannot generate or approve marketing', (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: <Override>[
          marketingAdminProvider.overrideWith((ref) async => false),
        ],
        child: const MaterialApp(home: MarketingPage()),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('마케팅 관리자만 이용할 수 있습니다.'), findsOneWidget);
    expect(find.text('AI 홍보 초안 생성'), findsNothing);
  });

  testWidgets(
    'draft exposes all scenes and approval, uncertain upload has no retry',
    (tester) async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: <Override>[
            marketingAdminProvider.overrideWith((ref) async => true),
            marketingCampaignsProvider.overrideWith(
              (ref) async => <Map<String, dynamic>>[
                <String, dynamic>{
                  'id': 'draft',
                  'title': '장보기 정리',
                  'description': '앱 기능 안내',
                  'status': 'draft',
                  'scenes': <String>['첫 장면', '둘째 장면', '마지막 장면'],
                },
                <String, dynamic>{
                  'id': 'uncertain',
                  'title': '확인 대기',
                  'description': '연결 중단',
                  'status': 'needs_review',
                  'scenes': <String>['1', '2', '3'],
                },
              ],
            ),
          ],
          child: const MaterialApp(home: MarketingPage()),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('장면 1 · 8초\n첫 장면'), findsOneWidget);
      expect(find.text('장면 2 · 8초\n둘째 장면'), findsOneWidget);
      expect(find.text('장면 3 · 8초\n마지막 장면'), findsOneWidget);
      expect(find.text('검토 완료 · 예약 승인'), findsOneWidget);
      expect(find.text('채널에서 결과 확인 필요'), findsOneWidget);
      expect(find.text('재시도'), findsNothing);
    },
  );
}
