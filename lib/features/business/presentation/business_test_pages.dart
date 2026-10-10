part of 'business_pages.dart';

class BusinessPracticeNotice extends StatelessWidget {
  const BusinessPracticeNotice({super.key});
  @override
  Widget build(BuildContext context) => Card(
      color: Theme.of(context).colorScheme.secondaryContainer,
      child: Padding(
          padding: const EdgeInsets.all(16),
          child:
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(bt(context, '연습 전용 공간', 'Practice workspace'),
                style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 6),
            Text(bt(
                context,
                '이곳에 추가·수정한 자료도 테스트 종료 시 삭제될 수 있습니다. 실제 업소 자료는 별도로 유지됩니다. 샘플로 실제 발주하지 마세요. PDF에도 연습용 표시가 붙습니다.',
                'Records added or edited here may be deleted when testing ends. Real business records stay separate. Do not place real orders with samples. PDFs are marked as practice.')),
          ])));
}

Future<String?> _testInput(BuildContext context, String label,
    {String initial = '', bool email = false}) async {
  final controller = TextEditingController(text: initial);
  final form = GlobalKey<FormState>();
  final result = await showDialog<String>(
      context: context,
      builder: (ctx) => ShoppingAccountGuard(
              child: AlertDialog(
                  title: Text(label),
                  scrollable: true,
                  content: Form(
                      key: form,
                      child: SizedBox(
                          width: 440,
                          child: TextFormField(
                              controller: controller,
                              autofocus: true,
                              maxLength: email ? 254 : 120,
                              keyboardType: email
                                  ? TextInputType.emailAddress
                                  : TextInputType.text,
                              decoration: InputDecoration(labelText: label),
                              validator: (value) => value == null ||
                                      value.trim().isEmpty ||
                                      (email &&
                                          !RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]+$')
                                              .hasMatch(value.trim()))
                                  ? bt(ctx, '입력 내용을 확인해 주세요.',
                                      'Check this field.')
                                  : null))),
                  actions: [
                TextButton(
                    onPressed: () => Navigator.pop(ctx),
                    child: Text(bt(ctx, '취소', 'Cancel'))),
                FilledButton(
                    onPressed: () {
                      if (form.currentState!.validate()) {
                        Navigator.pop(ctx, controller.text.trim());
                      }
                    },
                    child: Text(bt(ctx, '계속', 'Continue')))
              ])));
  await Future<void>.delayed(const Duration(milliseconds: 250));
  controller.dispose();
  return result;
}

// Account-scoped async actions prevent a delayed result from navigating another user.
abstract class _BusinessTestsState<T extends ConsumerStatefulWidget>
    extends ConsumerState<T> {
  bool busy = false;
  String? error;
  bool current(String? account) =>
      mounted &&
      account != null &&
      account == ref.read(activeAccountIdProvider);
  void refresh() {
    ref.invalidate(businessTestOptionsProvider);
    ref.invalidate(businessWorkspacesProvider);
    ref.invalidate(businessContextProvider);
    ref.invalidate(businessRecordsProvider);
    ref.invalidate(businessRecordProvider);
    ref.invalidate(businessSalesTotalsProvider);
  }

  Future<void> run(
      Future<void> Function(BusinessRepository repo, String account)
          action) async {
    final account = ref.read(activeAccountIdProvider);
    if (busy || !current(account)) return;
    setState(() {
      busy = true;
      error = null;
    });
    try {
      await action(ref.read(businessRepositoryProvider), account!);
    } catch (e) {
      if (current(account)) setState(() => error = businessError(context, e));
    } finally {
      if (current(account)) {
        refresh();
        setState(() => busy = false);
      }
    }
  }

  Widget shell(String title, List<Widget> children) => Scaffold(
      appBar: AppBar(title: Text(title), actions: [
        IconButton(
            onPressed: busy ? null : refresh,
            tooltip: bt(context, '새로고침', 'Refresh'),
            icon: const Icon(Icons.refresh))
      ]),
      body: Center(
          child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 960),
              child: ListView(padding: const EdgeInsets.all(20), children: [
                if (busy) const LinearProgressIndicator(),
                if (error != null)
                  Padding(
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      child: Text(error!,
                          style: TextStyle(
                              color: Theme.of(context).colorScheme.error))),
                ...children
              ]))));
}

