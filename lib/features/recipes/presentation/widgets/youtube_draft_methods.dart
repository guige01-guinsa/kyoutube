import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../core/localization/localized_text.dart';
import '../../../membership/application/membership_providers.dart';

class YoutubeDraftMethods extends ConsumerWidget {
  const YoutubeDraftMethods(
      {super.key, required this.onStandard, required this.onVideo});
  final VoidCallback onStandard, onVideo;
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final membership = ref.watch(membershipInfoProvider);
    final features = ref.watch(membershipFeaturesProvider);
    final premium = (features.valueOrNull?.videoMonthlyLimit ?? 0) > 0;
    final usage = premium ? ref.watch(videoAnalysisUsageProvider) : null;
    final count = usage?.asData?.value;
    final available = premium && count != null && count.used < count.limit;
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      FilledButton.icon(
          key: const ValueKey('standard-youtube-draft'),
          onPressed: onStandard,
          icon: const Icon(Icons.auto_awesome_outlined),
          label: const LocalizedText('기존 자동 초안 만들기')),
      const Padding(
          padding: EdgeInsets.symmetric(vertical: 8),
          child: LocalizedText('영상 제목과 설명으로 빠르게 만듭니다. 기존 AI 사용 한도를 적용합니다.')),
      OutlinedButton.icon(
          key: const ValueKey('video-youtube-draft'),
          onPressed: available ? onVideo : null,
          icon:
              Icon(premium ? Icons.video_library_outlined : Icons.lock_outline),
          label: const LocalizedText('영상 분석으로 초안 만들기')),
      Padding(
          padding: const EdgeInsets.only(top: 8),
          child: LocalizedText(Localizations.localeOf(context).languageCode != 'ko'
              ? 'Plus: 5/month · Business: 20/month · Up to 20 minutes/video'
              : '플러스 월 5회 · 비즈니스 월 20회 · 영상 최대 20분')),
      if (premium && count != null)
        Padding(
            padding: const EdgeInsets.only(top: 6),
            child: LocalizedText(Localizations.localeOf(context).languageCode != 'ko'
                ? 'Video analyses this month: ${count.used} / ${count.limit}'
                : '이번 달 영상 분석: ${count.used} / ${count.limit}')),
      if (membership.isLoading ||
          features.isLoading ||
          (premium && usage?.isLoading == true))
        const LinearProgressIndicator(),
      if (membership.hasError ||
          features.hasError ||
          (premium && usage?.hasError == true))
        TextButton(
            onPressed: () {
              ref.invalidate(membershipInfoProvider);
              ref.invalidate(membershipFeaturesProvider);
              ref.invalidate(videoAnalysisUsageProvider);
            },
            child: const LocalizedText('회원·사용 내역을 확인하지 못했습니다. 다시 확인')),
      const Padding(
          padding: EdgeInsets.symmetric(vertical: 12),
          child: LocalizedText(
              '영상 분석이 시작되면 월 분석 횟수에 포함됩니다. 초안 생성 성공 시 기존 AI 한도에도 1회 반영됩니다. 확인되지 않은 분량·불 세기·시간은 확인 필요로 표시합니다.')),
    ]);
  }
}
