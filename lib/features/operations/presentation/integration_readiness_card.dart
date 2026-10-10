import '../../../core/localization/localized_text.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../core/localization/app_localizations.dart';
import '../../auth/application/auth_providers.dart';

final integrationReadinessProvider = FutureProvider.autoDispose<Map<String, bool>>((ref) async {
  final account = ref.watch(activeAccountIdProvider);
  if (account == null) throw StateError('Sign in required');
  final client = Supabase.instance.client;
  final result = await client.functions.invoke('integration_readiness',method:HttpMethod.get)
      .timeout(const Duration(seconds:20));
  if (client.auth.currentUser?.id != account || result.status != 200 || result.data is! Map) {
    throw StateError('Readiness unavailable');
  }
  return {for (final row in result.data['checks'] as List) row['id'] as String: row['configured'] == true};
});

class IntegrationReadinessCard extends ConsumerWidget {
  const IntegrationReadinessCard({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    String t(String ko, String en) => AppLocalizations.of(context).bilingual(ko,en);
    final state = ref.watch(integrationReadinessProvider);
    const entries = {
      'recipe_ai': ('AI 레시피 초안', 'AI recipe drafts', 'OpenAI API key'),
      'youtube_search': ('YouTube 검색', 'YouTube search', 'YouTube Data API key'),
      'video_ai': ('AI 영상 분석', 'AI video analysis', 'Gemini API key and video analysis setting'),
      'coupang': ('쿠팡 자동 상품 검색·링크', 'Coupang product search and links', 'Coupang Partners Access Key and Secret Key'),
      'play_billing': ('Google Play 구매 검증', 'Google Play purchase verification', 'Google Play service account with Play Console permissions'),
      'play_notifications': ('구독 갱신·취소 알림', 'Subscription renewal and cancellation notices', 'Google Play RTDN audience and service account email'),
      'operations_push': ('운영 휴대폰 알림', 'Operations phone notifications', 'Firebase service account and operations monitor secret'),
    };
    return Card(child: Padding(padding: const EdgeInsets.all(16), child: Column(
      crossAxisAlignment:CrossAxisAlignment.stretch, children:[
        Text(t('외부 서비스 연결 상태','External service connections'),style:Theme.of(context).textTheme.titleLarge),
        Text(t('설정 등록 여부입니다. 실제 결제·알림 성공 여부는 별도 검증이 필요합니다.',
            'This checks configuration only. Successful purchases and notifications still require live verification.')),
        state.when(loading:()=>const LinearProgressIndicator(), error:(_,__)=>Column(children:[
          Text(t('관리자 2단계 인증과 서버 연결 상태를 확인한 뒤 다시 시도하세요.',
              'Check administrator two-step verification and server connectivity, then retry.')),
          TextButton(onPressed:()=>context.push('/account/mfa'),child:Text(t('2단계 인증 확인','Check two-step verification'))),
        ]), data:(checks)=>Column(children:[
          for (final e in entries.entries) ListTile(
            contentPadding:EdgeInsets.zero,
            leading:Icon(checks[e.key] == true ? Icons.check_circle_outline : Icons.settings_outlined),
            title:Text(t(e.value.$1,e.value.$2)),
            subtitle:LocalizedText(checks[e.key] == true ? t('설정 등록됨 · 실제 호출 검증 필요','Configured · Live verification required')
                : '${t('설정 필요','Setup required')}: ${t(e.value.$3,e.value.$3)}'),
          ),
          Text(t('발급된 쿠팡 제휴 링크는 API 연결 전에도 직접 등록할 수 있습니다. 비밀 키는 앱에 입력하지 않고 서버 보안 설정에 등록합니다.',
              'You can register issued Coupang affiliate links before API setup. Add secret keys to server secrets, never to the app.')),
        ])),
        Align(alignment:Alignment.centerRight,child:TextButton.icon(
          onPressed:()=>ref.invalidate(integrationReadinessProvider),icon:const Icon(Icons.refresh),
          label:Text(t('연결 상태 다시 확인','Recheck connections')))),
      ],
    )));
  }
}
