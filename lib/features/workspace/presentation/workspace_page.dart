import '../../../core/localization/localized_text.dart';
import '../../../core/auth/auth_return.dart';
import 'package:flutter/material.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/scout_page.dart';
import '../../../core/router/app_router.dart';
import 'workspace_frame.dart' show WorkspaceScope;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../core/widgets/scout_navigation_bar.dart';
import '../../../core/widgets/official_channels_card.dart';
import '../../auth/application/auth_providers.dart';
import '../../membership/application/membership_providers.dart';
import '../../recipes/application/recipe_providers.dart';
import '../../recipes/application/recipe_library_provider.dart';
import '../../shopping/data/supplier_request_repository.dart';
import '../../suppliers/data/supplier_catalog_repository.dart';
import '../application/workspace_profile_controller.dart';
import '../domain/workspace_profile.dart';
import 'workspace_menu.dart';
import '../../home/presentation/home_page.dart';
import '../../shopping/application/purchase_workspace.dart';
import 'workspace_preferences_page.dart';
import '../../chef/data/chef_access.dart';
import '../../chef/domain/chef_sales.dart';
import '../application/professional_summary.dart';
part 'professional_workspace_home.dart';

class WorkspacePage extends ConsumerWidget {
  const WorkspacePage({super.key, this.personalStudio = false});
  final bool personalStudio;
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final account = ref.watch(activeAccountIdProvider);
    final profile = ref.watch(workspaceProfileProvider);
    if (!personalStudio &&
        !profile.isLoading &&
        !profile.hasError &&
        profile.valueOrNull?.active != WorkspaceMode.supplier) {
      return const HomePage();
    }
    return Scaffold(
      appBar:
          AppBar(title: Text(workspaceText(context, '홈', 'Home')), actions: [
        TextButton.icon(
            onPressed: () =>
                context.push(account == null ? '/login' : '/account'),
            icon: Icon(
                account == null ? Icons.login : Icons.account_circle_outlined),
            label: Text(account == null
                ? workspaceText(context, '로그인', 'Sign in')
                : workspaceText(context, '내 계정', 'My account'))),
        const SizedBox(width: 8),
      ]),
      bottomNavigationBar: const ScoutNavigationBar(selectedIndex: 0),
      body: profile.when(
        data: (p) => p.configured
            ? p.active == WorkspaceMode.professional
                ? personalStudio
                    ? ProfessionalWorkspaceHome(
                        key: ValueKey(account),
                        profile: p,
                        signedIn: account != null)
                    : const HomePage()
                : _RoleHome(
                    key: ValueKey('${account ?? 'guest'}:${p.active!.name}'),
                    mode: p.active!,
                    signedIn: account != null)
            : PurposeEditor(key: ValueKey(account), initial: p),
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (_, __) => WorkspacePreferenceError(
            onRetry: () =>
                ref.read(workspaceProfileProvider.notifier).reload()),
      ),
    );
  }
}

