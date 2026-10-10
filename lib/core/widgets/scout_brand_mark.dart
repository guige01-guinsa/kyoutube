import 'package:flutter/material.dart';
import '../theme/app_theme.dart';

class ScoutBrandMark extends StatelessWidget {
  const ScoutBrandMark({
    super.key,
    this.size = 34,
    this.excludeFromSemantics = false,
  });

  final double size;
  final bool excludeFromSemantics;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: excludeFromSemantics ? null : '레시피 스카우트',
      excludeSemantics: true,
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          color: ScoutStyle.plum,
          borderRadius: BorderRadius.circular(size * 0.3),
        ),
        child: Icon(Icons.rice_bowl_outlined,
            size: size * 0.68, color: ScoutStyle.cream),
      ),
    );
  }
}
