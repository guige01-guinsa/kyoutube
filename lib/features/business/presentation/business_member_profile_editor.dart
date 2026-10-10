part of 'business_pages.dart';

Future<bool> editBusinessMemberProfile(BuildContext context, WidgetRef ref,
    String workspace, Map<String, dynamic> member) async {
  final account = ref.read(activeAccountIdProvider);
  final name = TextEditingController(text: member['display_name'] as String);
  final title =
      TextEditingController(text: member['job_title'] as String? ?? '');
  final contact =
      TextEditingController(text: member['work_contact'] as String? ?? '');
  final form = GlobalKey<FormState>();
  bool busy = false;
  String? error;
  final saved = await showDialog<bool>(
          context: context,
          barrierDismissible: false,
          builder: (ctx) => ShoppingAccountGuard(
              child: StatefulBuilder(
                  builder: (ctx, update) => PopScope(
                      canPop: !busy,
                      child: AlertDialog(
                          scrollable: true,
                          insetPadding: const EdgeInsets.symmetric(
                              horizontal: 16, vertical: 24),
                          title:
                              Text(bt(ctx, '담당자 정보 수정', 'Edit staff profile')),
                          content: SizedBox(
                              width: 440,
                              child: Form(
                                  key: form,
                                  child: Column(
                                      mainAxisSize: MainAxisSize.min,
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        TextFormField(
                                            key: const ValueKey(
                                                'staff-profile-name'),
                                            controller: name,
                                            enabled: !busy,
                                            maxLength: 120,
                                            decoration: InputDecoration(
                                                labelText: bt(ctx, '표시 이름',
                                                    'Display name')),
                                            validator: (v) =>
                                                v == null || v.trim().isEmpty
                                                    ? bt(ctx, '이름을 입력해 주세요.',
                                                        'Enter a name.')
                                                    : null),
                                        TextFormField(
                                            key: const ValueKey(
                                                'staff-profile-title'),
                                            controller: title,
                                            enabled: !busy,
                                            maxLength: 80,
                                            decoration: InputDecoration(
                                                labelText: bt(ctx, '직책 (선택)',
                                                    'Job title'))),
                                        Text(bt(
                                            ctx,
                                            '직책은 표시용입니다. 실제 접근 권한은 별도로 지정합니다.',
                                            'A job title is a label. Access permissions are managed separately.')),
                                        const SizedBox(height: 12),
                                        TextFormField(
                                            key: const ValueKey(
                                                'staff-profile-contact'),
                                            controller: contact,
                                            enabled: !busy,
                                            maxLength: 120,
                                            decoration: InputDecoration(
                                                labelText: bt(ctx, '업무 연락처',
                                                    'Work contact'))),
                                        Text(bt(
                                            ctx,
                                            '업무용 전화번호나 이메일을 입력하세요. 이 정보는 사장과 본인만 조회할 수 있습니다.',
                                            'Use a work phone number or email. Only the owner and this member can read this profile.')),
                                        if (error != null)
                                          Text(error!,
                                              style: TextStyle(
                                                  color: Theme.of(ctx)
                                                      .colorScheme
                                                      .error))
                                      ]))),
                          actions: [
                            TextButton(
                                onPressed: busy
                                    ? null
                                    : () => Navigator.pop(ctx, false),
                                child: Text(bt(ctx, '취소', 'Cancel'))),
                            FilledButton(
                                key: const ValueKey('staff-profile-save'),
                                onPressed: busy
                                    ? null
                                    : () async {
                                        if (!form.currentState!.validate() ||
                                            account !=
                                                ref.read(
                                                    activeAccountIdProvider)) {
                                          return;
                                        }
                                        update(() {
                                          busy = true;
                                          error = null;
                                        });
                                        try {
                                          await ref
                                              .read(businessRepositoryProvider)
                                              .memberProfile(workspace,
                                                  member['user_id'] as String,
                                                  displayName: name.text,
                                                  jobTitle: title.text,
                                                  workContact: contact.text,
                                                  revision:
                                                      (member['profile_revision']
                                                                  as num?)
                                                              ?.toInt() ??
                                                          1);
                                          if (ctx.mounted &&
                                              account ==
                                                  ref.read(
                                                      activeAccountIdProvider)) {
                                            Navigator.pop(ctx, true);
                                          }
                                        } catch (e) {
                                          if (ctx.mounted &&
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
                          ]))))) ??
      false;
  await Future<void>.delayed(const Duration(milliseconds: 250));
  name.dispose();
  title.dispose();
  contact.dispose();
  return saved;
}
