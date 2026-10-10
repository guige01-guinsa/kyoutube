part of 'business_pages.dart';

class BusinessPermissionPicker extends StatefulWidget {
  const BusinessPermissionPicker(
      {super.key,
      required this.initial,
      required this.onChanged,
      this.enabled = true});
  final Set<String> initial;
  final ValueChanged<Set<String>> onChanged;
  final bool enabled;
  @override
  State<BusinessPermissionPicker> createState() =>
      _BusinessPermissionPickerState();
}

class _BusinessPermissionPickerState extends State<BusinessPermissionPicker> {
  late Set<String> selected = {...widget.initial};
  void change(Set<String> values) {
    setState(() => selected = values);
    widget.onChanged({...values});
  }

  @override
  Widget build(BuildContext context) =>
      Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Wrap(spacing: 6, runSpacing: 4, children: [
          for (final role in businessRolePermissions.keys)
            ActionChip(
                label: Text(switch (role) {
                  'purchasing' => bt(context, '구매 담당 기본값', 'Purchasing preset'),
                  'culinary' => bt(context, '조리 담당 기본값', 'Cooking preset'),
                  _ => bt(context, '경영 담당 기본값', 'Management preset')
                }),
                onPressed: widget.enabled
                    ? () => change({...businessRolePermissions[role]!})
                    : null)
        ]),
        const SizedBox(height: 8),
        Text(bt(context, '기본값을 선택한 뒤 필요한 권한을 추가·해제하세요.',
            'Choose a preset, then add or remove individual permissions.')),
        for (final permission in businessPermissions)
          CheckboxListTile(
              key: ValueKey('permission-$permission'),
              contentPadding: EdgeInsets.zero,
              dense: true,
              value: selected.contains(permission),
              title: Text(switch (permission) {
                'recipes.read' =>
                  bt(context, '레시피·식단 조회', 'View recipes and meal plans'),
                'recipes.write' =>
                  bt(context, '레시피·식단 수정', 'Edit recipes and meal plans'),
                'purchasing.read' =>
                  bt(context, '구매·입고 조회', 'View purchasing and receipt'),
                'purchasing.write' => bt(context, '구매 작성·전달·입고 기록',
                    'Edit purchases, confirm sharing and receipt'),
                'menus.approve' => bt(context, '메뉴·식단 확정·가격 관리',
                    'Menu and meal approval & pricing'),
                'finance.read' =>
                  bt(context, '원가·판매가·매출 조회', 'View costs, prices and sales'),
                'finance.write' =>
                  bt(context, '원가·판매가·매출 수정', 'Edit costs, prices and sales'),
                _ => bt(context, '구매 승인·수정 요청',
                    'Approve purchases or request changes')
              }),
              onChanged: widget.enabled
                  ? (value) {
                      final next = {...selected};
                      if (value == true) {
                        next.add(permission);
                        if (permission.endsWith('.write')) {
                          next.add(permission.replaceAll('.write', '.read'));
                        }
                        if (permission == 'menus.approve') {
                          next.add('recipes.read');
                        }
                        if (permission == 'purchases.approve') {
                          next.add('purchasing.read');
                        }
                      } else {
                        next.remove(permission);
                        if (permission.endsWith('.read')) {
                          next.remove(permission.replaceAll('.read', '.write'));
                        }
                        if (permission == 'recipes.read') {
                          next.remove('menus.approve');
                        }
                        if (permission == 'purchasing.read') {
                          next.remove('purchases.approve');
                        }
                      }
                      change(next);
                    }
                  : null),
      ]);
}

class BusinessMembersPage extends ConsumerStatefulWidget {
  const BusinessMembersPage({super.key, required this.workspace});
  final String workspace;
  @override
  ConsumerState<BusinessMembersPage> createState() =>
      _BusinessMembersPageState();
}

class _BusinessMembersPageState extends ConsumerState<BusinessMembersPage> {
  late Future<List<List<Map<String, dynamic>>>> _rows = _load();
  String _query = '';
  String _status = 'all';

  bool _matches(Map<String, dynamic> member) {
    if (_status == 'active' && member['active'] != true) return false;
    if (_status == 'inactive' && member['active'] == true) return false;
    return ['display_name', 'job_title', 'work_contact']
        .map((key) => member[key]?.toString() ?? '')
        .join(' ')
        .toLowerCase()
        .contains(_query.trim().toLowerCase());
  }

