import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/localization/localized_text.dart';
import '../application/membership_providers.dart';

class MembershipFeaturesCard extends ConsumerWidget {
  const MembershipFeaturesCard({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final features = ref.watch(membershipFeaturesProvider);
    return Card(
        child: Padding(
      padding: const EdgeInsets.all(18),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        LocalizedText('내가 사용할 수 있는 기능',
            style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 12),
        const LocalizedText('레시피 저장 · 장보기 · 인분 환산 · 버전 관리'),
        const SizedBox(height: 8),
        features.when(
          data: (value) =>
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            LocalizedText(value.canManageCosts && value.canManageSales
                ? '원가 · 판매가 · 매출 관리 이용 가능'
                : '원가 · 판매가 · 매출은 비즈니스에서 제공합니다.'),
            if (value.canShareRequestPdf) ...[
              const SizedBox(height: 8),
              const LocalizedText('구매 요청서 작성 · 텍스트 및 PDF 공유'),
            ],
            const SizedBox(height: 8),
            if (value.videoMonthlyLimit > 0)
              LocalizedText(
                  '${context.tr('영상 분석')} · ${value.videoMonthlyLimit} ${context.tr('회/월')}')
            else
              const LocalizedText('영상 분석은 플러스·비즈니스에서 제공합니다.'),
          ]),
          loading: () => const LinearProgressIndicator(),
          error: (_, __) => TextButton.icon(
              onPressed: () => ref.invalidate(membershipFeaturesProvider),
              icon: const Icon(Icons.refresh),
              label: const LocalizedText('이용 권한을 확인하지 못했습니다.')),
        ),
      ]),
    ));
  }
}
