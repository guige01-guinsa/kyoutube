part of 'workspace_page.dart';

class ProfessionalWorkspaceHome extends ConsumerStatefulWidget {
  const ProfessionalWorkspaceHome(
      {super.key, required this.profile, required this.signedIn});
  final WorkspaceProfile profile;
  final bool signedIn;
  @override
  ConsumerState<ProfessionalWorkspaceHome> createState() =>
      _ProfessionalWorkspaceHomeState();
}

class _ProfessionalWorkspaceHomeState
    extends ConsumerState<ProfessionalWorkspaceHome> {
  bool _saving = false;
  Future<void> _focus(ProfessionalDuty? duty) async {
    if (_saving) return;
    final owner = ref.read(activeAccountIdProvider);
    setState(() => _saving = true);
    final saved = await ref
        .read(workspaceProfileProvider.notifier)
        .save(widget.profile.focusOn(duty));
    if (!mounted || owner != ref.read(activeAccountIdProvider)) return;
    setState(() => _saving = false);
    if (!saved) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(workspaceText(context, '업무 화면을 저장하지 못했어요. 다시 시도해 주세요.',
              'Could not save this work view. Please try again.'))));
    }
  }

  @override
  Widget build(BuildContext context) {
    String tr(String ko, String en) => workspaceText(context, ko, en);
    final profile = widget.profile;
    final focus = profile.effectiveDuty;
    final shown = focus == null ? profile.effectiveDuties : {focus};
    return Center(
        child: ConstrainedBox(
            constraints:
                const BoxConstraints(maxWidth: ScoutStyle.workspaceWidth),
            child: ListView(padding: const EdgeInsets.all(20), children: [
              if (!WorkspaceScope.hasFrame(context))
                const Align(
                    alignment: Alignment.centerLeft,
                    child: WorkspaceModeButton()),
              const SizedBox(height: 8),
              ScoutPageHeading(
                eyebrow: tr('개인 작업실', 'PERSONAL STUDIO'),
                title: focus == null
                    ? tr('나의 업무를 시작하세요.', 'Your work, at a glance.')
                    : switch (focus) {
                        ProfessionalDuty.purchasing => tr('필요한 재료부터, 입고 확인까지.',
                            'From ingredients to receipt.'),
                        ProfessionalDuty.culinary => tr('더 나은 한 접시를 연구하세요.',
                            'Develop your next great dish.'),
                        ProfessionalDuty.management => tr('원가를 알고, 판매를 결정하세요.',
                            'Know your costs. Plan your sales.'),
                      },
                subtitle: tr('하던 일을 이어가고, 다음 작업을 바로 시작하세요.',
                    'Continue where you left off and move to the next task.'),
                icon:
                    focus == null ? Icons.dashboard_outlined : dutyIcon(focus),
              ),
              const SizedBox(height: 14),
              Wrap(spacing: 8, runSpacing: 6, children: [
                if (profile.effectiveDuties.length > 1)
                  ChoiceChip(
                      key: const Key('work-focus-all'),
                      label: Text(tr('내 업무 전체', 'My work')),
                      selected: focus == null,
                      onSelected: _saving ? null : (_) => _focus(null)),
                for (final duty in ProfessionalDuty.values
                    .where(profile.effectiveDuties.contains))
                  ChoiceChip(
                      key: ValueKey('work-focus-${duty.name}'),
                      avatar: Icon(dutyIcon(duty), size: 18),
                      label: Text(dutyTitle(context, duty)),
                      selected: focus == duty,
                      onSelected: _saving ? null : (_) => _focus(duty)),
                TextButton.icon(
                    onPressed: _saving
                        ? null
                        : () => context.push('/workspace-settings'),
                    icon: const Icon(Icons.tune, size: 18),
                    label: Text(tr('담당 업무 설정', 'Responsibilities'))),
              ]),
              if (_saving) const LinearProgressIndicator(),
              const SizedBox(height: 12),
              Card(
                  color: ScoutStyle.mint,
                  child: ListTile(
                      leading: const Icon(Icons.groups_outlined),
                      title: Text(
                          tr('소속 업소에서 공동 업무하기', 'Open shared business work'),
                          style: const TextStyle(fontWeight: FontWeight.w700)),
                      subtitle: Text(tr('직원별 로그인 · 공동 자료 · 사장 권한 관리',
                          'Staff accounts · shared records · owner permissions')),
                      trailing: const Icon(Icons.chevron_right),
                      onTap: () => context.go('/workspace'))),
              if (!widget.signedIn) ...[
                const SizedBox(height: 12),
                Card(
                    child: ListTile(
                        leading: const Icon(Icons.login),
                        title: Text(tr('로그인하고 내 업무를 이어가세요.',
                            'Sign in to continue your work.')),
                        subtitle: Text(tr('샘플 튜토리얼은 로그인 없이 체험할 수 있어요.',
                            'You can try the sample tutorials without signing in.')),
                        onTap: () => context.push(loginFor(GoRouterState.of(context).uri.toString(), resume: true)))),
              ],
              for (final duty
                  in ProfessionalDuty.values.where(shown.contains)) ...[
                const SizedBox(height: 22),
                _DutyWorkflow(duty: duty),
                if (widget.signedIn) ...[
                  const SizedBox(height: 16),
                  if (duty == ProfessionalDuty.purchasing)
                    const _RecentRequests(),
                  if (duty == ProfessionalDuty.culinary) const _WorkRecipes(),
                  if (duty == ProfessionalDuty.management && focus == duty)
                    const _ManagementSummary(),
                ],
              ],
              const SizedBox(height: 20),
              Text(
                  tr('현재 로그인한 계정의 자료를 사용합니다. 업무 화면 선택은 자료 접근 권한을 바꾸지 않습니다.',
                      'These views use the current account’s records. Choosing a work view does not change access permissions.'),
                  style: Theme.of(context).textTheme.bodySmall),
              const SizedBox(height: 24),
              const OfficialChannelsCard(),
            ])));
  }
}

