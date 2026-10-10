import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../core/web/browser_lifecycle.dart';
import '../../../core/localization/app_localizations.dart';
import '../../auth/application/auth_providers.dart';

final workspaceNavigationProvider = Provider((ref) => WorkspaceNavigation());

Future<bool> confirmWorkspaceDiscard(BuildContext context) async {
  final en = AppLocalizations.of(context).isEnglish;
  return await showDialog<bool>(
          context: context,
          builder: (ctx) => AlertDialog(
                title: Text(en ? 'Leave without saving?' : '저장하지 않고 나갈까요?'),
                content: Text(en
                    ? 'Your unsaved edits will be lost.'
                    : '저장하지 않은 변경 내용은 사라집니다.'),
                actions: [
                  TextButton(
                      onPressed: () => Navigator.pop(ctx, false),
                      child: Text(en ? 'Keep editing' : '계속 편집')),
                  FilledButton(
                      onPressed: () => Navigator.pop(ctx, true),
                      child: Text(en ? 'Leave' : '나가기'))
                ],
              )) ==
      true;
}

class WorkspaceNavigation {
  final _guards = <Object, Future<bool> Function()>{};
  bool _checking = false;
  void register(Object key, Future<bool> Function() guard) =>
      _guards[key] = guard;
  void remove(Object key) => _guards.remove(key);
  Future<bool> confirmLeave() async {
    if (_checking) return false;
    _checking = true;
    try {
      for (final guard in _guards.values.toList()) {
        if (!await guard()) return false;
      }
      return true;
    } finally {
      _checking = false;
    }
  }
}

/// Covers desktop navigation and browser refresh while an editor is dirty.
/// Account changes always dispose the old account's editor without a prompt.
class WorkspaceEditGuard extends ConsumerStatefulWidget {
  const WorkspaceEditGuard(
      {super.key,
      required this.dirty,
      required this.busy,
      required this.confirmLeave,
      required this.child});
  final bool dirty, busy;
  final Future<bool> Function() confirmLeave;
  final Widget child;
  @override
  ConsumerState<WorkspaceEditGuard> createState() => _WorkspaceEditGuardState();
}

class _WorkspaceEditGuardState extends ConsumerState<WorkspaceEditGuard> {
  late final WorkspaceNavigation _navigation;
  String? _owner;
  void Function()? _stopWarning;
  @override
  void initState() {
    super.initState();
    _owner = ref.read(activeAccountIdProvider);
    _navigation = ref.read(workspaceNavigationProvider);
    _navigation.register(this, () async {
      try {
        if (_owner != Supabase.instance.client.auth.currentUser?.id) {
          return true;
        }
      } catch (_) {
        // Provider-only widget tests need no global Supabase singleton.
      }
      if (!mounted ||
          _owner != ref.read(activeAccountIdProvider) ||
          !(ModalRoute.of(context)?.isCurrent ?? true)) {
        return true;
      }
      if (widget.busy) return false;
      return !widget.dirty || await widget.confirmLeave();
    });
    _updateWarning();
  }

  void _updateWarning() {
    _stopWarning?.call();
    _stopWarning =
        widget.dirty || widget.busy ? warnBeforeBrowserClose() : null;
  }

  @override
  void didUpdateWidget(WorkspaceEditGuard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.dirty != widget.dirty || oldWidget.busy != widget.busy) {
      _updateWarning();
    }
  }

  @override
  void dispose() {
    _navigation.remove(this);
    _stopWarning?.call();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