class _RoleHome extends ConsumerWidget {
  const _RoleHome({super.key, required this.mode, required this.signedIn});
  final WorkspaceMode mode;
  final bool signedIn;
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    String tr(String ko, String en) => workspaceText(context, ko, en);
    final heading = switch (mode) {
      WorkspaceMode.personal =>
        tr('오늘의 요리, 가볍게 시작해요.', 'Make room for a good meal.'),
      WorkspaceMode.professional =>
        tr('오늘의 주방 업무를 한눈에.', 'Your kitchen work, at a glance.'),
      WorkspaceMode.supplier =>
        tr('좋은 식자재를 알리는 공간.', 'Introduce your business and products.'),
    };
    final shortcuts = focusedWorkspaceLinks(mode);
    return Center(
        child: ConstrainedBox(
            constraints:
                const BoxConstraints(maxWidth: ScoutStyle.workspaceWidth),
            child: ListView(padding: const EdgeInsets.all(24), children: [
              if (!WorkspaceScope.hasFrame(context))
                const Align(
                    alignment: Alignment.centerLeft,
                    child: WorkspaceModeButton()),
              const SizedBox(height: 12),
              Text(heading,
                  style: Theme.of(context)
                      .textTheme
                      .headlineMedium
                      ?.copyWith(fontWeight: FontWeight.w700, height: 1.25)),
              const SizedBox(height: 12),
              Text(modeDescription(context, mode)),
              const SizedBox(height: 16),
              const SizedBox(height: 12),
              if (!signedIn)
                Card(
                    child: ListTile(
                        title: Text(tr('같은 계정으로 앱과 웹을 이어 쓰세요.',
                            'Keep your work connected across the app and web.')),
                        trailing: const Icon(Icons.login),
                        onTap: () => context.push(loginFor(GoRouterState.of(context).uri.toString(), resume: true)))),
              if (signedIn) ...[
                if (mode == WorkspaceMode.professional) const _RecentRequests(),
                if (mode == WorkspaceMode.supplier) const _BusinessOverview(),
                if (mode == WorkspaceMode.personal) const _RecentRecipes(),
                const SizedBox(height: 24),
              ] else
                const SizedBox(height: 12),
              LayoutBuilder(builder: (context, box) {
                final columns = box.maxWidth >= 720 &&
                        MediaQuery.textScalerOf(context).scale(1) <= 1.3
                    ? 2
                    : 1;
                return Wrap(spacing: 12, runSpacing: 12, children: [
                  for (final link in shortcuts)
                    SizedBox(
                        width: (box.maxWidth - (columns - 1) * 12) / columns,
                        child: _ActionTile(link: link))
                ]);
              }),
              const SizedBox(height: 22),
              if (mode != WorkspaceMode.supplier)
                Card(
                    child: ListTile(
                        leading: const Icon(Icons.school_outlined),
                        title: Text(mode == WorkspaceMode.personal
                            ? tr('일반 사용자 체험 튜토리얼', 'Home cooking tutorials')
                            : tr('업소·전문가 체험 튜토리얼',
                                'Professional kitchen tutorials')),
                        trailing: const Icon(Icons.arrow_forward),
                        onTap: () => context.push(guideForMode(mode))))
              else
                Card(
                    child: Padding(
                        padding: const EdgeInsets.all(20),
                        child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              TextButton.icon(
                                  onPressed: () =>
                                      context.push(guideForMode(mode)),
                                  icon: const Icon(Icons.school_outlined),
                                  label: Text(tr(
                                      '공급업체 체험 튜토리얼', 'Supplier tutorials'))),
                              Text(
                                  tr('등록은 세 단계로 간단하게',
                                      'Three steps to get listed'),
                                  style:
                                      Theme.of(context).textTheme.titleMedium),
                              const SizedBox(height: 12),
                              Text(tr(
                                  '1. 업체 소개와 배송 지역 입력\n2. 취급상품·규격·사진 등록\n3. 내용을 확인하고 회원에게 공개',
                                  '1. Add your business and delivery regions\n2. Register products, pack sizes and photos\n3. Review and publish for signed-in members')),
                            ]))),
              const SizedBox(height: 24),
              const OfficialChannelsCard(),
            ])));
  }
}

class _ActionTile extends ConsumerWidget {
  const _ActionTile({required this.link});
  final WorkspaceLink link;
  @override
  Widget build(BuildContext context, WidgetRef ref) => Card(
      margin: EdgeInsets.zero,
      child: ListTile(
          contentPadding:
              const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
          leading: Icon(link.icon, color: ScoutStyle.forest),
          title: Text(
              link.label(context,
                  personalName: ref.watch(recipeOwnerNameProvider)),
              style: const TextStyle(fontWeight: FontWeight.w700)),
          trailing: const Icon(Icons.arrow_forward, size: 20),
          onTap: () => context.go(link.path)));
}

