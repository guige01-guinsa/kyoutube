import 'package:flutter/material.dart';
import 'package:k_youtube/core/localization/localized_text.dart';
import '../theme/app_theme.dart';

class CenteredStateView extends StatelessWidget {
  const CenteredStateView(
      {super.key,
      required this.icon,
      required this.title,
      required this.message,
      this.actionLabel,
      this.onAction,
      this.secondaryActionLabel,
      this.onSecondaryAction});
  final IconData icon;
  final String title;
  final String message;
  final String? actionLabel;
  final VoidCallback? onAction;
  final String? secondaryActionLabel;
  final VoidCallback? onSecondaryAction;

  @override
  Widget build(BuildContext context) =>
      LayoutBuilder(builder: (context, constraints) {
        final content = Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 32),
          child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 400),
              child: Column(mainAxisSize: MainAxisSize.min, children: <Widget>[
                Container(
                    width: 80,
                    height: 80,
                    decoration: BoxDecoration(
                        color: ScoutStyle.mint,
                        borderRadius: BorderRadius.circular(28)),
                    child: Icon(icon, size: 36, color: ScoutStyle.forest)),
                const SizedBox(height: 22),
                LocalizedText(title,
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.titleLarge),
                const SizedBox(height: 10),
                LocalizedText(message,
                    textAlign: TextAlign.center,
                    style: Theme.of(context)
                        .textTheme
                        .bodyMedium
                        ?.copyWith(color: ScoutStyle.muted)),
                if (actionLabel != null && onAction != null) ...<Widget>[
                  const SizedBox(height: 22),
                  FilledButton(
                      onPressed: onAction, child: LocalizedText(actionLabel!))
                ],
                if (secondaryActionLabel != null &&
                    onSecondaryAction != null) ...<Widget>[
                  const SizedBox(height: 8),
                  TextButton(
                      onPressed: onSecondaryAction,
                      child: LocalizedText(secondaryActionLabel!))
                ],
              ])),
        );
        return Center(
            child: constraints.hasBoundedHeight
                ? SingleChildScrollView(child: content)
                : content);
      });
}
