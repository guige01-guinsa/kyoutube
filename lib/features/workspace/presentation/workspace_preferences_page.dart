import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../auth/application/auth_providers.dart';
import '../application/workspace_profile_controller.dart';
import '../domain/workspace_profile.dart';
import 'workspace_menu.dart';

class WorkspacePreferencesPage extends ConsumerWidget {
  const WorkspacePreferencesPage({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) => Scaffold(
        appBar: AppBar(
            title: Text(workspaceText(context, '이용 목적 관리', 'Manage purposes'))),
        body: ref.watch(workspaceProfileProvider).when(
              data: (profile) => PurposeEditor(
                  key: ValueKey(ref.watch(activeAccountIdProvider)),
                  initial: profile),
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (_, __) => WorkspacePreferenceError(
                  onRetry: () =>
                      ref.read(workspaceProfileProvider.notifier).reload()),
            ),
      );
}

class WorkspacePreferenceError extends StatelessWidget {
  const WorkspacePreferenceError({super.key, required this.onRetry});
  final VoidCallback onRetry;
  @override
  Widget build(BuildContext context) => Center(
      child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Text(workspaceText(context, '이용 화면 설정을 불러오지 못했어요.',
                'Could not load your workspace preferences.')),
            const SizedBox(height: 12),
            FilledButton(
                onPressed: onRetry,
                child: Text(workspaceText(context, '다시 시도', 'Retry'))),
          ])));
}

class PurposeEditor extends ConsumerStatefulWidget {
  const PurposeEditor({super.key, required this.initial});
  final WorkspaceProfile initial;
  @override
  ConsumerState<PurposeEditor> createState() => _PurposeEditorState();
}

class _PurposeEditorState extends ConsumerState<PurposeEditor> {
  late final Set<WorkspaceMode> _enabled = {...widget.initial.enabled};
  late WorkspaceMode? _active = widget.initial.active;
  late final Set<ProfessionalDuty> _duties = {
    ...widget.initial.effectiveDuties
  };
  late ProfessionalDuty? _focus = widget.initial.effectiveDuty;
  bool _busy = false;
  String? _error;
  Future<void> _save() async {
    if (_active == null || _enabled.isEmpty || _busy) return;
    final owner = ref.read(activeAccountIdProvider);
    final controller = ref.read(workspaceProfileProvider.notifier);
    setState(() {
      _busy = true;
      _error = null;
    });
    final saved = await controller.save(WorkspaceProfile(
        active: _active,
        enabled: Set.unmodifiable(_enabled),
        duties: Set.unmodifiable(_duties),
        focus: _focus,
        dutiesConfigured: _enabled.contains(WorkspaceMode.professional) ||
            widget.initial.dutiesConfigured));
    if (!mounted || owner != ref.read(activeAccountIdProvider)) return;
    if (saved) {
      setState(() => _busy = false);
      // Release the saving guard before replacing the current route.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && owner == ref.read(activeAccountIdProvider)) {
          context.go(workspaceStartPath(_active!));
        }
      });
      return;
    }
    setState(() {
      _busy = false;
      _error = workspaceText(context, '설정을 저장하지 못했어요. 연결 상태를 확인하고 다시 시도해 주세요.',
          'Could not save your preferences. Check your connection and try again.');
    });
  }

  @override
  Widget build(BuildContext context) {
    String tr(String ko, String en) => workspaceText(context, ko, en);
    return PopScope(
        canPop: !_busy,
        child: Center(
            child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 760),
                child: ListView(
                  padding: const EdgeInsets.all(24),
                  children: [
                    Text(tr('나에게 맞는 레시피 스카우트', 'Recipe Scout, tailored to you'),
                        style: Theme.of(context).textTheme.headlineSmall),
                    const SizedBox(height: 12),
                    Text(tr('이용 목적을 선택해 주세요. 여러 용도를 함께 선택하고 나중에 바꿀 수 있어요.',
                        'Choose how you will use Recipe Scout. Select more than one purpose and change them later.')),
                    const SizedBox(height: 24),
                    for (final mode in WorkspaceMode.values)
                      Padding(
                          padding: const EdgeInsets.only(bottom: 12),
                          child: Card(
                              margin: EdgeInsets.zero,
                              color: _enabled.contains(mode)
                                  ? const Color(0xfff0e6ec)
                                  : null,
                              child: CheckboxListTile(
                                key: ValueKey('purpose-${mode.name}'),
                                value: _enabled.contains(mode),
                                controlAffinity:
                                    ListTileControlAffinity.trailing,
                                secondary: Icon(modeIcon(mode)),
                                title: Text(modeTitle(context, mode)),
                                subtitle: Text(modeDescription(context, mode)),
                                contentPadding: const EdgeInsets.all(18),
                                onChanged: _busy
                                    ? null
                                    : (selected) => setState(() {
                                          if (selected == true) {
                                            _enabled.add(mode);
                                            _active ??= mode;
                                          } else {
                                            _enabled.remove(mode);
                                            if (_active == mode) {
                                              _active = _enabled.firstOrNull;
                                            }
                                          }
                                        }),
                              ))),
                    if (_enabled.contains(WorkspaceMode.professional)) ...[
                      const SizedBox(height: 16),
                      Text(tr('맡고 있는 업무', 'Your responsibilities'),
                          style: Theme.of(context).textTheme.titleLarge),
                      const SizedBox(height: 8),
                      Text(tr('맡은 업무에 맞춰 개인 작업실 안내를 보여 드려요.',
                          'Your personal studio guidance follows your responsibilities.')),
                      for (final duty in ProfessionalDuty.values)
                        CheckboxListTile(
                          key: ValueKey('duty-${duty.name}'),
                          contentPadding: EdgeInsets.zero,
                          title: Text(dutyTitle(context, duty)),
                          subtitle: Text(dutyDescription(context, duty)),
                          value: _duties.contains(duty),
                          onChanged: _busy
                              ? null
                              : (value) => setState(() {
                                    if (value == true) {
                                      _duties.add(duty);
                                    } else if (_duties.length > 1) {
                                      _duties.remove(duty);
                                    }
                                    if (!_duties.contains(_focus)) {
                                      _focus = null;
                                    }
                                  }),
                        ),
                      if (_duties.length > 1)
                        DropdownButtonFormField<String>(
                            key: ValueKey(
                                'duty-focus-${_duties.map((d) => d.name).join(',')}'),
                            initialValue: _focus?.name ?? 'all',
                            isExpanded: true,
                            decoration: InputDecoration(
                                labelText: tr('처음 볼 업무', 'Default work view')),
                            items: [
                              DropdownMenuItem(
                                  value: 'all',
                                  child: Text(tr('선택한 업무 한눈에',
                                      'All selected responsibilities'))),
                              for (final duty in ProfessionalDuty.values
                                  .where(_duties.contains))
                                DropdownMenuItem(
                                    value: duty.name,
                                    child: Text(dutyTitle(context, duty)))
                            ],
                            onChanged: _busy
                                ? null
                                : (value) => setState(() => _focus =
                                    ProfessionalDuty.values
                                        .where((d) => d.name == value)
                                        .firstOrNull)),
                      const SizedBox(height: 12),
                      Text(
                          tr('최소 한 업무를 선택해 주세요. 이 설정은 내 화면을 정리하며 직원 초대나 자료 공유 권한을 부여하지 않습니다.',
                              'Keep at least one responsibility selected. These preferences organize your view; they do not invite staff or grant access to shared records.'),
                          style: Theme.of(context).textTheme.bodySmall),
                    ],
                    if (_enabled.length > 1) ...[
                      const SizedBox(height: 12),
                      DropdownButtonFormField<WorkspaceMode>(
                          key: ValueKey(_enabled.map((m) => m.name).join(',')),
                          initialValue: _active,
                          isExpanded: true,
                          decoration: InputDecoration(
                              labelText:
                                  tr('처음 열 화면', 'Start in this workspace')),
                          items: WorkspaceMode.values
                              .where(_enabled.contains)
                              .map((m) => DropdownMenuItem(
                                  value: m, child: Text(modeTitle(context, m))))
                              .toList(),
                          onChanged: _busy
                              ? null
                              : (v) => setState(() => _active = v)),
                    ],
                    const SizedBox(height: 20),
                    Text(
                        tr('레시피와 구매 자료는 같은 계정에서 함께 사용해요. 화면을 바꾸어도 이용권한과 요금제는 그대로예요.',
                            'Recipes and purchasing records stay shared within your account. Switching workspaces does not change your plan or permissions.'),
                        style: Theme.of(context).textTheme.bodySmall),
                    if (_error != null)
                      Padding(
                          padding: const EdgeInsets.only(top: 16),
                          child: Text(_error!,
                              style: TextStyle(
                                  color: Theme.of(context).colorScheme.error))),
                    const SizedBox(height: 24),
                    FilledButton.icon(
                        key: const Key('save-workspace-purpose'),
                        onPressed: _busy || _active == null ? null : _save,
                        icon: _busy
                            ? const SizedBox(
                                width: 18,
                                height: 18,
                                child:
                                    CircularProgressIndicator(strokeWidth: 2))
                            : const Icon(Icons.arrow_forward),
                        label:
                            Text(tr('이 화면으로 시작', 'Start in this workspace'))),
                  ],
                ))));
  }
}