class _RecentRequests extends ConsumerWidget {
  const _RecentRequests();
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    String tr(String ko, String en) => workspaceText(context, ko, en);
    final checkpoints = ref.watch(requestEditCheckpointsProvider);
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      for (final checkpoint in checkpoints.values.take(2))
        Card(
            child: ListTile(
                leading: const Icon(Icons.edit_note),
                title:
                    Text(tr('작성하던 요청서 이어가기', 'Continue an unfinished request')),
                subtitle: Text(checkpoint.request.supplier.name),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => context.push('/purchases'))),
      ref.watch(supplierRequestsProvider).when(
            data: (rows) =>
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              for (final stage in PurchaseStage.values) ...[
                _SectionTitle(
                    title: switch (stage) {
                      PurchaseStage.preparing =>
                        tr('이어서 작성', 'Continue preparing'),
                      PurchaseStage.active => tr('확인할 일', 'To check'),
                      PurchaseStage.completed =>
                        tr('지난 요청 다시 만들기', 'Request again'),
                    },
                    path: '/purchases?stage=${stage.name}'),
                if (!rows.any((r) => purchaseStage(r.status) == stage))
                  Padding(
                      padding: const EdgeInsets.only(bottom: 12),
                      child: Text(switch (stage) {
                        PurchaseStage.preparing => tr('새 구매요청에서 필요한 재료를 준비하세요.',
                            'Start with ingredients in New request.'),
                        PurchaseStage.active =>
                          tr('진행 중인 요청이 없습니다.', 'No requests in progress.'),
                        PurchaseStage.completed => tr('완료한 요청이 여기에 표시됩니다.',
                            'Completed requests will appear here.'),
                      })),
                for (final r in rows
                    .where((r) => purchaseStage(r.status) == stage)
                    .take(2))
                  Card(
                      margin: const EdgeInsets.only(bottom: 8),
                      child: ListTile(
                          title: Text(r.supplier.name),
                          subtitle: Text(switch (r.status) {
                            'sent' => tr('전달 확인 · 업체 답변을 확인해 주세요.',
                                'Marked as shared · check the supplier reply.'),
                            'accepted' => tr('수락 확인 · 입고 내역을 확인해 주세요.',
                                'Acceptance recorded · check receipt.'),
                            'received' => tr('입고 확인 완료', 'Receipt recorded'),
                            'cancelled' => tr('취소한 요청', 'Cancelled request'),
                            _ => tr('저장한 초안 · 수정 후 보내기',
                                'Saved draft · edit and share'),
                          }),
                          trailing: const Icon(Icons.chevron_right),
                          onTap: () =>
                              context.push(purchaseRequestPath(r.id)))),
              ],
            ]),
            loading: () => const LinearProgressIndicator(),
            error: (_, __) => _RetryTile(
                onRetry: () => ref.invalidate(supplierRequestsProvider)),
          ),
    ]);
  }
}

class _RecentRecipes extends ConsumerWidget {
  const _RecentRecipes();
  @override
  Widget build(BuildContext context, WidgetRef ref) =>
      Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        _SectionTitle(
            title:
                workspaceText(context, '다시 만들고 싶은 요리', 'Recipes to make again'),
            path: '/my-recipes'),
        ref.watch(creatorRecipesProvider('')).when(
              data: (rows) => rows.isEmpty
                  ? Text(workspaceText(context, '마음에 드는 요리를 내 레시피에 모아 보세요.',
                      'Collect the dishes you love in My recipes.'))
                  : Column(children: [
                      for (final recipe in rows.take(3))
                        Card(
                            margin: const EdgeInsets.only(bottom: 8),
                            child: ListTile(
                                leading: const Icon(Icons.menu_book_outlined),
                                title: Text(recipe.title),
                                trailing: const Icon(Icons.chevron_right),
                                onTap: () => context.push(
                                    '/creator/${Uri.encodeComponent(recipe.id)}'))),
                    ]),
              loading: () => const LinearProgressIndicator(),
              error: (_, __) => _RetryTile(
                  onRetry: () => ref.invalidate(creatorRecipesProvider(''))),
            ),
      ]);
}

class _BusinessOverview extends ConsumerWidget {
  const _BusinessOverview();
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    String tr(String ko, String en) => workspaceText(context, ko, en);
    return ref.watch(mySupplierBusinessProvider).when(
          data: (business) => business == null
              ? Card(
                  child: ListTile(
                      leading: const Icon(Icons.add_business_outlined),
                      title:
                          Text(tr('내 업체를 처음 등록해요', 'Register your business')),
                      subtitle: Text(tr('소개·배송 지역·취급상품을 입력해 주세요.',
                          'Add your introduction, delivery regions and products.')),
                      onTap: () => context.go('/supplier-business')))
              : Card(
                  child: Padding(
                      padding: const EdgeInsets.all(20),
                      child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(business.name,
                                style: Theme.of(context).textTheme.titleLarge),
                            const SizedBox(height: 10),
                            Text(business.published
                                ? tr('로그인한 회원에게 공개 중',
                                    'Visible to signed-in members')
                                : tr('아직 비공개 · 내용을 확인하고 공개하세요',
                                    'Not published yet. Review your details before publishing.')),
                            const SizedBox(height: 12),
                            ref
                                .watch(myCatalogProductsProvider(business.id))
                                .when(
                                    data: (products) =>
                                        Wrap(spacing: 8, children: [
                                          Text(tr(
                                              '등록 상품', 'Registered products')),
                                          LocalizedText('${products.length}',
                                              style: const TextStyle(
                                                  fontWeight: FontWeight.w700))
                                        ]),
                                    loading: () =>
                                        const LinearProgressIndicator(),
                                    error: (_, __) => _RetryTile(
                                        onRetry: () => ref.invalidate(
                                            myCatalogProductsProvider(
                                                business.id)))),
                            const SizedBox(height: 12),
                            OutlinedButton(
                                onPressed: () =>
                                    context.go('/supplier-business'),
                                child: Text(tr('업체·상품 수정하기',
                                    'Edit business and products'))),
                          ]))),
          loading: () => const LinearProgressIndicator(),
          error: (_, __) => _RetryTile(
              onRetry: () => ref.invalidate(mySupplierBusinessProvider)),
        );
  }
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle({required this.title, required this.path});
  final String title, path;
  @override
  Widget build(BuildContext context) => Wrap(
          alignment: WrapAlignment.spaceBetween,
          crossAxisAlignment: WrapCrossAlignment.center,
          spacing: 16,
          children: [
            Text(title, style: Theme.of(context).textTheme.titleLarge),
            TextButton(
                onPressed: () => context.go(path),
                child: Text(workspaceText(context, '모두 보기', 'View all'))),
          ]);
}

