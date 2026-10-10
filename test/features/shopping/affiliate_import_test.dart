import 'dart:io';
import 'package:archive/archive.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:k_youtube/features/shopping/domain/affiliate_import.dart';
import 'package:k_youtube/features/shopping/domain/shopping_affiliate.dart';

void main() {
  test('both preview paths accept leading blanks and simple pipe lists', () {
    for (final parse in [AffiliateImport.text, AffiliateImport.quick]) {
      final table = parse(
          '\n\n관리 번호\t상품 명\t제휴 링크\n001\t양파\thttps://link.coupang.com/a/Onion\n');
      expect(table.single.error, isNull);
      expect(table.single.data['source_code'], '001');
      final simple = parse('양파 | https://link.coupang.com/a/Onion');
      expect(simple.single.error, isNull);
      expect(simple.single.data['title'], '양파');
      expect(() => parse('  \n'), throwsFormatException);
    }
  });
  test('the supplied UTF8 file parses through file and pasted table paths', () {
    final file = File('쿠팡제휴목록_UTF8.csv');
    if (!file.existsSync()) return; // Private operator file is not committed.
    final rows = AffiliateImport.file(file.path, file.readAsBytesSync());
    final pasted = AffiliateImport.quick(file.readAsStringSync());
    expect(rows.length, greaterThanOrEqualTo(101));
    expect(rows.map((r) => r.data['link']), pasted.map((r) => r.data['link']));
    expect(rows.take(101).where((r) => r.error != null), isEmpty);
  });
  test('blank ingredient cells use product titles without losing pack text',
      () {
    final rows = AffiliateImport.text('관리번호,분류,상품명,규격,브랜드,재료,제휴 링크\n'
        '1,기본 양념·기름,진간장,"500ml,900ml,1.8L,13L",삼화식품,간장,https://link.coupang.com/a/ONE\n'
        '2,기본 양념·기름,고추장,,,,https://link.coupang.com/a/TWO\n'
        '3,,다진마늘,,,,https://link.coupang.com/a/THREE\n'
        '4,,,,,,https://link.coupang.com/a/FOUR\n');
    expect(rows.map((r) => r.error), [null, null, null, 'invalid']);
    expect(rows[0].data['specification'], '500ml,900ml,1.8L,13L');
    expect(rows[0].data['ingredients'], ['간장']);
    expect(rows[1].data['ingredients'], ['고추장']);
    expect(rows[2].data['ingredients'], ['다진마늘']);
    expect(rows[2].data['category'], isNotEmpty);
    expect(rows[1].data['link'], 'https://link.coupang.com/a/TWO');
  });
  test('spreadsheet headers work in quick preview with 2000 sparse rows', () {
    for (final delimiter in [',', '\t']) {
      final input = [
        ['관리번호', '분류', '상품명', '규격', '브랜드', '재료', '제휴 링크'].join(delimiter),
        ...List.generate(
            2000,
            (i) => [
                  '$i',
                  '',
                  '상품$i',
                  '',
                  '',
                  '',
                  'https://link.coupang.com/a/P$i'
                ].join(delimiter)),
      ].join('\n');
      final rows = AffiliateImport.quick(input);
      expect(rows, hasLength(2000));
      expect(rows.where((r) => r.error != null), isEmpty);
      expect(rows.last.data['ingredients'], ['상품1999']);
    }
  });
  test('non UTF-8 CSV returns an actionable encoding error', () {
    expect(
        () => AffiliateImport.file('catalog.csv', [0xb0, 0xa1]),
        throwsA(isA<FormatException>()
            .having((e) => e.message, 'message', 'encoding')));
  });
  test('issued Coupang URL is preserved and lookalikes rejected', () {
    const link = 'https://link.coupang.com/a/AbC123';
    expect(affiliateUri('coupang', link).toString(), link);
    for (final invalid in [
      '$link?x=y',
      '$link#foo',
      'http://link.coupang.com/a/AbC123',
      'https://link.coupang.com.evil/a/AbC123',
      'https://coupang.com/vp/products/123',
      'https://link.coupang.com:443/a/AbC123',
      '$link\n'
    ]) {
      expect(affiliateUri('coupang', invalid), isNull, reason: invalid);
    }
  });
  test('real source and normalized CSV preserve all 100 links', () {
    final raw = AffiliateImport.text(
        File('tools/data/affiliate-catalog/initial-100-source.txt')
            .readAsStringSync());
    final csv = AffiliateImport.text(
        File('tools/data/affiliate-catalog/initial-100-drafts.csv')
            .readAsStringSync());
    expect(raw.length, 100);
    expect(csv.length, 100);
    expect(raw.where((r) => r.error != null), isEmpty);
    expect(csv.where((r) => r.error != null), isEmpty);
    expect(raw.map((r) => r.data['link']).toList(),
        csv.map((r) => r.data['link']).toList());
    expect(raw[3].data['title'], '고추장');
    expect(raw[3].data['category'], '기본 양념·기름');
  });
  test('quoted CSV BOM aliases and invalid rows remain reviewable', () {
    final rows = AffiliateImport.text(
        '\uFEFF상품명,규격,재료,제휴 링크\r\n"진간장, 대용량",1L,"간장,진간장",https://link.coupang.com/a/ONE\r\n두번째,1L,간장,https://link.coupang.com/a/ONE\r\n잘못된주소,1L,간장,javascript:x');
    expect(rows[0].data['title'], '진간장, 대용량');
    expect(rows[0].data['ingredients'], ['간장', '진간장']);
    expect(rows.map((r) => r.error), [null, 'duplicate', 'invalid']);
  });
  test('quick paste creates reviewable rows without a CSV file', () {
    final rows = AffiliateImport.quick('''
진간장 | 오뚜기 진간장 1L | https://link.coupang.com/a/QUICK1
국수소면 | https://link.coupang.com/a/QUICK2
101 | 배추김치 | 종가집 포기김치 1kg | https://link.coupang.com/a/QUICK3
''');
    expect(rows, hasLength(3));
    expect(rows.where((row) => row.error != null), isEmpty);
    expect(rows[0].data['title'], '오뚜기 진간장 1L');
    expect(rows[0].data['ingredients'], ['진간장']);
    expect(rows[1].data['title'], '국수소면');
    expect(rows[1].data['ingredients'], ['국수소면']);
    expect(rows[2].data['source_code'], '101');
    expect(rows[2].data['ingredients'], ['배추김치']);
    expect(rows[0].data['category'], '장류·소스·오일 > 장류·소스');
  });
  test('quick paste accepts marketplace category paths with or without codes',
      () {
    final rows = AffiliateImport.quick('''
장류·소스·오일 > 장류·소스 | 진간장 | 오뚜기 진간장 1L | https://link.coupang.com/a/CAT1
002 | 쌀·잡곡·면·가루 > 면·파스타 | 소면 | 오뚜기 소면 900g | https://link.coupang.com/a/CAT2
''');
    expect(rows.where((row) => row.error != null), isEmpty);
    expect(rows[0].data['category'], '장류·소스·오일 > 장류·소스');
    expect(rows[0].data['ingredients'], ['진간장']);
    expect(rows[1].data['source_code'], '002');
    expect(rows[1].data['category'], '쌀·잡곡·면·가루 > 면·파스타');
  });
  test('quick paste accepts two thousand rows and retains the hard limit', () {
    String input(int count) =>
        List.generate(count, (i) => '상품$i | https://link.coupang.com/a/QUICK$i')
            .join('\n');
    expect(AffiliateImport.quick(input(AffiliateImport.maxRows)),
        hasLength(AffiliateImport.maxRows));
    expect(() => AffiliateImport.quick(input(AffiliateImport.maxRows + 1)),
        throwsFormatException);
  });
  test('size duplicate headers row limits malformed CSV rejected', () {
    expect(() => AffiliateImport.text('title,title,link\na,b,c'),
        throwsFormatException);
    expect(() => AffiliateImport.text('title,link\n"abc,x'),
        throwsFormatException);
    expect(
        () => AffiliateImport.text(
            'title,link\n${List.filled(AffiliateImport.maxRows + 1, 'x,https://link.coupang.com/a/X').join('\n')}'),
        throwsFormatException);
    expect(
        () => AffiliateImport.file(
            'x.txt', List.filled(AffiliateImport.maxBytes + 1, 65)),
        throwsFormatException);
  });
  test('Excel first worksheet sparse cells and formula rejection', () {
    final zip = Archive()
      ..add(ArchiveFile.string('xl/workbook.xml',
          '<workbook xmlns:r="rel"><sheets><sheet r:id="s1"/></sheets></workbook>'))
      ..add(ArchiveFile.string('xl/_rels/workbook.xml.rels',
          '<Relationships><Relationship Id="s1" Target="worksheets/sheet2.xml"/></Relationships>'))
      ..add(ArchiveFile.string(
          'xl/sharedStrings.xml', '<sst><si><t>진간장</t></si></sst>'))
      ..add(ArchiveFile.string(
          'xl/worksheets/sheet2.xml', '''<worksheet><sheetData>
<row><c r="A1" t="inlineStr"><is><t>title</t></is></c><c r="C1" t="inlineStr"><is><t>link</t></is></c><c r="D1" t="inlineStr"><is><t>ingredients</t></is></c><c r="E1" t="inlineStr"><is><t>category</t></is></c></row>
<row><c r="A2" t="s"><v>0</v></c><c r="C2" t="inlineStr"><is><t>https://link.coupang.com/a/X</t></is></c></row>
<row><c r="A3"><f>1+1</f><v>2</v></c><c r="C3" t="inlineStr"><is><t>https://link.coupang.com/a/Y</t></is></c></row>
</sheetData></worksheet>'''));
    final rows = AffiliateImport.file('test.xlsx', ZipEncoder().encode(zip));
    expect(rows[0].data['title'], '진간장');
    expect(rows[0].error, isNull);
    expect(rows[1].error, 'invalid');
  });
}