/// The router's existing editor exit guards run before this page is entered.
class WorkspaceSwitchPage extends ConsumerStatefulWidget {
  const WorkspaceSwitchPage({super.key, required this.mode});
  final String mode;
  @override
  ConsumerState<WorkspaceSwitchPage> createState() =>
      _WorkspaceSwitchPageState();
}

class _WorkspaceSwitchPageState extends ConsumerState<WorkspaceSwitchPage> {
  bool _started = false, _failed = false;
  Future<void> _switch(WorkspaceProfile profile) async {
    final mode =
        WorkspaceMode.values.where((m) => m.name == widget.mode).firstOrNull;
    if (mode == null ||
        (mode != WorkspaceMode.personal && !profile.enabled.contains(mode))) {
      if (mounted) context.go('/workspace-settings');
      return;
    }
    final owner = ref.read(activeAccountIdProvider);
    final next = mode == WorkspaceMode.personal
        ? WorkspaceProfile(
            active: mode,
            enabled: {...profile.enabled, mode},
            duties: profile.duties,
            focus: profile.focus,
            dutiesConfigured: profile.dutiesConfigured)
        : profile.activate(mode);
    final saved = await ref.read(workspaceProfileProvider.notifier).save(next);
    if (!mounted || owner != ref.read(activeAccountIdProvider)) return;
    if (saved) {
      context.go(workspaceStartPath(mode));
    } else {
      setState(() => _failed = true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final value = ref.watch(workspaceProfileProvider);
    if (!_started && value.valueOrNull != null) {
      _started = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _switch(value.requireValue);
      });
    }
    return Scaffold(
        appBar: AppBar(
            title:
                Text(workspaceText(context, '이용 화면 전환', 'Switch workspace'))),
        body: _failed || value.hasError
            ? WorkspacePreferenceError(
                onRetry: () => context.go('/workspace-settings'))
            : const Center(child: CircularProgressIndicator()));
  }
}
