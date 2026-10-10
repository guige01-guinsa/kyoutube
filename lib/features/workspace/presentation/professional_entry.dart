import '../../../core/auth/auth_return.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/scout_page.dart';
import '../../../core/widgets/official_channels_card.dart';
import '../../auth/application/auth_providers.dart';
import '../../business/data/business_repository.dart';
import 'workspace_frame.dart' show WorkspaceScope;
import 'workspace_menu.dart';

class ProfessionalEntry extends ConsumerWidget {
  const ProfessionalEntry({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    String tr(String ko, String en) => workspaceText(context, ko, en);
    final account = ref.watch(activeAccountIdProvider);
    return ScoutPageBody(
        child: ListView(padding: const EdgeInsets.all(20), children: [
      if (!WorkspaceScope.hasFrame(context)) ...[
        const Align(
            alignment: Alignment.centerLeft, child: WorkspaceModeButton()),
        const SizedBox(height: 16),
      ],
      ScoutPageHeading(
        eyebrow: tr('업소·전문가 / 작업공간', 'BUSINESS & PROFESSIONAL / WORKSPACE'),
        title: tr('어느 공간에서 일할까요?', 'Choose your work area'),
        subtitle: tr('직원과 함께하는 업무는 소속 업소에서, 혼자 연구하는 자료는 개인 작업실에서 관리하세요.',
            'Use your business for shared work and your personal studio for private research.'),
        icon: Icons.storefront_outlined,
        trailing: OutlinedButton.icon(
          onPressed: () => context.push('/business-workspaces'),
          icon: const Icon(Icons.add_business_outlined),
          label: Text(tr('업소 만들기·초대 참여', 'Create or join a business')),
        ),
      ),
      const SizedBox(height: 24),
      ScoutSectionLabel(
          title: tr('소속 업소', 'Your businesses'),
          subtitle: tr('업소를 선택하면 공동 업무와 담당 메뉴가 열립니다.',
              'Choose a business to open its shared work and your available tools.')),
      if (account == null)
        Card(
            child: ListTile(
                leading: const Icon(Icons.login),
                title: Text(
                    tr('로그인하고 소속 업소 확인', 'Sign in to see your businesses')),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => context.push(loginFor(GoRouterState.of(context).uri.toString(), resume: true))))
      else
        ref.watch(businessWorkspacesProvider).when(
              skipLoadingOnReload: false,
              loading: () => const LinearProgressIndicator(),
              error: (_, __) => Card(
                  child: ListTile(
                      title: Text(tr('소속 업소를 불러오지 못했습니다.',
                          'Could not load your businesses.')),
                      trailing: const Icon(Icons.refresh),
                      onTap: () => ref.invalidate(businessWorkspacesProvider))),
              data: (rows) => rows.isEmpty
                  ? ScoutPanel(
                      child: Text(tr('참여한 업소가 없습니다. 업소를 만들거나 초대 코드로 참여하세요.',
                          'Create a business or join one using your invitation code.')))
                  : ScoutAdaptiveGrid(minTileWidth: 300, children: [
                      for (final row in rows)
                        Card(
                            clipBehavior: Clip.antiAlias,
                            child: InkWell(
                              key: ValueKey('enter-business-${row['id']}'),
                              onTap: () => context
                                  .go('/business-workspaces/${row['id']}'),
                              child: Padding(
                                  padding: const EdgeInsets.all(22),
                                  child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Row(children: [
                                          Container(
                                              padding: const EdgeInsets.all(12),
                                              decoration: BoxDecoration(
                                                  color: ScoutStyle.mint,
                                                  borderRadius:
                                                      BorderRadius.circular(
                                                          12)),
                                              child: const Icon(
                                                  Icons.storefront_outlined,
                                                  color: ScoutStyle.forest)),
                                          const Spacer(),
                                          const Icon(
                                              Icons.arrow_forward_rounded,
                                              size: 20,
                                              color: ScoutStyle.forest),
                                        ]),
                                        const SizedBox(height: 20),
                                        Text(row['name'] as String,
                                            style: Theme.of(context)
                                                .textTheme
                                                .titleLarge),
                                        const SizedBox(height: 8),
                                        Text(
                                            tr('공동 메뉴·레시피 · 구매·입고 · 경영관리',
                                                'Shared menus, recipes, purchasing and management'),
                                            style: Theme.of(context)
                                                .textTheme
                                                .bodySmall),
                                        const SizedBox(height: 16),
                                        Text(tr('업무 시작', 'Open workspace'),
                                            style: Theme.of(context)
                                                .textTheme
                                                .labelLarge
                                                ?.copyWith(
                                                    color: ScoutStyle.forest)),
                                      ])),
                            )),
                    ]),
            ),
      const SizedBox(height: 28),
      ScoutSectionLabel(title: tr('나만의 연구 공간', 'Your private research space')),
      Card(
          child: ListTile(
        key: const Key('enter-personal-studio'),
        contentPadding: const EdgeInsets.all(20),
        leading: const Icon(Icons.science_outlined, color: ScoutStyle.forest),
        title: Text(tr('개인 작업실', 'Personal studio'),
            style: Theme.of(context).textTheme.titleMedium),
        subtitle: Text(tr('내 레시피·배합·원가·구매 기록. 업소에 자동 공유되지 않습니다.',
            'Your recipes, formulas, costs and purchases. Not automatically shared with staff.')),
        trailing: const Icon(Icons.chevron_right),
        onTap: () => context.go('/workspace?area=personal'),
      )),
      const SizedBox(height: 28),
      const OfficialChannelsCard(),
      const SizedBox(height: 20),
    ]));
  }
}