class _RetryTile extends StatelessWidget {
  const _RetryTile({required this.onRetry});
  final VoidCallback onRetry;
  @override
  Widget build(BuildContext context) => ListTile(
      title: Text(workspaceText(
          context, '자료를 불러오지 못했어요.', 'Could not load your records.')),
      trailing: TextButton(
          onPressed: onRetry,
          child: Text(workspaceText(context, '다시 시도', 'Retry'))));
}

class WorkspaceMenuPage extends ConsumerWidget {
  const WorkspaceMenuPage({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    String tr(String ko, String en) => workspaceText(context, ko, en);
    final profile = ref.watch(workspaceProfileProvider).valueOrNull;
    final isAdmin =
        ref.watch(membershipInfoProvider).valueOrNull?.isAdmin ?? false;
    final mode = profile?.active ?? WorkspaceMode.personal;
    Widget tile(WorkspaceLink link) => Card(
        margin: const EdgeInsets.only(bottom: 10),
        child: ListTile(
            leading: Icon(link.icon),
            title: Text(link.label(context,
                personalName: ref.watch(recipeOwnerNameProvider))),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => context.go(link.path)));
    return Scaffold(
        appBar: AppBar(title: Text(tr('더보기', 'More'))),
        bottomNavigationBar: const ScoutNavigationBar(selectedIndex: 0),
        body: Center(
            child: ConstrainedBox(
                constraints:
                    const BoxConstraints(maxWidth: ScoutStyle.readingWidth),
                child: ListView(padding: const EdgeInsets.all(20), children: [
                  if (!WorkspaceScope.hasFrame(context))
                    const Align(
                        alignment: Alignment.centerLeft,
                        child: WorkspaceModeButton()),
                  const SizedBox(height: 16),
                  tile(workspaceAccount),
                  if (isAdmin)
                    ListTile(
                        leading:
                            const Icon(Icons.admin_panel_settings_outlined),
                        title: Text(tr('관리자 홈', 'Admin home')),
                        subtitle: Text(tr('회원·제휴 상품·서비스 운영 관리',
                            'Members, affiliate offers and operations')),
                        trailing: const Icon(Icons.chevron_right),
                        onTap: () => context.go(AppRoutes.membershipAdmin)),
                  const Divider(),
                  tile(workspaceTeam),
                  if (mode == WorkspaceMode.supplier) ...[
                    tile(workspaceBusiness),
                    tile(workspaceDirectory),
                  ] else if (profile?.enabled
                          .contains(WorkspaceMode.professional) ==
                      true)
                    tile(workspaceSales),
                  const Divider(),
                  ListTile(
                      leading: const Icon(Icons.tune),
                      title: Text(tr(
                          '전문·공급업체 기능 설정', 'Professional & supplier settings')),
                      onTap: () => context.go('/workspace-settings')),
                  ListTile(
                      leading: const Icon(Icons.school_outlined),
                      title: Text(tr('체험 튜토리얼', 'Tutorials')),
                      onTap: () => context.go(guideForMode(mode))),
                  ListTile(
                      leading: const Icon(Icons.workspace_premium_outlined),
                      title:
                          Text(tr('회원 및 구독 관리', 'Membership & subscriptions')),
                      onTap: () => context.go('/membership')),
                  const SizedBox(height: 16),
                  const OfficialChannelsCard(),
                ]))));
  }
}