class _DutyWorkflow extends StatelessWidget {
  const _DutyWorkflow({required this.duty});
  final ProfessionalDuty duty;
  @override
  Widget build(BuildContext context) {
    String tr(String ko, String en) => workspaceText(context, ko, en);
    final steps = switch (duty) {
      ProfessionalDuty.purchasing => [
          (
            title: tr('구매량 준비', 'Prepare quantities'),
            detail: tr('조리량과 별도로 구매 단위·수량 확정',
                'Set purchase quantities and units separately'),
            path: '/kitchen?tab=shopping',
            icon: Icons.shopping_basket_outlined
          ),
          (
            title: tr('업체 비교·요청', 'Compare & request'),
            detail: tr('재료별 후보 최대 3곳 → 요청서 검토',
                'Up to 3 candidates per item → review request'),
            path: '/purchases',
            icon: Icons.receipt_long_outlined
          ),
          (
            title: tr('전달·입고 확인', 'Follow up & receive'),
            detail: tr('업체 답변과 실제 입고를 확인해 기록',
                'Record the reply and receipt after checking'),
            path: '/purchases?stage=active',
            icon: Icons.inventory_2_outlined
          ),
        ],
      ProfessionalDuty.culinary => [
          (
            title: tr('레시피 연구', 'Research recipes'),
            detail: tr('영상 찾기 → 초안 검토 → 내 레시피',
                'Find a video → review draft → save recipe'),
            path: '/',
            icon: Icons.search
          ),
          (
            title: tr('인분·버전 비교', 'Scale & compare'),
            detail: tr('기준 레시피의 배합과 개선 기록',
                'Adjust the formula and keep revision notes'),
            path: '/chef',
            icon: Icons.science_outlined
          ),
          (
            title: tr('구매 준비로 연결', 'Prepare purchasing'),
            detail:
                tr('내 레시피 선택 → 장보기 준비', 'Choose a recipe → prepare shopping'),
            path: '/my-recipes',
            icon: Icons.menu_book_outlined
          ),
        ],
      ProfessionalDuty.management => [
          (
            title: tr('원가·판매가 점검', 'Review cost & price'),
            detail: tr(
                '재료비·수율·추가 비용을 확인', 'Check ingredients, yield and added costs'),
            path: '/chef',
            icon: Icons.balance_outlined
          ),
          (
            title: tr('매출 기록·분석', 'Record & review sales'),
            detail:
                tr('요리별 판매량과 일·주·월 실적', 'Sales by dish, day, week and month'),
            path: '/chef-sales',
            icon: Icons.bar_chart_outlined
          ),
          (
            title: tr('구매 대장 확인', 'Review purchases'),
            detail: tr(
                '기간·업체별 요청 내역과 문서 출력', 'Review requests and export documents'),
            path: '/supplier-request-ledger',
            icon: Icons.fact_check_outlined
          ),
        ],
    };
    final lesson = switch (duty) {
      ProfessionalDuty.purchasing => 'buy-quantity',
      ProfessionalDuty.culinary => 'pro-standard',
      ProfessionalDuty.management => 'pro-cost',
    };
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Wrap(
          spacing: 16,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            Text(dutyTitle(context, duty),
                style: Theme.of(context)
                    .textTheme
                    .titleLarge
                    ?.copyWith(fontWeight: FontWeight.w700)),
            TextButton.icon(
                onPressed: () => context.push('/guide?lesson=$lesson'),
                icon: const Icon(Icons.school_outlined, size: 18),
                label: Text(tr('샘플로 배우기', 'Learn with samples'))),
          ]),
      const SizedBox(height: 8),
      LayoutBuilder(builder: (context, box) {
        final columns = box.maxWidth >= 820 &&
                MediaQuery.textScalerOf(context).scale(1) <= 1.3
            ? 3
            : 1;
        return Wrap(spacing: 12, runSpacing: 10, children: [
          for (final (i, step) in steps.indexed)
            SizedBox(
                width: (box.maxWidth - (columns - 1) * 12) / columns,
                child: Card(
                    margin: EdgeInsets.zero,
                    child: ListTile(
                        key: ValueKey('work-${duty.name}-$i'),
                        contentPadding: const EdgeInsets.symmetric(
                            horizontal: 16, vertical: 8),
                        leading:
                            CircleAvatar(radius: 17, child: LocalizedText('${i + 1}')),
                        title: Text(step.title,
                            style:
                                const TextStyle(fontWeight: FontWeight.w700)),
                        subtitle: Text(step.detail),
                        trailing: const Icon(Icons.chevron_right),
                        onTap: () => context.go(step.path)))),
        ]);
      }),
      const SizedBox(height: 10),
      Text(
          switch (duty) {
            ProfessionalDuty.purchasing => tr(
                '구매·입고 이력을 관리합니다. 조리로 인한 재고 차감은 하지 않습니다.',
                'Track purchasing and receipt. Cooking does not deduct stock.'),
            ProfessionalDuty.culinary => tr(
                '작업실에서 저장한 뒤 장보기 준비로 이어갈 수 있어요. 구매량은 별도로 확인하세요.',
                'Save your work before continuing to shopping preparation. Confirm purchase quantities separately.'),
            ProfessionalDuty.management => tr(
                '예상이익은 입력된 원가 기준입니다. 미입력 경비와 세금은 포함되지 않습니다.',
                'Estimated profit uses recorded costs. Unentered expenses and taxes are excluded.'),
          },
          style: Theme.of(context).textTheme.bodySmall),
    ]);
  }
}

