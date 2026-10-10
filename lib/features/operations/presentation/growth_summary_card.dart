import '../../../core/localization/localized_text.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../core/localization/app_localizations.dart';
import '../../auth/application/auth_providers.dart';
import '../domain/growth_overview.dart';

final growthOverviewProvider =
    FutureProvider.autoDispose<GrowthOverview>((ref) async {
  ref.watch(activeAccountIdProvider);
  final result = await Supabase.instance.client
      .rpc('admin_growth_overview')
      .timeout(const Duration(seconds: 15));
  return GrowthOverview.fromJson(Map<String, dynamic>.from(result as Map));
});

class GrowthSummaryCard extends ConsumerWidget {
  const GrowthSummaryCard({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final en = AppLocalizations.of(context).isEnglish;
    final title = en ? 'Prelaunch recruitment' : '출시 전 사용자 모집';
    final state = ref.watch(growthOverviewProvider);
    return Card(
        child: state.when(
      loading: () => ListTile(
          title: Text(title), subtitle: const LinearProgressIndicator()),
      error: (_, __) => ListTile(
          title: Text(title),
          subtitle: LocalizedText(en
              ? 'Recruitment data is unavailable. Check the server setup and administrator access.'
              : '모집 현황을 불러오지 못했습니다. 서버 설정과 관리자 권한을 확인해 주세요.'),
          trailing: IconButton(
              tooltip: en ? 'Retry' : '다시 시도',
              onPressed: () => ref.invalidate(growthOverviewProvider),
              icon: const Icon(Icons.refresh))),
      data: (data) => ExpansionTile(
        leading: const Icon(Icons.campaign_outlined),
        title: Text(title),
        subtitle: LocalizedText(en
            ? '${data.count('confirmed')} confirmed · ${data.count('confirmed_7d')} in 7 days'
            : '이메일 확인 ${data.count('confirmed')}명 · 최근 7일 ${data.count('confirmed_7d')}명'),
        childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        children: [
          Align(
              alignment: Alignment.centerLeft,
              child: LocalizedText(en
                  ? 'Intake: ${data.intakeEnabled ? 'enabled' : 'paused'} · Email: ${data.deliveryEnabled ? 'enabled' : 'paused'}'
                  : '신청 접수: ${data.intakeEnabled ? '활성' : '정지'} · 이메일: ${data.deliveryEnabled ? '활성' : '정지'}')),
          const SizedBox(height: 12),
          Wrap(spacing: 8, runSpacing: 8, children: [
            Chip(
                label: LocalizedText(
                    '${en ? 'Unconfirmed' : '확인 대기'} ${data.count('pending')}')),
            Chip(
                label: LocalizedText(
                    '${en ? 'Queued emails' : '대기 메일'} ${data.count('queued')}')),
            Chip(
                label: LocalizedText(
                    '${en ? 'Failed emails' : '발송 실패'} ${data.count('failed')}')),
            Chip(
                label: LocalizedText(
                    '${en ? 'Attempts today' : '오늘 발송 시도'} ${data.count('attempts_today')}/${data.count('daily_limit')}')),
          ]),
          for (final channel in data.channels)
            ListTile(
                dense: true,
                contentPadding: EdgeInsets.zero,
                title: LocalizedText('${channel['source']}'),
                subtitle: LocalizedText(en
                    ? '${channel['applications']} requests · ${channel['confirmed']} confirmed'
                    : '신청 ${channel['applications']}명 · 확인 ${channel['confirmed']}명')),
          LocalizedText(
              en
                  ? 'Current retained requests only. Email confirmation is not app installation. Email acceptance by a provider is not proof of delivery. The server sending cap is separate from provider limits.'
                  : '현재 보관 중인 신청 기준입니다. 이메일 확인은 앱 설치 완료가 아닙니다. 발송 요청 접수와 실제 수신은 다르며, 서버 발송 상한과 발송 업체 한도는 별개입니다.',
              style: Theme.of(context).textTheme.bodySmall),
          TextButton.icon(
              onPressed: () => ref.invalidate(growthOverviewProvider),
              icon: const Icon(Icons.refresh),
              label: LocalizedText(en ? 'Refresh recruitment' : '모집 현황 새로고침')),
        ],
      ),
    ));
  }
}
