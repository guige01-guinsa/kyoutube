import 'dart:convert';
import 'package:archive/archive.dart';
import 'package:xml/xml.dart';
import 'shopping_affiliate.dart';
import 'affiliate_food_categories.dart';

class AffiliateImportRow {
  AffiliateImportRow(this.line, this.data, this.error);
  final int line;
  final Map<String, dynamic> data;
  final String? error;
}

/// Parses data only: never executes spreadsheet formulas or follows URLs.
class AffiliateImport {
  static const maxBytes = 2 * 1024 * 1024;
  static const maxRows = 2000;
  static List<AffiliateImportRow> file(String name, List<int> bytes) {
    if (bytes.length > maxBytes) throw const FormatException('file_size');
    if (name.toLowerCase().endsWith('.xlsx')) return _rows(_xlsx(bytes));
    final String decoded;
    try {
      decoded = utf8.decode(bytes);
    } on FormatException {
      throw const FormatException('encoding');
    }
    // Older Korean spreadsheet programs often export CP949 CSV. Dart can
    // replace malformed bytes instead of throwing, which otherwise makes the
    // header look like an unrelated column-layout error.
    if (decoded.contains('\uFFFD')) {
      throw const FormatException('encoding');
    }
    return text(decoded);
  }

  static List<AffiliateImportRow> text(String input) {
    if (utf8.encode(input).length > maxBytes) {
      throw const FormatException('file_size');
    }
    input = input.replaceFirst('\uFEFF', '').trim();
    if (input.isEmpty) throw const FormatException('empty');
    final first = input.split(RegExp(r'\r?\n')).first;
    final delimited = first.contains('\t') || first.contains(',');
    if (delimited) {
      final rows = _csv(input, first.contains('\t') ? '\t' : ',');
      if (rows.first.any((s) => _header(s).isNotEmpty)) {
        return _rows(rows);
      }
    }
    if (first.contains('|') || first.contains('\t')) return quick(input);
    final rows = <List<String>>[
      ['source_code', 'category', 'title', 'link'],
    ];
    for (final line in input.split(RegExp(r'\r?\n'))) {
      if (line.trim().isEmpty) continue;
      final match =
          RegExp(r'^\s*(\d+)\s+(.+?)\s+(https?://\S+)\s*$').firstMatch(line);
      if (match == null) {
        rows.add(['', '', line.trim(), '']);
      } else {
        final parts = match[2]!
            .split('\t')
            .map((e) => e.trim())
            .where((e) => e.isNotEmpty)
            .toList();
        rows.add([
          match[1]!,
          parts.length > 1 ? parts.first : '',
          parts.last.replaceFirst(RegExp(r'^★\s*'), ''),
          match[3]!
        ]);
      }
    }
    return _rows(rows);
  }

  /// Parses a lightweight paste format so an operator does not need to create
  /// a spreadsheet before importing issued affiliate links. Each non-empty
  /// line may be one of:
  ///
  /// ingredient | product title | affiliate link
  /// product title | affiliate link
  /// category | ingredient | product title | affiliate link
  /// source code | ingredient | product title | affiliate link
  /// source code | category | ingredient | product title | affiliate link
  ///
  /// Tabs can be used in place of pipes. The ingredient is stored as a search
  /// alias; when it is omitted, the product title remains the conservative
  /// alias and the row can be refined later in the editor.
  static List<AffiliateImportRow> quick(String input) {
    if (utf8.encode(input).length > maxBytes) {
      throw const FormatException('file_size');
    }
    // A pasted spreadsheet includes its header. Accept it through either
    // preview button without interpreting seven columns as the short format.
    input = input.replaceFirst('\uFEFF', '').trim();
    if (input.isEmpty) throw const FormatException('empty');
    final first = input.split(RegExp(r'\r?\n')).first;
    if (first.contains('\t') || first.contains(',')) {
      final header =
          _csv(first, first.contains('\t') ? '\t' : ',').first.map(_header);
      if (header.any((value) => value.isNotEmpty)) {
        return text(input);
      }
    }
    if (!first.contains('|') && !first.contains('\t')) return text(input);
    final rows = <List<String>>[
      [
        'source_code',
        'category',
        'title',
        'specification',
        'brand',
        'ingredients',
        'link',
      ],
    ];
    for (final source
        in input.replaceFirst('\uFEFF', '').split(RegExp(r'\r?\n'))) {
      final line = source.trim();
      if (line.isEmpty) continue;
      final separator = line.contains('|') ? '|' : '\t';
      final parts = line.split(separator).map((value) => value.trim()).toList();
      switch (parts.length) {
        case 2:
          rows.add(['', '', parts[0], '', '', parts[0], parts[1]]);
        case 3:
          rows.add(['', '', parts[1], '', '', parts[0], parts[2]]);
        case 4:
          if (RegExp(r'^\d+$').hasMatch(parts[0])) {
            rows.add([parts[0], '', parts[2], '', '', parts[1], parts[3]]);
          } else {
            rows.add(['', parts[0], parts[2], '', '', parts[1], parts[3]]);
          }
        case 5:
          rows.add([parts[0], parts[1], parts[3], '', '', parts[2], parts[4]]);
        default:
          // Keep malformed data visible in the preview instead of silently
          // skipping it. _rows marks the generated row as invalid.
          rows.add(['', '', line, '', '', '', '']);
      }
    }
    return _rows(rows);
  }