class _WorkRecipes extends ConsumerWidget {
  const _WorkRecipes();
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    String tr(String ko, String en) => workspaceText(context, ko, en);
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      _SectionTitle(
          title: tr('내 레시피에서 계속하기', 'Continue with your recipes'),
          path: '/my-recipes'),
      ref.watch(creatorRecipesProvider('')).when(
          data: (rows) => rows.isEmpty
              ? Text(tr('영상에서 초안을 만들거나 내 레시피에 요리를 저장하세요.',
                  'Create a video draft or save a dish in My recipes.'))
              : Column(children: [
                  for (final recipe in rows.take(3))
                    Card(
                        child: Padding(
                            padding: const EdgeInsets.all(12),
                            child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(recipe.title,
                                      style: Theme.of(context)
                                          .textTheme
                                          .titleMedium),
                                  const SizedBox(height: 6),
                                  Wrap(spacing: 8, runSpacing: 4, children: [
                                    TextButton.icon(
                                        onPressed: () => context.push(
                                            '/creator/${Uri.encodeComponent(recipe.id)}'),
                                        icon: const Icon(
                                            Icons.menu_book_outlined),
                                        label: Text(tr('조리법·구매 준비',
                                            'Recipe & purchasing'))),
                                    OutlinedButton.icon(
                                        onPressed: () => context.push(
                                            '/chef/${Uri.encodeComponent(recipe.id)}'),
                                        icon:
                                            const Icon(Icons.science_outlined),
                                        label: Text(tr(
                                            '인분·버전 연구', 'Scale & versions'))),
                                  ])
                                ]))),
                ]),
          loading: () => const LinearProgressIndicator(),
          error: (_, __) => _RetryTile(
              onRetry: () => ref.invalidate(creatorRecipesProvider('')))),
    ]);
  }
}

