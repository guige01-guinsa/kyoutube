import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../../core/localization/app_localizations.dart';
import '../domain/guide_curriculum.dart';

/// Push a public lesson above the active workspace; Back keeps the current work.
class GuideHelpButton extends StatelessWidget {
  const GuideHelpButton({super.key, required this.lesson, this.enabled = true});
  final String lesson;
  final bool enabled;
  @override
  Widget build(BuildContext context) => IconButton(
        tooltip: AppLocalizations.of(context).isEnglish
            ? 'Practice this task'
            : '이 작업 체험 안내',
        icon: const Icon(Icons.help_outline),
        onPressed: enabled ? () => context.push(guideLessonPath(lesson)) : null,
      );
}
