import 'package:flutter/material.dart';
import 'package:k_youtube/core/localization/localized_text.dart';

class ScoutSectionHeading extends StatelessWidget {
  const ScoutSectionHeading(
      {super.key, required this.title, this.subtitle, this.trailing});
  final String title;
  final String? subtitle;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: <Widget>[
        Expanded(
            child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
              LocalizedText(title,
                  style: Theme.of(context).textTheme.titleLarge),
              if (subtitle != null) ...<Widget>[
                const SizedBox(height: 4),
                LocalizedText(subtitle!,
                    style: Theme.of(context).textTheme.bodySmall)
              ],
            ])),
        if (trailing != null) trailing!,
      ],
    );
  }
}