  static const _headers = <String, String>{
    'source_code': 'source_code',
    '번호': 'source_code',
    '관리번호': 'source_code',
    'category': 'category',
    '분류': 'category',
    '카테고리': 'category',
    'title': 'title',
    '상품명': 'title',
    '품목': 'title',
    '식자재': 'title',
    'link': 'link',
    'url': 'link',
    '제휴링크': 'link',
    '제휴 링크': 'link',
    'specification': 'specification',
    '규격': 'specification',
    'brand': 'brand',
    '브랜드': 'brand',
    'ingredients': 'ingredients',
    '재료': 'ingredients',
    '별칭': 'ingredients',
    'program': 'program',
    '제휴사': 'program',
  };
  static String _header(String value) =>
      _headers[value.replaceAll(RegExp(r'\s+'), '').toLowerCase()] ?? '';

  static List<AffiliateImportRow> _rows(List<List<String>> rows) {
    rows = rows.where((row) => row.any((v) => v.trim().isNotEmpty)).toList();
    if (rows.length < 2) throw const FormatException('empty');
    if (rows.length > maxRows + 1) throw const FormatException('row_limit');
    final headers = rows.first.map(_header).toList();
    if (!headers.contains('title') || !headers.contains('link')) {
      throw const FormatException('headers');
    }
    final known = headers.where((e) => e.isNotEmpty).toList();
    if (known.toSet().length != known.length) {
      throw const FormatException('headers');
    }
    final seen = <String>{};
    return [
      for (var i = 1; i < rows.length; i++)
        if (rows[i].any((v) => v.trim().isNotEmpty))
          (() {
            final data = <String, dynamic>{};
            for (var j = 0; j < headers.length; j++) {
              if (headers[j].isNotEmpty) {
                data[headers[j]] = j < rows[i].length ? rows[i][j].trim() : '';
              }
            }
            final link = data['link'] as String? ?? '';
            final program = (data['program'] as String? ?? '').isNotEmpty
                ? data['program'] as String
                : link.startsWith('https://link.coupang.com/')
                    ? 'coupang'
                    : link.contains('youtu')
                        ? 'youtube'
                        : 'naver';
            data['program'] = program;
            final title = data['title'] as String? ?? '';
            final ingredientText = data['ingredients'] as String? ?? '';
            final aliases =
                (ingredientText.trim().isEmpty ? title : ingredientText)
                    .split(RegExp(r'[,;|]'))
                    .map((s) => s.trim())
                    .where((s) => s.isNotEmpty)
                    .toSet()
                    .toList();
            data['ingredients'] = aliases;
            if ((data['category'] as String? ?? '').trim().isEmpty) {
              data['category'] = AffiliateFoodCategory.infer(
                  aliases.isEmpty ? title : aliases.first);
            }
            String? error;
            if (title.isEmpty ||
                title.length > 120 ||
                affiliateUri(program, link) == null ||
                aliases.isEmpty ||
                aliases.length > 20 ||
                aliases.any((s) => s.length > 120) ||
                ['category', 'brand', 'source_code']
                    .any((k) => (data[k] as String? ?? '').length > 80) ||
                (data['specification'] as String? ?? '').length > 160 ||
                rows[i].any((s) => s == '#FORMULA!')) {
              error = 'invalid';
            } else if (!seen.add('$program:$link')) {
              error = 'duplicate';
            }
            return AffiliateImportRow(i, data, error);
          })()
    ];
  }

