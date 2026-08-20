import 'package:flutter/material.dart';

import '../../application/password_policy.dart';

class PasswordStrengthPanel extends StatelessWidget {
  const PasswordStrengthPanel({
    super.key,
    required this.password,
  });

  final String password;

  @override
  Widget build(BuildContext context) {
    final strength = PasswordPolicy.evaluate(password);
    final colorScheme = Theme.of(context).colorScheme;

    final strengthColor = switch (strength.score) {
      0 || 1 => colorScheme.error,
      2 => Colors.orange.shade700,
      3 => Colors.teal.shade700,
      _ => Colors.green.shade700,
    };

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerHighest.withValues(alpha: 0.45),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              const Text(
                '비밀번호 강도',
                style: TextStyle(fontWeight: FontWeight.w700),
              ),
              const Spacer(),
              Text(
                strength.label,
                style: TextStyle(
                  color: strengthColor,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          LinearProgressIndicator(
            value: strength.score / 4,
            minHeight: 6,
            borderRadius: BorderRadius.circular(99),
            color: strengthColor,
            backgroundColor: colorScheme.outlineVariant,
          ),
          const SizedBox(height: 10),
          _RuleLine(
            label: '8자 이상 입력',
            passed: strength.hasMinimumLength,
          ),
          _RuleLine(
            label: '영문 포함',
            passed: strength.hasLetter,
          ),
          _RuleLine(
            label: '숫자 포함',
            passed: strength.hasNumber,
          ),
          _RuleLine(
            label: '특수문자 또는 12자 이상 사용 권장',
            passed: strength.hasSpecialCharacter || strength.hasLongLength,
            optional: true,
          ),
        ],
      ),
    );
  }
}

class _RuleLine extends StatelessWidget {
  const _RuleLine({
    required this.label,
    required this.passed,
    this.optional = false,
  });

  final String label;
  final bool passed;
  final bool optional;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final color = passed
        ? Colors.green.shade700
        : optional
            ? colorScheme.onSurfaceVariant
            : colorScheme.error;

    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Row(
        children: <Widget>[
          Icon(
            passed
                ? Icons.check_circle_outline
                : optional
                    ? Icons.info_outline
                    : Icons.radio_button_unchecked,
            size: 18,
            color: color,
          ),
          const SizedBox(width: 8),
          Text(
            label,
            style: TextStyle(
              color: color,
              fontSize: 13,
            ),
          ),
        ],
      ),
    );
  }
}
