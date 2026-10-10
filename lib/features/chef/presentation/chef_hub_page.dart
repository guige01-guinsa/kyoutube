import 'package:k_youtube/core/widgets/scout_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/localization/localized_text.dart';
import '../../../core/router/app_router.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/scout_navigation_bar.dart';
import '../../auth/application/auth_providers.dart';
import '../../recipes/application/recipe_providers.dart';
import '../data/chef_access.dart';

/// A task-oriented entry point. Recipe documents and financial data stay in
/// their existing, owner-scoped repositories and server-protected routes.
class ChefHubPage extends ConsumerWidget {
  const ChefHubPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final account = ref.watch(activeAccountIdProvider);
    return Scaffold(
      appBar: AppBar(title: const LocalizedText('셰프 작업실')),
      bottomNavigationBar: const ScoutNavigationBar(selectedIndex: 3),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: ScoutStyle.contentWidth),
          child: _ChefHubContents(key: ValueKey(account), accountId: account),
        ),
      ),
    );
  }
}

class _ChefHubContents extends ConsumerStatefulWidget {
  const _ChefHubContents({super.key, required this.accountId});
  final String? accountId;

  @override
  ConsumerState<_ChefHubContents> createState() => _ChefHubContentsState();
}

class _ChefHubContentsState extends ConsumerState<_ChefHubContents> {
  String _search = '';

  @override
  Widget build(BuildContext context) {
    final signedIn = widget.accountId != null;
    final access = signedIn ? ref.watch(chefPaidAccessProvider) : null;
    final recipes =
        signedIn ? ref.watch(creatorRecipesProvider(_search)) : null;
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
      children: [
        ScoutPageHeading(
          title: context.tr('맛의 기록을, 주방의 기준으로.'),
          subtitle: context.tr('레시피를 선택해 인분과 수율을 조정하고, 버전별 변화를 확인하세요.'),
          icon: Icons.science_outlined,
        ),
        const SizedBox(height: 12),
        _HubAction(
            icon: Icons.school_outlined,
            title: '업소·전문가 튜토리얼',
            subtitle: '인분·원가·매출·구매 요청을 단계별로 익혀보세요.',
            onTap: () =>
                context.push('${AppRoutes.guide}?audience=professional')),
        const SizedBox(height: 12),
        if (!signedIn)
          Card(
              child: Padding(
            padding: const EdgeInsets.all(16),
            child:
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              const LocalizedText('인분 환산과 버전 관리는 무료로 시작할 수 있습니다.'),
              const SizedBox(height: 8),
              FilledButton.icon(
                onPressed: () => context.push(AppRoutes.login),
                icon: const Icon(Icons.login),
                label: const LocalizedText('로그인하고 시작'),
              ),
            ]),
          ))
        else ...[
          access!.when(
            data: (paid) => paid
                ? _HubAction(
                    icon: Icons.bar_chart_outlined,
                    title: '매출 현황',
                    subtitle: '판매 수량·매출·원가를 한눈에 확인하세요.',
                    onTap: () => context.push(AppRoutes.chefSales))
                : const ChefPaidNotice(),
            loading: () => const LinearProgressIndicator(),
            error: (_, __) => _HubAction(
                icon: Icons.refresh,
                title: '이용 권한을 확인하지 못했습니다.',
                subtitle: '다시 시도',
                onTap: () => ref.invalidate(chefPaidAccessProvider)),
          ),
          _HubAction(
              icon: Icons.receipt_long_outlined,
              title: '구매 요청서',
              subtitle: '구매처에 보낼 목록과 입고 기록을 관리하세요.',
              onTap: () => context.push(AppRoutes.supplierRequests)),
          const SizedBox(height: 20),
          LocalizedText('작업할 레시피',
              style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 8),
          const LocalizedText('직접 만들거나 내 레시피로 복사한 레시피가 표시됩니다.'),
          const SizedBox(height: 12),
          TextField(
            key: const Key('chef-recipe-search'),
            decoration: InputDecoration(
                labelText: context.tr('내 레시피 검색'),
                prefixIcon: const Icon(Icons.search)),
            onChanged: (value) => setState(() => _search = value),
          ),
          const SizedBox(height: 12),
          recipes!.when(
            data: (items) => items.isEmpty
                ? _HubAction(
                    icon: Icons.menu_book_outlined,
                    title: '작업할 레시피를 준비해 보세요.',
                    subtitle: '내 레시피에서 만들거나 저장한 레시피를 확인하세요.',
                    onTap: () => context.go(AppRoutes.myRecipes))
                : Column(children: [
                    for (final recipe in items)
                      Card(
                          child: ListTile(
                        key: ValueKey('chef-recipe-${recipe.id}'),
                        leading: const Icon(Icons.menu_book_outlined),
                        title: Text(recipe.title),
                        subtitle: const LocalizedText('인분 · 수율 · 버전'),
                        trailing: const Icon(Icons.chevron_right),
                        onTap: () =>
                            context.push(AppRoutes.chefWorkspace(recipe.id)),
                      )),
                  ]),
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (_, __) => _HubAction(
                icon: Icons.refresh,
                title: '레시피를 불러오지 못했습니다',
                subtitle: '다시 시도',
                onTap: () => ref.invalidate(creatorRecipesProvider(_search))),
          ),
        ],
      ],
    );
  }
}

class _HubAction extends StatelessWidget {
  const _HubAction(
      {required this.icon,
      required this.title,
      required this.subtitle,
      required this.onTap});
  final IconData icon;
  final String title, subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Card(
          child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        leading: Icon(icon),
        title: LocalizedText(title),
        subtitle: LocalizedText(subtitle),
        trailing: const Icon(Icons.chevron_right),
        onTap: onTap,
      ));
}