  static List<List<String>> _csv(String source, String delimiter) {
    final result = <List<String>>[];
    var row = <String>[];
    var field = StringBuffer();
    var quoted = false;
    for (var i = 0; i < source.length; i++) {
      final c = source[i];
      if (c == '"') {
        if (quoted && i + 1 < source.length && source[i + 1] == '"') {
          field.write('"');
          i++;
        } else {
          quoted = !quoted;
        }
      } else if (!quoted && c == delimiter) {
        row.add(field.toString());
        field = StringBuffer();
      } else if (!quoted && (c == '\n' || c == '\r')) {
        if (c == '\r' && i + 1 < source.length && source[i + 1] == '\n') i++;
        row.add(field.toString());
        result.add(row);
        row = [];
        field = StringBuffer();
      } else {
        field.write(c);
      }
    }
    if (quoted) throw const FormatException('quotes');
    row.add(field.toString());
    if (row.any((v) => v.isNotEmpty)) result.add(row);
    return result;
  }

  static List<List<String>> _xlsx(List<int> bytes) {
    final directory = ZipDirectory()..read(InputMemoryStream(bytes));
    if (directory.fileHeaders.length > 1000 ||
        directory.fileHeaders.fold<int>(0, (n, f) => n + f.uncompressedSize) >
            20 * 1024 * 1024 ||
        directory.fileHeaders.any(
            (f) => ((f.externalFileAttributes >> 16) & 0xf000) == 0xa000)) {
      throw const FormatException('file_size');
    }
    final zip = ZipDecoder().decodeBytes(bytes);
    if (zip.length > 1000 ||
        zip.fold<int>(0, (n, f) => n + f.size) > 20 * 1024 * 1024) {
      throw const FormatException('file_size');
    }
    XmlDocument xml(String name) {
      final f = zip.findFile(name);
      if (f == null) throw const FormatException('workbook');
      return XmlDocument.parse(utf8.decode(f.content));
    }

    final workbook = xml('xl/workbook.xml');
    final sheet = workbook.findAllElements('sheet').first;
    final id = sheet.getAttribute('r:id');
    final rel = xml('xl/_rels/workbook.xml.rels')
        .findAllElements('Relationship')
        .firstWhere((e) => e.getAttribute('Id') == id);
    if (rel.getAttribute('TargetMode') == 'External') {
      throw const FormatException('workbook');
    }
    final target = rel.getAttribute('Target')!;
    final name = target.startsWith('/') ? target.substring(1) : 'xl/$target';
    final strings = zip.findFile('xl/sharedStrings.xml') == null
        ? <String>[]
        : xml('xl/sharedStrings.xml')
            .findAllElements('si')
            .map((e) => e.findAllElements('t').map((t) => t.innerText).join())
            .toList();
    final result = <List<String>>[];
    for (final row in xml(name).findAllElements('row')) {
      if (result.length >= maxRows + 1) {
        throw const FormatException('row_limit');
      }
      final values = <String>[];
      for (final cell in row.findElements('c')) {
        final coordinate = cell.getAttribute('r') ?? '';
        final letters = RegExp(r'^[A-Z]+').stringMatch(coordinate);
        if (letters == null) throw const FormatException('workbook');
        var column = 0;
        for (final c in letters.codeUnits) {
          column = column * 26 + c - 64;
        }
        if (column > 64) throw const FormatException('columns');
        while (values.length < column) {
          values.add('');
        }
        final value = cell.getElement('v')?.innerText ?? '';
        values[column - 1] = cell.getElement('f') != null
            ? '#FORMULA!'
            : switch (cell.getAttribute('t')) {
                's' => strings[int.parse(value)],
                'inlineStr' =>
                  cell.findAllElements('t').map((e) => e.innerText).join(),
                _ => value,
              };
      }
      result.add(values);
    }
    return result;
  }
}
