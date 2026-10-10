import 'dart:convert';

import 'package:flutter/material.dart';

import '../../../core/theme/app_theme.dart';

class RecipeContentStyle {
  const RecipeContentStyle({
    this.size = 'normal',
    this.bold = false,
    this.color = 'default',
  });

  final String size;
  final bool bold;
  final String color;

  bool get isDefault => size == 'normal' && !bold && color == 'default';

  factory RecipeContentStyle.fromJson(Object? value) {
    if (value is! Map) return const RecipeContentStyle();
    final map = Map<String, dynamic>.from(value);
    final rawSize = map['size'] ?? map['z'];
    final rawColor = map['color'] ?? map['c'];
    final size = <String>{'small', 'normal', 'large'}.contains(rawSize)
        ? rawSize as String
        : 'normal';
    final color =
        <String>{'default', 'forest', 'blue', 'coral'}.contains(rawColor)
            ? rawColor as String
            : 'default';
    return RecipeContentStyle(
      size: size,
      bold: map['bold'] == true || map['b'] == true,
      color: color,
    );
  }

  Map<String, dynamic> toJson() => <String, dynamic>{
        if (size != 'normal') 'z': size,
        if (bold) 'b': true,
        if (color != 'default') 'c': color,
      };

  RecipeContentStyle copyWith({String? size, bool? bold, String? color}) {
    return RecipeContentStyle(
      size: size ?? this.size,
      bold: bold ?? this.bold,
      color: color ?? this.color,
    );
  }

  TextStyle apply(BuildContext context, TextStyle? base) {
    final baseSize = base?.fontSize ?? 17.0;
    final fontSize = switch (size) {
      'small' => baseSize * 0.85,
      'large' => baseSize * 1.2,
      _ => baseSize,
    };
    final textColor = switch (color) {
      'forest' => ScoutStyle.forest,
      'blue' => const Color(0xFF185FA5),
      'coral' => const Color(0xFFB5473C),
      _ => base?.color ?? Theme.of(context).colorScheme.onSurface,
    };
    return (base ?? const TextStyle()).copyWith(
      fontSize: fontSize,
      fontWeight: bold ? FontWeight.w800 : base?.fontWeight,
      color: textColor,
    );
  }

  @override
  bool operator ==(Object other) =>
      other is RecipeContentStyle &&
      other.size == size &&
      other.bold == bold &&
      other.color == color;

  @override
  int get hashCode => Object.hash(size, bold, color);
}

class RecipeContentStyleRange {
  const RecipeContentStyleRange({
    required this.start,
    required this.end,
    required this.style,
  });

  final int start;
  final int end;
  final RecipeContentStyle style;

  factory RecipeContentStyleRange.fromJson(Object? value) {
    if (value is! Map) {
      return const RecipeContentStyleRange(
        start: 0,
        end: 0,
        style: RecipeContentStyle(),
      );
    }
    final map = Map<String, dynamic>.from(value);
    return RecipeContentStyleRange(
      start: ((map['start'] ?? map['s']) as num?)?.toInt() ?? 0,
      end: ((map['end'] ?? map['e']) as num?)?.toInt() ?? 0,
      style: RecipeContentStyle.fromJson(map),
    );
  }

  Map<String, dynamic> toJson() => <String, dynamic>{
        's': start,
        'e': end,
        ...style.toJson(),
      };
}

typedef RecipeContentStyleRanges = Map<String, List<RecipeContentStyleRange>>;

RecipeContentStyleRanges decodeRecipeContentStyles(
  Object? value, {
  Map<String, int> legacyFieldLengths = const <String, int>{},
}) {
  if (value is! Map) return <String, List<RecipeContentStyleRange>>{};
  final decoded = <String, List<RecipeContentStyleRange>>{};
  for (final entry in Map<String, dynamic>.from(value).entries) {
    final raw = entry.value;
    if (raw is List) {
      final ranges = raw
          .map(RecipeContentStyleRange.fromJson)
          .where((range) => range.end > range.start && !range.style.isDefault)
          .toList(growable: false);
      if (ranges.isNotEmpty) decoded[entry.key] = ranges;
      continue;
    }

    // Version 48 이전의 입력란 전체 서식도 그대로 읽을 수 있게 유지합니다.
    final style = RecipeContentStyle.fromJson(raw);
    final length = legacyFieldLengths[entry.key] ?? 0;
    if (!style.isDefault && length > 0) {
      decoded[entry.key] = <RecipeContentStyleRange>[
        RecipeContentStyleRange(start: 0, end: length, style: style),
      ];
    }
  }
  return decoded;
}

Map<String, dynamic> encodeRecipeContentStyles(
  RecipeContentStyleRanges styles,
) {
  final encoded = <String, List<Map<String, dynamic>>>{};
  for (final entry in styles.entries) {
    final ranges = entry.value
        .where((range) => range.end > range.start && !range.style.isDefault)
        .map((range) => range.toJson())
        .toList();
    if (ranges.isNotEmpty) encoded[entry.key] = ranges;
  }

  // 데이터베이스 제한 안에서 정상 저장되도록 가장 뒤쪽의 세부 구간부터 줄입니다.
  while (utf8.encode(jsonEncode(encoded)).length > 3800 &&
      encoded.values.any((ranges) => ranges.isNotEmpty)) {
    final longest = encoded.entries.reduce(
      (left, right) => left.value.length >= right.value.length ? left : right,
    );
    longest.value.removeLast();
    if (longest.value.isEmpty) encoded.remove(longest.key);
  }
  return encoded;
}

List<RecipeContentStyleRange> styleRangesForSlice(
  List<RecipeContentStyleRange> ranges,
  int start,
  int end, {
  int outputOffset = 0,
}) {
  if (end <= start) return const <RecipeContentStyleRange>[];
  final result = <RecipeContentStyleRange>[];
  for (final range in ranges) {
    final overlapStart = range.start.clamp(start, end);
    final overlapEnd = range.end.clamp(start, end);
    if (overlapEnd <= overlapStart) continue;
    result.add(RecipeContentStyleRange(
      start: outputOffset + overlapStart - start,
      end: outputOffset + overlapEnd - start,
      style: range.style,
    ));
  }
  return result;
}

TextSpan buildRecipeStyledTextSpan({
  required BuildContext context,
  required String text,
  required List<RecipeContentStyleRange> ranges,
  required TextStyle? baseStyle,
}) {
  if (text.isEmpty || ranges.isEmpty) {
    return TextSpan(text: text, style: baseStyle);
  }
  final boundaries = <int>{0, text.length};
  for (final range in ranges) {
    boundaries
      ..add(range.start.clamp(0, text.length))
      ..add(range.end.clamp(0, text.length));
  }
  final points = boundaries.toList()..sort();
  final children = <InlineSpan>[];
  for (var index = 0; index < points.length - 1; index++) {
    final start = points[index];
    final end = points[index + 1];
    if (end <= start) continue;
    final matching = ranges.where(
      (range) => range.start <= start && range.end >= end,
    );
    final rangeStyle = matching.isEmpty ? null : matching.last.style;
    children.add(TextSpan(
      text: text.substring(start, end),
      style: rangeStyle?.apply(context, baseStyle) ?? baseStyle,
    ));
  }
  return TextSpan(style: baseStyle, children: children);
}
