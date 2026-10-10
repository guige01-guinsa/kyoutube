import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:k_youtube/core/localization/app_localizations.dart';
import 'package:k_youtube/features/auth/application/password_policy.dart';

void main() {
  const english = AppLocalizations(Locale('en'));
  const spanish = AppLocalizations(
      Locale.fromSubtags(languageCode: 'es', countryCode: '419'));

  test('uses Latin American Spanish and never falls back to Korean', () {
    expect(AppLocalizations.resolveLocale(const Locale('es', 'MX')),
        const Locale.fromSubtags(languageCode: 'es', countryCode: '419'));
    expect(spanish.appName, 'Explorador de recetas');
    expect(spanish.shopping, 'Compras');
    expect(spanish.translate('재료 3개'), isNot(contains(RegExp(r'[가-힣]'))));
    expect(spanish.translate('장보기 목록 만들기 · 2개'),
        isNot(contains(RegExp(r'[가-힣]'))));
  });

  test('dynamic UI messages are translated', () {
    expect(english.translate('선택한 YouTube 영상 정보가 올바르지 않습니다.'),
        'The selected YouTube video information is invalid. Please select the video again.');
    expect(english.translate('재료 3개'), '3 ingredients');
    expect(english.translate('장보기 2개 · 구매할 재료 7개'),
        '2 shopping lists · 7 items to buy');
    expect(english.translate('김치 구매 상태 변경'), 'Change purchase status for 김치');
    expect(
      english.translate(PasswordPolicy.validateForSignUp('short')!),
      'Enter at least 8 characters for the password.',
    );
  });

  test('localized UI literals do not leave Korean interface text', () {
    final root = Directory('lib');
    final literalPatterns = <RegExp>[
      RegExp(r"LocalizedText(?:\.rich)?\(\s*'((?:\\.|[^'])*)'"),
      RegExp(r"context\.tr\(\s*'((?:\\.|[^'])*)'\s*\)"),
    ];
    final missing = <String>[];

    for (final file in root
        .listSync(recursive: true)
        .whereType<File>()
        .where((item) => item.path.endsWith('.dart'))) {
      final source = file.readAsStringSync();
      for (final pattern in literalPatterns) {
        for (final match in pattern.allMatches(source)) {
          final literal = match
              .group(1)!
              .replaceAll(r'\n', '\n')
              .replaceAll(RegExp(r'\$\{[^}]+\}'), '1')
              .replaceAll(RegExp(r'\$[A-Za-z_][A-Za-z0-9_]*'), '1');
          if (!RegExp(r'[가-힣]').hasMatch(literal)) continue;
          final translated = english.translate(literal);
          if (RegExp(r'[가-힣]').hasMatch(translated)) {
            missing.add('${file.path}: $literal');
          }
        }
      }
    }

    expect(missing, isEmpty,
        reason: 'Every localized UI literal needs an English translation:\n'
            '${missing.join('\n')}');
  });

  test('presentation source has translations for Korean string literals', () {
    final files = Directory('lib')
        .listSync(recursive: true)
        .whereType<File>()
        .where((file) => file.path.endsWith('.dart'))
        .where((file) =>
            file.path.endsWith('lib${Platform.pathSeparator}app.dart') ||
            file.path.contains(
                '${Platform.pathSeparator}presentation${Platform.pathSeparator}') ||
            file.path.contains(
                '${Platform.pathSeparator}core${Platform.pathSeparator}widgets${Platform.pathSeparator}'));
    final literalPattern = RegExp(r"(?<![A-Za-z0-9_])'((?:\\.|[^'])*)'");
    final missing = <String>[];

    for (final file in files) {
      final source = file.readAsStringSync();
      for (final match in literalPattern.allMatches(source)) {
        final literal = match
            .group(1)!
            .replaceAll(r'\n', '\n')
            .replaceAll(RegExp(r'\$\{[^}]+\}'), '1')
            .replaceAll(RegExp(r'\$[A-Za-z_][A-Za-z0-9_]*'), '1')
            .trim();
        if (!RegExp(r'[가-힣]').hasMatch(literal)) continue;
        if (RegExp(r'[\[\]\\^?*+{}]').hasMatch(literal)) continue;
        if (RegExp(r'[가-힣]\s*/\s*[가-힣]').hasMatch(literal)) continue;
        final translated = english.translate(literal);
        if (RegExp(r'[가-힣]').hasMatch(translated)) {
          missing.add('${file.path}: $literal');
        }
      }
    }

    expect(missing, isEmpty,
        reason: 'Every Korean presentation literal needs a catalog entry:\n'
            '${missing.join('\n')}');
  });
}
