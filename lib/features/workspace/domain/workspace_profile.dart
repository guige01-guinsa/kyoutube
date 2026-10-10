enum WorkspaceMode { personal, professional, supplier }

enum ProfessionalDuty { purchasing, culinary, management }

const allProfessionalDuties = {
  ProfessionalDuty.purchasing,
  ProfessionalDuty.culinary,
  ProfessionalDuty.management,
};

/// Presentation preferences only. Never an authorization or membership role.
class WorkspaceProfile {
  const WorkspaceProfile(
      {this.active,
      this.enabled = const {},
      this.duties = allProfessionalDuties,
      this.focus,
      this.dutiesConfigured = false});
  static const metadataKey = 'scout_workspace_v1';
  final WorkspaceMode? active;
  final Set<WorkspaceMode> enabled;
  final Set<ProfessionalDuty> duties;
  final ProfessionalDuty? focus;
  final bool dutiesConfigured;
  bool get configured => active != null && enabled.contains(active);
  Set<ProfessionalDuty> get effectiveDuties =>
      duties.isEmpty ? allProfessionalDuties : duties;
  ProfessionalDuty? get effectiveDuty => effectiveDuties.length == 1
      ? effectiveDuties.first
      : (effectiveDuties.contains(focus) ? focus : null);
  WorkspaceProfile activate(WorkspaceMode mode) {
    if (!enabled.contains(mode)) throw ArgumentError('Inactive workspace');
    return WorkspaceProfile(
        active: mode,
        enabled: enabled,
        duties: duties,
        focus: focus,
        dutiesConfigured: dutiesConfigured);
  }

  WorkspaceProfile focusOn(ProfessionalDuty? value) {
    if (value != null && !effectiveDuties.contains(value)) {
      throw ArgumentError('Inactive duty');
    }
    return WorkspaceProfile(
        active: active,
        enabled: enabled,
        duties: effectiveDuties,
        focus: value,
        dutiesConfigured: true);
  }

  Map<String, dynamic> toJson() {
    if (!configured) throw StateError('Choose a workspace');
    return {
      'schema': 1,
      'active': active!.name,
      'enabled': WorkspaceMode.values
          .where(enabled.contains)
          .map((m) => m.name)
          .toList(),
      if (dutiesConfigured)
        'professional': {
          'duties': ProfessionalDuty.values
              .where(effectiveDuties.contains)
              .map((d) => d.name)
              .toList(),
          'focus': effectiveDuty?.name,
        },
    };
  }

  factory WorkspaceProfile.fromJson(Object? value) {
    if (value is! Map || value['schema'] != 1 || value['enabled'] is! List) {
      return const WorkspaceProfile();
    }
    final modes = WorkspaceMode.values
        .where((m) => (value['enabled'] as List).contains(m.name))
        .toSet();
    final active = WorkspaceMode.values
        .where((m) => m.name == value['active'])
        .firstOrNull;
    if (active == null || !modes.contains(active)) {
      return const WorkspaceProfile();
    }
    final work = value['professional'];
    final selected = work is Map && work['duties'] is List
        ? ProfessionalDuty.values
            .where((d) => (work['duties'] as List).contains(d.name))
            .toSet()
        : <ProfessionalDuty>{};
    final focus = work is Map
        ? selected.where((d) => d.name == work['focus']).firstOrNull
        : null;
    return WorkspaceProfile(
        active: active,
        enabled: Set.unmodifiable(modes),
        duties: selected.isEmpty
            ? allProfessionalDuties
            : Set.unmodifiable(selected),
        focus: focus,
        dutiesConfigured: selected.isNotEmpty);
  }
}