class _ManagementSummary extends ConsumerStatefulWidget {
  const _ManagementSummary();
  @override
  ConsumerState<_ManagementSummary> createState() => _ManagementSummaryState();
}

class _ManagementSummaryState extends ConsumerState<_ManagementSummary> {
  ChefSalesPeriod _period = ChefSalesPeriod.day;
  String _currency = 'KRW';
  @override
  Widget build(BuildContext context) {
    String tr(String ko, String en) => workspaceText(context, ko, en);
    final query =
        (period: _period, currency: _currency, date: chefDate(DateTime.now()));
    final value = ref.watch(professionalSalesSummaryProvider(query));
    return Card(
        child: Padding(
            padding: const EdgeInsets.all(18),
            child:
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(tr('기록한 판매 실적', 'Recorded sales'),
                  style: Theme.of(context).textTheme.titleLarge),
              const SizedBox(height: 10),
              Wrap(spacing: 8, runSpacing: 6, children: [
                for (final p in ChefSalesPeriod.values)
                  ChoiceChip(
                      label: Text(switch (p) {
                        ChefSalesPeriod.day => tr('오늘', 'Today'),
                        ChefSalesPeriod.week => tr('이번 주', 'This week'),
                        ChefSalesPeriod.month => tr('이번 달', 'This month')
                      }),
                      selected: p == _period,
                      onSelected: (_) => setState(() => _period = p)),
                for (final currency in ['KRW', 'USD'])
                  ChoiceChip(
                      label: Text(currency),
                      selected: _currency == currency,
                      onSelected: (_) => setState(() => _currency = currency)),
              ]),
              const SizedBox(height: 12),
              value.when(
                  data: (totals) => totals == null
                      ? const ChefPaidNotice()
                      : Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                              LocalizedText(
                                  '${tr('판매 수량', 'Quantity')}: ${totals.quantity}'),
                              LocalizedText(
                                  '${tr('매출', 'Revenue')}: ${totals.revenue.toStringAsFixed(_currency == 'KRW' ? 0 : 2)} $_currency'),
                              LocalizedText(
                                  '${tr('판매분 원가', 'Recorded cost')}: ${totals.cost.toStringAsFixed(_currency == 'KRW' ? 0 : 2)} $_currency'),
                              LocalizedText(
                                  '${tr('예상이익', 'Estimated profit')}: ${totals.profit.toStringAsFixed(_currency == 'KRW' ? 0 : 2)} $_currency',
                                  style: const TextStyle(
                                      fontWeight: FontWeight.w700)),
                              const SizedBox(height: 8),
                              Text(
                                  tr('선택한 통화의 기록만 표시합니다. 실제 결제 내역이나 순이익이 아닙니다.',
                                      'Only records in the selected currency are shown. These are not payment transactions or net profit.'),
                                  style: Theme.of(context).textTheme.bodySmall),
                            ]),
                  loading: () => const LinearProgressIndicator(),
                  error: (_, __) => _RetryTile(
                      onRetry: () => ref.invalidate(
                          professionalSalesSummaryProvider(query)))),
              const SizedBox(height: 8),
              TextButton.icon(
                  onPressed: () => context.go('/chef-sales'),
                  icon: const Icon(Icons.arrow_forward),
                  label: Text(tr('매출 상세 보기', 'View sales details'))),
            ])));
  }
}
