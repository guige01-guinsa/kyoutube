import 'spanish_ui_translations.dart';

class _Template {
  _Template(this.pattern, this.translation, this.slots);
  final RegExp pattern;
  final String translation;
  final List<String> slots;
}

final _slot = RegExp(r'\{\d+\}');
List<_Template>? _templates;
final _cache = <String, String>{};

/// Full catalog phrases and explicit placeholders only. Do not run word-by-word
/// replacement over names, original recipe content or other user-entered data.
String translateSpanish(String source) {
  final exact = spanishUiTranslations[source];
  if (exact != null) return exact;
  if (_cache.containsKey(source)) return _cache[source]!;
  final templates = _templates ??= () {
    final entries = spanishUiTranslations.entries
        .where((e) => _slot.hasMatch(e.key))
        .toList()
      ..sort((a, b) => _slot
          .allMatches(b.key)
          .fold(b.key.length, (n, m) => n - m[0]!.length)
          .compareTo(_slot
              .allMatches(a.key)
              .fold(a.key.length, (n, m) => n - m[0]!.length)));
    return entries.map((e) {
      final slots = <String>[];
      var offset = 0;
      final expression = StringBuffer('^');
      for (final match in _slot.allMatches(e.key)) {
        expression.write(RegExp.escape(e.key.substring(offset, match.start)));
        expression.write('(.*?)');
        slots.add(match[0]!);
        offset = match.end;
      }
      expression.write(RegExp.escape(e.key.substring(offset)));
      expression.write(r'$');
      return _Template(
          RegExp(expression.toString(), dotAll: true), e.value, slots);
    }).toList();
  }();
  var result = source;
  for (final template in templates) {
    final match = template.pattern.firstMatch(source);
    if (match == null) continue;
    // One pass prevents a user value containing {1} from becoming a placeholder.
    result = template.translation.replaceAllMapped(_slot, (m) {
      final index = template.slots.indexOf(m[0]!);
      return index < 0 ? m[0]! : match[index + 1]!;
    });
    break;
  }
  if (result == source && source.contains('\n')) {
    result = source.split('\n').map(translateSpanish).join('\n');
  }
  if (_cache.length >= 512) _cache.clear();
  _cache[source] = result;
  return result;
}