  Future<void> _profile(Map<String, dynamic> member) async {
    final account = ref.read(activeAccountIdProvider);
    final saved =
        await editBusinessMemberProfile(context, ref, widget.workspace, member);
    if (mounted && saved && account == ref.read(activeAccountIdProvider)) {
      _reload();
    }
  }

  Widget _staffCard(Map<String, dynamic> member) {
    final owner = member['user_id'] == ref.read(activeAccountIdProvider);
    final active = member['active'] == true;
    final permissions = Set<String>.from(member['permissions'] as List);
    final title = member['job_title'] as String? ?? '';
    final contact = member['work_contact'] as String? ?? '';
    final labels = <String>[
      if (permissions.contains('recipes.read'))
        permissions.contains('recipes.write')
            ? bt(context, '레시피·식단 수정', 'Edit recipes and meal plans')
            : bt(context, '레시피·식단 조회', 'View recipes and meal plans'),
      if (permissions.contains('purchasing.read'))
        permissions.contains('purchasing.write')
            ? bt(context, '구매·입고 담당', 'Purchasing and receipt')
            : bt(context, '구매·입고 조회', 'View purchasing and receipt'),
      if (permissions.contains('finance.read'))
        permissions.contains('finance.write')
            ? bt(context, '원가·매출 담당', 'Costs and sales')
            : bt(context, '원가·매출 조회', 'View costs and sales'),
      if (permissions.contains('menus.approve'))
        bt(context, '메뉴 선정 담당', 'Menu approver'),
      if (permissions.contains('purchases.approve'))
        bt(context, '구매 승인 담당', 'Purchase approver')
    ];
    return Card(
        key: ValueKey('staff-card-${member['user_id']}'),
        child: Padding(
            padding: const EdgeInsets.all(14),
            child:
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(member['display_name'] as String,
                  style: Theme.of(context).textTheme.titleMedium),
              Text(owner
                  ? bt(context, '사장 · 전체 권한', 'Owner · full access')
                  : active
                      ? bt(context, '이용 중', 'Active')
                      : bt(context, '이용 중지', 'Access suspended')),
              if (title.isNotEmpty) Text(title),
              if (contact.isNotEmpty) SelectableText(contact),
              if (!owner) ...[
                const SizedBox(height: 8),
                Text(bt(context, '담당 업무·권한', 'Duties and permissions'),
                    style: Theme.of(context).textTheme.labelLarge),
                for (final label in labels) LocalizedText('• $label'),
              ],
              Wrap(spacing: 8, runSpacing: 4, children: [
                if (member.containsKey('profile_revision'))
                  TextButton.icon(
                      key: ValueKey('staff-profile-${member['user_id']}'),
                      onPressed: () => _profile(member),
                      icon: const Icon(Icons.badge_outlined),
                      label: Text(bt(context, '담당자 정보', 'Staff profile'))),
                if (!owner) ...[
                  TextButton(
                      key: ValueKey('staff-permissions-${member['user_id']}'),
                      onPressed: () => _permissions(member: member),
                      child: Text(bt(
                          context, '업무·권한 수정', 'Edit duties and permissions'))),
                  if (active)
                    TextButton(
                        key: ValueKey('staff-suspend-${member['user_id']}'),
                        onPressed: () => _revoke(member),
                        child: Text(bt(context, '이용 중지', 'Suspend access')))
                  else
                    TextButton(
                        key: ValueKey('staff-restore-${member['user_id']}'),
                        onPressed: () =>
                            _permissions(member: member, restore: true),
                        child: Text(bt(context, '이용 복구', 'Restore access')))
                ]
              ])
            ])));
  }

  Future<List<List<Map<String, dynamic>>>> _load() async {
    final repo = ref.read(businessRepositoryProvider);
    return Future.wait([
      repo.members(widget.workspace),
      repo.invites(widget.workspace),
      repo.accessEvents(widget.workspace)
    ]);
  }

  String _memberName(List<Map<String, dynamic>> members, Object? id) =>
      members.where((m) => m['user_id'] == id).firstOrNull?['display_name']
          as String? ??
      bt(context, '업소', 'Business');

  void _reload() {
    final next = _load();
    setState(() {
      _rows = next;
    });
    ref.invalidate(businessContextProvider(widget.workspace));
  }

  Future<void> _permissions(
      {Map<String, dynamic>? member, bool restore = false}) async {
    final account = ref.read(activeAccountIdProvider),
        email = TextEditingController();
    var permissions = member == null
        ? {...businessRolePermissions['purchasing']!}
        : Set<String>.from(member['permissions'] as List);
    bool busy = false;
    String? error;
    Map<String, dynamic>? invite;
    await showDialog<void>(
        context: context,
        barrierDismissible: false,
        builder: (ctx) => ShoppingAccountGuard(
            child: StatefulBuilder(
                builder: (ctx, update) => PopScope(
                    canPop: !busy,
                    child: AlertDialog(
                        scrollable: true,
                        title: Text(member == null
                            ? bt(ctx, '직원 초대', 'Invite staff')
                            : restore
                                ? bt(ctx, '이용 복구 · 권한 확인',
                                    'Restore access · review permissions')
                                : bt(
                                    ctx, '직원 권한 수정', 'Edit staff permissions')),
                        content: SizedBox(
                            width: 500,
                            child: invite == null
                                ? Column(
                                    mainAxisSize: MainAxisSize.min,
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                        if (member == null)
                                          TextField(
                                              controller: email,
                                              enabled: !busy,
                                              maxLength: 254,
                                              keyboardType:
                                                  TextInputType.emailAddress,
                                              decoration: InputDecoration(
                                                  labelText: bt(
                                                      ctx,
                                                      '초대할 직원 이메일',
                                                      'Staff email address')))
                                        else
                                          Text(
                                              member['display_name'] as String),
                                        if (member != null &&
                                            member['active'] != true)
                                          Text(restore
                                              ? bt(
                                                  ctx,
                                                  '저장하면 아래 권한으로 업소 이용이 다시 허용됩니다.',
                                                  'Saving restores business access with the permissions below.')
                                              : bt(
                                                  ctx,
                                                  '권한을 수정해도 이용 중지 상태는 유지됩니다.',
                                                  'Editing permissions keeps access suspended.')),
                                        BusinessPermissionPicker(
                                            initial: permissions,
                                            enabled: !busy,
                                            onChanged: (v) => permissions = v),
                                        if (error != null)
                                          Text(error!,
                                              style: TextStyle(
                                                  color: Theme.of(ctx)
                                                      .colorScheme
                                                      .error)),
                                      ])
                                : Column(
                                    mainAxisSize: MainAxisSize.min,
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                        Text(bt(
                                            ctx,
                                            '이 코드를 초대한 직원에게 전달해 주세요. 24시간 동안 한 번 사용할 수 있고, 지정한 이메일로만 참여할 수 있습니다.',
                                            'Give this code to the invited staff member. It expires in 24 hours, works once and is bound to their email.')),
                                        const SizedBox(height: 12),
                                        SelectableText(
                                            invite!['token'] as String),
                                        TextButton.icon(
                                            onPressed: () => Clipboard.setData(
                                                ClipboardData(
                                                    text: invite!['token']
                                                        as String)),
                                            icon: const Icon(Icons.copy),
                                            label: Text(bt(ctx, '초대 코드 복사',
                                                'Copy invitation code'))),
                                      ])),
                        actions: [
                          TextButton(
                              onPressed: busy ? null : () => Navigator.pop(ctx),
                              child: Text(bt(ctx, '닫기', 'Close'))),
                          if (invite == null)
                            FilledButton(
                                onPressed: busy
                                    ? null
                                    : () async {
                                        if (permissions.isEmpty) {
                                          update(() => error = bt(
                                              ctx,
                                              '조회 권한을 최소 한 개 선택해 주세요.',
                                              'Select at least one read permission.'));
                                          return;
                                        }
                                        update(() => busy = true);
                                        try {
                                          final repo = ref
                                              .read(businessRepositoryProvider);
                                          if (member == null) {
                                            final result = await repo.invite(
                                                widget.workspace,
                                                email.text.trim(),
                                                permissions);
                                            if (ctx.mounted &&
                                                mounted &&
                                                account ==
                                                    ref.read(
                                                        activeAccountIdProvider)) {
                                              update(() => invite = result);
                                            }
                                          } else {
                                            await repo.member(
                                                widget.workspace,
                                                member['user_id'] as String,
                                                permissions,
                                                restore ||
                                                    member['active'] == true);
                                            if (ctx.mounted &&
                                                mounted &&
                                                account ==
                                                    ref.read(
                                                        activeAccountIdProvider)) {
                                              Navigator.pop(ctx);
                                            }
                                          }
                                          if (context.mounted &&
                                              mounted &&
                                              account ==
                                                  ref.read(
                                                      activeAccountIdProvider)) {
                                            _reload();
                                          }
                                        } catch (e) {
                                          if (ctx.mounted &&
                                              mounted &&
                                              account ==
                                                  ref.read(
                                                      activeAccountIdProvider)) {
                                            update(() =>
                                                error = businessError(ctx, e));
                                          }
                                        } finally {
                                          if (ctx.mounted) {
                                            update(() => busy = false);
                                          }
                                        }
                                      },
                                child: Text(bt(ctx, '저장', 'Save')))
                        ])))));
    await Future<void>.delayed(const Duration(milliseconds: 250));
    email.dispose();
  }

  Future<void> _revoke(Map<String, dynamic> member) async {
    final account = ref.read(activeAccountIdProvider);
    if (!await businessConfirm(
        context,
        bt(context, '이 직원의 업소 접근 권한을 해제할까요? 저장된 공동 자료와 작업 이력은 남습니다.',
            'Remove this person’s access? Shared records and work history remain.'))) {
      return;
    }
    try {
      await ref.read(businessRepositoryProvider).member(
          widget.workspace,
          member['user_id'] as String,
          Set<String>.from(member['permissions'] as List),
          false);
      if (context.mounted &&
          mounted &&
          account == ref.read(activeAccountIdProvider)) {
        _reload();
      }
    } catch (e) {
      if (context.mounted &&
          mounted &&
          account == ref.read(activeAccountIdProvider)) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(businessError(context, e))));
      }
    }
  }

  @override
  Widget build(BuildContext context) =>
      ref.watch(businessContextProvider(widget.workspace)).when(
          data: (business) {
            if (!business.owner) {
              return Scaffold(
                  appBar: AppBar(),
                  body: Center(
                      child: Text(bt(context, '사장만 직원 권한을 관리할 수 있습니다.',
                          'Only the owner can manage staff permissions.'))));
            }
            return Scaffold(
                appBar: AppBar(
                    title:
                        Text(bt(context, '직원·권한 관리', 'Staff & permissions'))),
                body: Center(
                    child: ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 860),
                        child: ListView(
                            padding: const EdgeInsets.all(20),
                            children: [
                              if (business.isTest)
                                const BusinessPracticeNotice(),
                              _BusinessWorkHeader(
                                  workspace: business.name,
                                  title: bt(context, '직원·권한 관리',
                                      'Staff & permissions'),
                                  subtitle: bt(
                                      context,
                                      '직원을 초대하고 맡은 업무에 필요한 권한을 관리하세요.',
                                      'Invite staff and manage access for their responsibilities.'),
                                  icon: Icons.groups_outlined),
                              const SizedBox(height: 12),
                              ScoutSectionLabel(
                                  number: '01',
                                  title: bt(context, '직원 초대·구매 승인 설정',
                                      'Invitations & purchase approval')),
                              FilledButton.icon(
                                  onPressed: business.paid
                                      ? () => _permissions()
                                      : null,
                                  icon: const Icon(Icons.person_add_alt),
                                  label: Text(
                                      bt(context, '직원 초대하기', 'Invite staff'))),
                              SwitchListTile(
                                  contentPadding: EdgeInsets.zero,
                                  title: Text(bt(context, '구매 승인 후 전달하기',
                                      'Require approval before sharing')),
                                  subtitle: Text(bt(
                                      context,
                                      '켜면 구매 작성자와 승인 권한자의 확인 단계를 구분합니다.',
                                      'When enabled, purchases pass through an approval step.')),
                                  value: business.approval,
                                  onChanged: (value) async {
                                    final account =
                                        ref.read(activeAccountIdProvider);
                                    if (!await businessConfirm(
                                        context,
                                        value
                                            ? bt(
                                                context,
                                                '앞으로 작성할 구매요청에 승인 단계를 사용할까요?',
                                                'Require approval for draft purchases?')
                                            : bt(
                                                context,
                                                '구매 담당자가 승인 대기 없이 요청서를 확정할 수 있게 할까요?',
                                                'Allow purchasers to finalize drafts without waiting for approval?'))) {
                                      return;
                                    }
                                    try {
                                      await ref
                                          .read(businessRepositoryProvider)
                                          .settings(widget.workspace,
                                              business.name, value);
                                      if (context.mounted &&
                                          mounted &&
                                          account ==
                                              ref.read(
                                                  activeAccountIdProvider)) {
                                        _reload();
                                      }
                                    } catch (e) {
                                      if (context.mounted &&
                                          mounted &&
                                          account ==
                                              ref.read(
                                                  activeAccountIdProvider)) {
                                        ScaffoldMessenger.of(context)
                                            .showSnackBar(SnackBar(
                                                content: Text(businessError(
                                                    context, e))));
                                      }
                                    }
                                  }),
                              ScoutSectionLabel(
                                  number: '02',
                                  title: bt(context, '구성원·초대 현황',
                                      'Members & invitations')),
                              FutureBuilder(
                                  future: _rows,
                                  builder: (context, snapshot) {
                                    if (snapshot.hasError) {
                                      return _BusinessError(
                                          snapshot.error!, _reload);
                                    }
                                    if (!snapshot.hasData) {
                                      return const LinearProgressIndicator();
                                    }
                                    return Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          Text(bt(context, '참여 직원', 'Members'),
                                              style: Theme.of(context)
                                                  .textTheme
                                                  .titleLarge),
                                          Text(bt(
                                              context,
                                              '사장이 담당자 정보와 업무 권한을 관리합니다. 이용 중지 시 공동 자료와 작업 이력은 보존됩니다.',
                                              'Manage staff profiles and permissions here. Suspending access preserves shared records and history.')),
                                          const SizedBox(height: 12),
                                          Wrap(
                                              spacing: 8,
                                              runSpacing: 6,
                                              children: [
                                                Chip(
                                                    label: LocalizedText(
                                                        '${bt(context, '전체', 'All')} ${snapshot.data![0].length}')),
                                                Chip(
                                                    label: LocalizedText(
                                                        '${bt(context, '이용 중', 'Active')} ${snapshot.data![0].where((m) => m['active'] == true).length}')),
                                                Chip(
                                                    label: LocalizedText(
                                                        '${bt(context, '이용 중지', 'Suspended')} ${snapshot.data![0].where((m) => m['active'] != true).length}')),
                                              ]),
                                          TextField(
                                              key: const ValueKey(
                                                  'staff-search'),
                                              decoration: InputDecoration(
                                                  prefixIcon:
                                                      const Icon(Icons.search),
                                                  labelText: bt(
                                                      context,
                                                      '이름·직책·업무 연락처 검색',
                                                      'Search name, job title or work contact')),
                                              onChanged: (value) => setState(
                                                  () => _query = value)),
                                          const SizedBox(height: 8),
                                          Wrap(
                                              spacing: 8,
                                              runSpacing: 6,
                                              children: [
                                                for (final status in [
                                                  'all',
                                                  'active',
                                                  'inactive'
                                                ])
                                                  ChoiceChip(
                                                      key: ValueKey(
                                                          'staff-filter-$status'),
                                                      label:
                                                          Text(switch (status) {
                                                        'active' => bt(context,
                                                            '이용 중', 'Active'),
                                                        'inactive' => bt(
                                                            context,
                                                            '이용 중지',
                                                            'Suspended'),
                                                        _ => bt(context, '전체',
                                                            'All')
                                                      }),
                                                      selected:
                                                          _status == status,
                                                      onSelected: (_) =>
                                                          setState(() =>
                                                              _status = status))
                                              ]),
                                          if (!snapshot.data![0].any(_matches))
                                            Padding(
                                                padding:
                                                    const EdgeInsets.symmetric(
                                                        vertical: 20),
                                                child: Text(bt(
                                                    context,
                                                    '조건에 맞는 담당자가 없습니다.',
                                                    'No staff match these filters.'))),
                                          for (final member in snapshot.data![0]
                                              .where(_matches))
                                            _staffCard(member),
                                          const SizedBox(height: 20),
                                          ExpansionTile(
                                              tilePadding: EdgeInsets.zero,
                                              title: Text(bt(
                                                  context,
                                                  '직원·권한 변경 이력',
                                                  'Staff access history')),
                                              subtitle: Text(bt(
                                                  context,
                                                  '최근 50건 · 사장만 확인',
                                                  'Latest 50 changes · owner only')),
                                              children: [
                                                for (final event
                                                    in snapshot.data![2])
                                                  ListTile(
                                                    contentPadding:
                                                        EdgeInsets.zero,
                                                    title: Text(switch (
                                                        event['action']) {
                                                      'invited' => bt(
                                                          context,
                                                          '직원 초대',
                                                          'Staff invited'),
                                                      'joined' => bt(
                                                          context,
                                                          '직원 참여',
                                                          'Staff joined'),
                                                      'profile' => bt(
                                                          context,
                                                          '담당자 정보 변경',
                                                          'Staff profile changed'),
                                                      'permissions' => bt(
                                                          context,
                                                          '권한 변경·복구',
                                                          'Access changed or restored'),
                                                      'revoked' => bt(
                                                          context,
                                                          '직원 접근 해제',
                                                          'Staff access removed'),
                                                      _ => bt(
                                                          context,
                                                          '업소 설정 변경',
                                                          'Business settings changed'),
                                                    }),
                                                    subtitle: LocalizedText(
                                                        '${_memberName(snapshot.data![0], event['actor_id'])} → ${_memberName(snapshot.data![0], event['subject_id'])}\n${_businessDate(context, event['created_at'])}'),
                                                  )
                                              ]),
                                          const SizedBox(height: 20),
                                          Text(
                                              bt(context, '최근 초대',
                                                  'Recent invitations'),
                                              style: Theme.of(context)
                                                  .textTheme
                                                  .titleLarge),
                                          for (final invite
                                              in snapshot.data![1])
                                            ListTile(
                                                contentPadding: EdgeInsets.zero,
                                                title: Text(
                                                    invite['email'] as String),
                                                subtitle: Text(invite['revoked'] ==
                                                        true
                                                    ? bt(
                                                        context, '취소됨', 'Revoked')
                                                    : invite['used_at'] != null
                                                        ? bt(context, '참여 완료',
                                                            'Accepted')
                                                        : bt(
                                                            context,
                                                            '만료: ${invite['expires_at']}',
                                                            'Expires: ${invite['expires_at']}')),
                                                trailing: invite['revoked'] == true ||
                                                        invite['used_at'] !=
                                                            null
                                                    ? null
                                                    : IconButton(
                                                        tooltip: bt(
                                                            context,
                                                            '초대 취소',
                                                            'Revoke invitation'),
                                                        icon: const Icon(Icons.close),
                                                        onPressed: () async {
                                                          final owner = ref.read(
                                                              activeAccountIdProvider);
                                                          try {
                                                            await ref
                                                                .read(
                                                                    businessRepositoryProvider)
                                                                .revokeInvite(
                                                                    invite['id']
                                                                        as String);
                                                            if (context
                                                                    .mounted &&
                                                                mounted &&
                                                                owner ==
                                                                    ref.read(
                                                                        activeAccountIdProvider)) {
                                                              _reload();
                                                            }
                                                          } catch (e) {
                                                            if (context
                                                                    .mounted &&
                                                                mounted &&
                                                                owner ==
                                                                    ref.read(
                                                                        activeAccountIdProvider)) {
                                                              ScaffoldMessenger
                                                                      .of(
                                                                          context)
                                                                  .showSnackBar(SnackBar(
                                                                      content: Text(businessError(
                                                                          context,
                                                                          e))));
                                                            }
                                                          }
                                                        })),
                                        ]);
                                  }),
                            ]))));
          },
          loading: () =>
              const Scaffold(body: Center(child: CircularProgressIndicator())),
          error: (e, _) => Scaffold(
              appBar: AppBar(),
              body: _BusinessError(
                  e,
                  () => ref
                      .invalidate(businessContextProvider(widget.workspace)))));
}