class BusinessSamplesPage extends ConsumerStatefulWidget {
  const BusinessSamplesPage({super.key});
  @override
  ConsumerState<BusinessSamplesPage> createState() =>
      _BusinessSamplesPageState();
}

class _BusinessSamplesPageState
    extends _BusinessTestsState<BusinessSamplesPage> {
  Future<void> start(Map<String, dynamic> row) async {
    final account = ref.read(activeAccountIdProvider);
    final workspace = row['workspace_id'] as String?;
    if (workspace != null) {
      context.push('/business-workspaces/$workspace');
      return;
    }
    final display = await _testInput(
        context, bt(context, '직원에게 보일 이름', 'Your display name'),
        initial: bt(context, '테스터', 'Tester'));
    if (!mounted || display == null || !current(account)) return;
    final language = Localizations.localeOf(context).languageCode == 'es'
        ? 'es'
        : Localizations.localeOf(context).languageCode == 'en'
            ? 'en'
            : 'ko';
    await run((repo, account) async {
      final id = await repo.startTest(row['id'] as String, language, display);
      if (mounted && current(account)) {
        context.push('/business-workspaces/$id');
      }
    });
  }

  Future<void> reset(Map<String, dynamic> row) async {
    final account = ref.read(activeAccountIdProvider);
    final confirmed = await businessConfirm(
        context,
        bt(
            context,
            '내 연습 공간에 추가·수정한 자료를 모두 삭제하고 처음 샘플 20개로 되돌립니다. 초대한 직원은 유지됩니다. 실제 업소 자료는 바뀌지 않습니다. 다시 시작할까요?',
            'Delete all records added or edited in your practice workspace and restore the original 20 samples? Invited staff stay. Real business records are unchanged.'));
    if (!confirmed || !current(account)) return;
    await run((repo, _) => repo.resetTest(
        row['workspace_id'] as String, (row['generation'] as num).toInt()));
  }

  @override
  Widget build(BuildContext context) {
    final account = ref.watch(activeAccountIdProvider);
    return shell(bt(context, '업소 업무 테스트', 'Business practice'), [
      Text(
          bt(context, '20개 샘플로, 한 업소의 업무를 끝까지',
              'Explore a complete workflow with 20 samples'),
          style: Theme.of(context).textTheme.headlineSmall),
      const SizedBox(height: 12),
      Text(bt(
          context,
          '구매·조리·경영 업무가 연결된 내 연습 공간을 만듭니다. 테스트 기간에는 이 공간의 업무 기능을 이용권 결제 없이 체험할 수 있습니다.',
          'Create your own practice workspace linking purchasing, cooking and management. Its work features are available without a paid plan during the test.')),
      const SizedBox(height: 16),
      Wrap(spacing: 8, runSpacing: 8, children: [
        for (final (ko, en) in [
          ('레시피 5', '5 recipes'),
          ('식단 3', '3 meal plans'),
          ('구매요청 5', '5 requests'),
          ('원가·판매가 3', '3 cost sheets'),
          ('판매기록 4', '4 sales')
        ])
          Chip(label: Text(bt(context, ko, en)))
      ]),
      const SizedBox(height: 16),
      const BusinessPracticeNotice(),
      ExpansionTile(
          tilePadding: const EdgeInsets.symmetric(horizontal: 8),
          title: Text(bt(context, '업무별 연습 순서', 'Practice steps by role')),
          children: [
            Padding(
                padding: const EdgeInsets.fromLTRB(8, 0, 8, 16),
                child: Text(bt(
                    context,
                    '1. 조리: 레시피와 식단 열기 → 재료 요청\n2. 구매: 구매량·구매 단위 확인 → 승인 요청 → 전달·입고 확인\n3. 경영: 승인 → 원가·판매가 비교 → 일·주·월 판매 확인\n혼자서는 모든 업무를, 직원 초대로는 담당별 권한을 시험할 수 있습니다. 함께할 직원도 같은 테스트의 참여 계정이어야 합니다.',
                    '1. Cooking: open recipes and meal plans → request ingredients\n2. Purchasing: confirm purchase quantities and units → request approval → confirm sharing and receipt\n3. Management: approve → compare costs and prices → review daily, weekly and monthly sales\nTry all tasks yourself or invite staff to test assigned permissions. Staff must also be participants in the same test.')))
          ]),
      const SizedBox(height: 12),
      if (account == null)
        TextButton(
            onPressed: () => context.push(loginFor(
                GoRouterState.of(context).uri.toString(),
                resume: true)),
            child: Text(bt(context, '로그인하기', 'Sign in')))
      else
        ref.watch(businessTestOptionsProvider(false)).when(
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (e, _) => _BusinessError(e, refresh),
            data: (rows) => Column(children: [
                  if (rows.isEmpty)
                    Text(bt(
                        context,
                        '참여할 테스트가 없습니다. 관리자에게 로그인 이메일로 테스터 등록을 요청해 주세요.',
                        'No test is available. Ask the administrator to register your sign-in email.')),
                  for (final row in rows)
                    Card(
                        child: Padding(
                            padding: const EdgeInsets.all(20),
                            child: Column(
                                crossAxisAlignment: CrossAxisAlignment.stretch,
                                children: [
                                  Text(row['name'] as String,
                                      style: Theme.of(context)
                                          .textTheme
                                          .titleLarge),
                                  LocalizedText(
                                      '${bt(context, '종료 예정', 'Ends')} · ${_businessDate(context, row['ends_at'])}'),
                                  const SizedBox(height: 12),
                                  if (row['available'] == true)
                                    Wrap(spacing: 12, runSpacing: 8, children: [
                                      FilledButton.icon(
                                          key: ValueKey(
                                              'sample-start-${row['id']}'),
                                          onPressed:
                                              busy ? null : () => start(row),
                                          icon: const Icon(Icons.play_arrow),
                                          label: Text(
                                              row['workspace_id'] == null
                                                  ? bt(context, '내 샘플 20개 만들기',
                                                      'Create my 20 samples')
                                                  : bt(context, '이어서 연습하기',
                                                      'Continue practice'))),
                                      if (row['workspace_id'] != null)
                                        OutlinedButton.icon(
                                            key: ValueKey(
                                                'sample-reset-${row['id']}'),
                                            onPressed:
                                                busy ? null : () => reset(row),
                                            icon: const Icon(Icons.restart_alt),
                                            label: Text(bt(context, '샘플 처음으로',
                                                'Reset samples')))
                                    ])
                                  else
                                    Text(bt(
                                        context,
                                        '테스트가 종료되었거나 참여가 해제되었습니다. 연습 공간을 더 이상 이용할 수 없습니다.',
                                        'This test has ended or access was removed. The practice workspace is no longer available.')),
                                ])))
                ]))
    ]);
  }
}

class BusinessTestAdminPage extends ConsumerStatefulWidget {
  const BusinessTestAdminPage({super.key});
  @override
  ConsumerState<BusinessTestAdminPage> createState() =>
      _BusinessTestAdminPageState();
}

class _BusinessTestAdminPageState
    extends _BusinessTestsState<BusinessTestAdminPage> {
  Future<void> create() async {
    final account = ref.read(activeAccountIdProvider);
    final name = TextEditingController(
        text: bt(context, '업소 업무 체험 테스트', 'Business workflow test'));
    final days = TextEditingController(text: '14');
    final form = GlobalKey<FormState>();
    var audience = 'selected';
    final result = await showDialog<({String name, int days, String audience})>(
        context: context,
        builder: (ctx) => ShoppingAccountGuard(
            child: StatefulBuilder(
                builder: (ctx, update) => AlertDialog(
                        title: Text(bt(ctx, '테스트 열기', 'Open a test')),
                        scrollable: true,
                        content: SizedBox(
                            width: 460,
                            child: Form(
                                key: form,
                                child: Column(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      TextFormField(
                                          controller: name,
                                          maxLength: 120,
                                          decoration: InputDecoration(
                                              labelText: bt(
                                                  ctx, '테스트 이름', 'Test name')),
                                          validator: (v) =>
                                              v == null || v.trim().isEmpty
                                                  ? bt(ctx, '이름을 입력해 주세요.',
                                                      'Enter a name.')
                                                  : null),
                                      TextFormField(
                                          controller: days,
                                          keyboardType: TextInputType.number,
                                          decoration: InputDecoration(
                                              labelText: bt(
                                                  ctx,
                                                  '테스트 기간 (1~90일)',
                                                  'Duration (1–90 days)')),
                                          validator: (v) {
                                            final n = int.tryParse(v ?? '');
                                            return n == null || n < 1 || n > 90
                                                ? bt(ctx, '1~90일로 입력해 주세요.',
                                                    'Enter 1–90 days.')
                                                : null;
                                          }),
                                      const SizedBox(height: 16),
                                      DropdownButtonFormField<String>(
                                          initialValue: audience,
                                          isExpanded: true,
                                          decoration: InputDecoration(
                                              labelText: bt(ctx, '참여 범위',
                                                  'Participants')),
                                          items: [
                                            DropdownMenuItem(
                                                value: 'selected',
                                                child: Text(bt(ctx, '지정한 테스터',
                                                    'Selected testers'))),
                                            DropdownMenuItem(
                                                value: 'members',
                                                child: Text(bt(ctx, '모든 회원',
                                                    'All members')))
                                          ],
                                          onChanged: (v) =>
                                              update(() => audience = v!)),
                                      const SizedBox(height: 12),
                                      Text(bt(
                                          ctx,
                                          '이메일 인증을 완료한 계정이 참여할 수 있습니다. 테스터별로 샘플 20개가 생성되며 최대 1,000개 연습 공간을 지원합니다. 실제 이용권 권한은 변경되지 않습니다.',
                                          'Participants need verified email accounts. Each gets 20 samples, up to 1,000 practice workspaces. Paid membership entitlements do not change.'))
                                    ]))),
                        actions: [
                          TextButton(
                              onPressed: () => Navigator.pop(ctx),
                              child: Text(bt(ctx, '취소', 'Cancel'))),
                          FilledButton(
                              onPressed: () {
                                if (form.currentState!.validate()) {
                                  Navigator.pop(ctx, (
                                    name: name.text.trim(),
                                    days: int.parse(days.text),
                                    audience: audience
                                  ));
                                }
                              },
                              child: Text(bt(ctx, '테스트 시작', 'Start test')))
                        ]))));
    await Future<void>.delayed(const Duration(milliseconds: 250));
    name.dispose();
    days.dispose();
    if (result == null || !current(account)) return;
    await run((repo, _) =>
        repo.createTest(result.name, result.days, result.audience));
  }

  Future<void> participant(Map<String, dynamic> row,
      {Map<String, dynamic>? person}) async {
    final account = ref.read(activeAccountIdProvider);
    final email = person?['email'] as String? ??
        await _testInput(
            context, bt(context, '테스터의 로그인 이메일', 'Tester sign-in email'),
            email: true);
    if (!mounted || email == null || !current(account)) return;
    final active = person == null || person['active'] != true;
    if (!active &&
        (!await businessConfirm(
                context,
                bt(
                    context,
                    '$email 계정의 테스트 접근을 해제할까요? 이 계정 소유의 연습 공간은 초대한 직원도 접근할 수 없게 됩니다.',
                    'Remove test access for $email? Staff invited to this account’s practice workspace will also lose access.')) ||
            !current(account))) {
      return;
    }
    await run(
        (repo, _) => repo.testParticipant(row['id'] as String, email, active));
  }

  Future<void> end(Map<String, dynamic> row, {required bool cleanup}) async {
    final account = ref.read(activeAccountIdProvider);
    final message = cleanup
        ? bt(
            context,
            '${row['name']}\n연습 공간 ${row['workspaces']}개와 현재 자료 ${row['records']}개를 삭제합니다. 테스터가 추가·수정한 자료, 변경 이력, 직원 초대도 포함됩니다. 실행 시점의 모든 연습 자료가 대상이며 복구할 수 없습니다. 실제 업소 자료는 유지합니다. 테스트를 종료하고 삭제할까요?',
            '${row['name']}\nDelete ${row['workspaces']} practice workspaces and ${row['records']} current records, including edits, added records, history and staff invitations? All practice records present at execution are included. This cannot be undone. Real business records stay. End the test and delete samples?')
        : bt(
            context,
            '${row['name']} 테스트를 종료할까요? 모든 참여자의 연습 공간 접근이 중단됩니다. 자료는 나중에 삭제할 수 있습니다.',
            'End ${row['name']}? All participants lose access to practice workspaces. Records can be deleted later.');
    if (!await businessConfirm(context, message) || !current(account)) return;
    await run((repo, account) async {
      final id = row['id'] as String;
      await repo.endTest(id);
      if (cleanup) {
        var remaining = 1;
        while (remaining > 0 && current(account)) {
          remaining = await repo.cleanupTest(id);
        }
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final account = ref.watch(activeAccountIdProvider);
    return shell(bt(context, '업소 테스트 관리', 'Business test management'), [
      Text(
          bt(context, '테스트 기간과 참여자를 한곳에서',
              'Manage the test and its participants'),
          style: Theme.of(context).textTheme.headlineSmall),
      const SizedBox(height: 12),
      Text(bt(
          context,
          '관리자 2단계 인증이 필요합니다. 기간이 지나면 접근이 자동 중단됩니다. 자료 삭제는 관리자가 확인 후 실행하며, 연습 공간에 추가된 자료도 함께 삭제합니다.',
          'Administrator two-step authentication is required. Access stops when the test expires. Administrators confirm deletion, including records added in practice workspaces.')),
      const SizedBox(height: 16),
      if (account == null)
        Text(bt(context, '관리자 계정으로 로그인해 주세요.', 'Sign in as an administrator.'))
      else
        ref.watch(businessTestOptionsProvider(true)).when(
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (e, _) => _BusinessError(e, refresh),
            data: (rows) => Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      if (!rows.any((r) => r['ended'] != true))
                        Align(
                            alignment: Alignment.centerLeft,
                            child: FilledButton.icon(
                                onPressed: busy ? null : create,
                                icon: const Icon(Icons.add),
                                label: Text(
                                    bt(context, '테스트 열기', 'Open a test')))),
                      for (final row in rows)
                        Card(
                            child: Padding(
                                padding: const EdgeInsets.all(20),
                                child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.stretch,
                                    children: [
                                      Text(row['name'] as String,
                                          style: Theme.of(context)
                                              .textTheme
                                              .titleLarge),
                                      LocalizedText(
                                          '${row['ended'] == true ? bt(context, '종료됨', 'Ended') : bt(context, '진행 중', 'Active')} · ${_businessDate(context, row['ends_at'])}'),
                                      Text(row['audience'] == 'members'
                                          ? bt(
                                              context,
                                              '이메일 인증을 마친 모든 회원 (해제 계정 제외)',
                                              'All verified members, except removed accounts')
                                          : bt(context, '관리자가 지정한 테스터',
                                              'Selected testers')),
                                      const SizedBox(height: 8),
                                      Text(bt(
                                          context,
                                          '연습 공간 ${row['workspaces']}개 · 현재 자료 ${row['records']}개',
                                          '${row['workspaces']} practice workspaces · ${row['records']} current records')),
                                      const SizedBox(height: 12),
                                      for (final raw
                                          in row['participants'] as List) ...[
                                        Text((raw as Map)['email'] as String),
                                        Align(
                                            alignment: Alignment.centerLeft,
                                            child: TextButton(
                                                onPressed: busy ||
                                                        row['ended'] == true
                                                    ? null
                                                    : () => participant(row,
                                                        person: Map<String,
                                                            dynamic>.from(raw)),
                                                child: Text(
                                                    raw['active'] == true
                                                        ? bt(context, '참여 해제',
                                                            'Remove access')
                                                        : bt(context, '참여 허용',
                                                            'Allow access')))),
                                      ],
                                      Wrap(
                                          spacing: 12,
                                          runSpacing: 8,
                                          children: [
                                            if (row['ended'] != true) ...[
                                              OutlinedButton.icon(
                                                  onPressed: busy
                                                      ? null
                                                      : () => participant(row),
                                                  icon: const Icon(
                                                      Icons.person_add_alt),
                                                  label: Text(bt(context,
                                                      '테스터 등록', 'Add tester'))),
                                              OutlinedButton(
                                                  onPressed: busy
                                                      ? null
                                                      : () => end(row,
                                                          cleanup: false),
                                                  child: Text(bt(context,
                                                      '테스트 종료', 'End test'))),
                                            ],
                                            if ((row['workspaces'] as num) > 0)
                                              OutlinedButton.icon(
                                                  key: ValueKey(
                                                      'sample-delete-${row['id']}'),
                                                  onPressed: busy
                                                      ? null
                                                      : () => end(row,
                                                          cleanup: true),
                                                  icon: const Icon(
                                                      Icons.delete_outline),
                                                  label: Text(row['closed'] ==
                                                          true
                                                      ? bt(context, '샘플 자료 삭제',
                                                          'Delete sample records')
                                                      : bt(
                                                          context,
                                                          '종료하고 샘플 삭제',
                                                          'End and delete samples')))
                                          ])
                                    ])))
                    ]))
    ]);
  }
}
