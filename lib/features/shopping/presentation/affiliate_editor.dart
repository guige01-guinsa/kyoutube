import '../../../core/format/user_number.dart';
import 'shopping_assistant_dialogs.dart' show ShoppingAccountGuard;
import '../../auth/presentation/account_recovery_actions.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:flutter/material.dart';
import '../../../core/widgets/scout_page.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/localization/localized_text.dart';
import '../../auth/application/auth_providers.dart';
import '../data/shopping_affiliate_repository.dart';
import '../data/shopping_assistant_repository.dart';
import '../domain/shopping_affiliate.dart';
import '../domain/coupang_purchase_plan.dart';

class AffiliateEditor extends ConsumerStatefulWidget {
  const AffiliateEditor({super.key, required this.data});
  final Map<String, dynamic> data;
  @override
  ConsumerState<AffiliateEditor> createState() => AffiliateEditorState();
}

class AffiliateEditorState extends ConsumerState<AffiliateEditor> {
  late final _title =
      TextEditingController(text: widget.data['title'] as String? ?? '');
  late final _spec = TextEditingController(
      text: widget.data['specification'] as String? ?? '');
  late final _aliases = TextEditingController(
      text: (widget.data['ingredients'] as List? ?? []).join(', '));
  late final _link =
      TextEditingController(text: widget.data['link'] as String? ?? '');
  late final _category =
      TextEditingController(text: widget.data['category'] as String? ?? '');
  late final _brand =
      TextEditingController(text: widget.data['brand'] as String? ?? '');
  late final _code =
      TextEditingController(text: widget.data['source_code'] as String? ?? '');
  late bool _verified = widget.data['product_verified'] == true;
  late final _packAmount = TextEditingController(
      text: (widget.data['purchase_pack']?['amount'] ?? '').toString());
  late final _packCount = TextEditingController(
      text: (widget.data['purchase_pack']?['units_per_order'] ?? 1).toString());
  late final _packLabel = TextEditingController(
      text: widget.data['purchase_pack']?['label'] as String? ?? '묶음');
  late final _packOption = TextEditingController(
      text: widget.data['purchase_pack']?['option'] as String? ?? '');
  late String _packUnit =
      widget.data['purchase_pack']?['unit'] as String? ?? 'g';
  late final _note =
      TextEditingController(text: widget.data['review_note'] as String? ?? '');
  late String _program = widget.data['program'] as String? ?? 'coupang';
  late bool _mobile = widget.data['mobile_allowed'] == true,
      _web = widget.data['web_allowed'] == true,
      _published = widget.data['published'] == true;
  late final String? _account;
  bool get _changedLink =>
      _base['id'] != null &&
      (_base['link'] != _link.text.trim() || _base['program'] != _program);
  late Map<String, dynamic> _base = Map.of(widget.data);
  String? _recoveryCode;
  bool _busy = false;
  String? _error;
  @override
  void initState() {
    super.initState();
    _account = ref.read(activeAccountIdProvider);
    for (final controller in [
      _title,
      _spec,
      _brand,
      _aliases,
      _packAmount,
      _packCount,
      _packLabel,
      _packOption
    ]) {
      controller.addListener(() => setState(() {
            _verified = false;
            _published = false;
          }));
    }
    _link.addListener(() {
      setState(() {
        _published = false;
        _verified = false;
        _mobile = false;
        _web = false;
        _note.clear();
      });
    });
  }

  @override
  void dispose() {
    for (final c in [
      _title,
      _spec,
      _aliases,
      _link,
      _note,
      _category,
      _brand,
      _code,
      _packAmount,
      _packCount,
      _packLabel,
      _packOption
    ]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _save() async {
    if (_busy || ref.read(activeAccountIdProvider) != _account) return;
    final pack = _program != 'coupang' || _packAmount.text.trim().isEmpty
        ? null
        : CoupangPack.parse({
            'amount': parseUserNumber(_packAmount.text.trim()),
            'unit': _packUnit,
            'units_per_order': num.tryParse(_packCount.text.trim()),
            'label': _packLabel.text.trim(),
            'option': _packOption.text.trim(),
          });
    if (_program == 'coupang' &&
        _packAmount.text.trim().isNotEmpty &&
        pack == null) {
      setState(() => _error = '판매 규격의 내용량·묶음 수·옵션명을 확인해 주세요.');
      return;
    }
    final aliases = _aliases.text
        .split(',')
        .map((s) => s.trim())
        .where((s) => s.isNotEmpty)
        .toSet()
        .toList();
    if (_title.text.trim().isEmpty ||
        _title.text.trim().length > 120 ||
        aliases.isEmpty ||
        aliases.length > 20 ||
        aliases.any((s) => s.length > 120) ||
        affiliateUri(_program, _link.text.trim()) == null ||
        (_published &&
            (!_mobile && !_web ||
                _note.text.trim().length < 10 ||
                (_program == 'coupang' &&
                    (!_verified || _spec.text.trim().isEmpty))))) {
      setState(() => _error = '링크와 입력 항목을 확인해 주세요.');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await ref.read(shoppingAffiliateRepositoryProvider).save({
        ..._base,
        'category': _category.text.trim(),
        'brand': _brand.text.trim(),
        'source_code': _code.text.trim(),
        'product_verified': _verified,
        'program': _program,
        'title': _title.text.trim(),
        'specification': _spec.text.trim(),
        'purchase_pack': pack?.toJson(),
        'ingredients': aliases,
        'link': _link.text.trim(),
        'review_note': _note.text.trim(),
        'mobile_allowed': _mobile,
        'web_allowed': _web,
        'published': _published,
        'expires_at': DateTime.now()
            .toUtc()
            .add(const Duration(days: 30))
            .toIso8601String()
      });
      if (mounted && ref.read(activeAccountIdProvider) == _account) {
        Navigator.of(context).pop();
      }
    } catch (error) {
      if (mounted) {
        _recoveryCode = error is PostgrestException ? error.message : null;
        setState(() => _error = error is PostgrestException &&
                error.message == 'AFFILIATE_DUPLICATE'
            ? '같은 제휴 링크가 등록되어 있습니다. 아래에서 기존 상품을 확인해 주세요.'
            : error is PostgrestException && error.message == 'AFFILIATE_STALE'
                ? '다른 변경 사항이 있습니다. 최신 내용과 비교한 뒤 계속할 수 있습니다.'
                : '저장하지 못했습니다. 관리자 2단계 인증·입력값을 확인하거나 새로고침 후 다시 시도하세요.');
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Widget _comparisonSummary(String heading, Map<String, dynamic> row) =>
      Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(heading, style: Theme.of(context).textTheme.titleMedium),
        for (final field in [
          ('상품명', 'title'),
          ('규격', 'specification'),
          ('브랜드', 'brand'),
          ('재료', 'ingredients'),
          ('제휴 링크', 'link'),
          ('검토 메모', 'review_note')
        ])
          LocalizedText('${context.tr(field.$1)}: ${row[field.$2] ?? ''}'),
        if (row['purchase_pack'] case final Map pack)
          LocalizedText(
              '${context.tr('판매 규격')}: ${pack['amount'] ?? ''} ${pack['unit'] ?? ''} × ${pack['units_per_order'] ?? 1} · ${pack['label'] ?? ''} ${pack['option'] ?? ''}'),
        LocalizedText(
            '${context.tr('웹 공개')}: ${context.tr(row['web_allowed'] == true ? '허용' : '숨김')} · ${context.tr('앱 공개')}: ${context.tr(row['mobile_allowed'] == true ? '허용' : '숨김')}'),
        Text(context.tr(row['published'] == true ? '공개 중' : '초안·숨김')),
        const SizedBox(height: 12),
      ]);

  Future<void> _recover() async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      final repo = ref.read(shoppingAffiliateRepositoryProvider);
      final row = await repo.recovery(
          id: _recoveryCode == 'AFFILIATE_STALE'
              ? _base['id'] as String?
              : null,
          program: _program,
          link: _link.text.trim());
      if (!mounted || ref.read(activeAccountIdProvider) != _account) return;
      if (row == null) {
        setState(() => _error = '기존 상품을 찾을 수 없습니다. 목록을 다시 확인해 주세요.');
        return;
      }
      final duplicate = _recoveryCode == 'AFFILIATE_DUPLICATE';
      final choice = await showDialog<String>(
          context: context,
          builder: (ctx) => ShoppingAccountGuard(
                  child: AlertDialog(
                      title:
                          LocalizedText(duplicate ? '등록된 상품 확인' : '변경 내용 비교'),
                      content: SingleChildScrollView(
                          child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                            _comparisonSummary(context.tr('최신 상품'), row),
                            if (row['deleted_at'] != null)
                              const LocalizedText(
                                  '휴지통에 있는 상품입니다. 복원 후 수정할 수 있습니다.'),
                            if (!duplicate)
                              _comparisonSummary(context.tr('내 입력'), {
                                'title': _title.text,
                                'specification': _spec.text,
                                'brand': _brand.text,
                                'ingredients': _aliases.text,
                                'link': _link.text,
                                'purchase_pack': {
                                  'amount': _packAmount.text,
                                  'unit': _packUnit,
                                  'units_per_order': _packCount.text,
                                  'label': _packLabel.text,
                                  'option': _packOption.text
                                },
                                'review_note': _note.text,
                                'web_allowed': _web,
                                'mobile_allowed': _mobile,
                                'published': _published,
                              }),
                          ])),
                      actions: [
                    TextButton(
                        onPressed: () => Navigator.pop(ctx),
                        child: const LocalizedText('입력 유지·돌아가기')),
                    if (!duplicate && row['deleted_at'] == null)
                      TextButton(
                          onPressed: () => Navigator.pop(ctx, 'keep'),
                          child: const LocalizedText('내 입력으로 이어서 검토')),
                    FilledButton(
                        onPressed: () => Navigator.pop(ctx, 'open'),
                        child: LocalizedText(row['deleted_at'] != null
                            ? '복원 후 편집'
                            : '최신 상품 편집')),
                  ])));
      if (!mounted ||
          ref.read(activeAccountIdProvider) != _account ||
          choice == null) {
        return;
      }
      if (choice == 'keep') {
        setState(() {
          _base = row;
          _verified = false;
          _published = false;
          _recoveryCode = null;
          _error = null;
        });
      } else {
        var latest = row;
        if (row['deleted_at'] != null) {
          await repo.change(row, 'restore');
          latest = await repo.recovery(id: row['id'] as String) ?? row;
        }
        if (!mounted || ref.read(activeAccountIdProvider) != _account) return;
        await showDialog<void>(
            context: context,
            barrierDismissible: false,
            builder: (_) =>
                ShoppingAccountGuard(child: AffiliateEditor(data: latest)));
      }
    } catch (_) {
      if (mounted) {
        setState(() => _error = '최신 상품을 확인하지 못했습니다. 연결·권한을 확인하고 다시 시도해 주세요.');
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Widget field(TextEditingController c, String label, int max) => Padding(
      padding: const EdgeInsets.only(top: 12),
      child: TextField(
          controller: c,
          enabled: !_busy,
          maxLength: max,
          minLines: 1,
          maxLines: 3,
          decoration: InputDecoration(labelText: context.tr(label))));
  @override
  Widget build(BuildContext context) => AlertDialog(
          scrollable: true,
          insetPadding: const EdgeInsets.all(16),
          title: const LocalizedText('제휴 상품 관리'),
          content: SizedBox(
              width: 520,
              child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    ScoutSectionLabel(
                        number: '01',
                        title:
                            Localizations.localeOf(context).languageCode != 'ko'
                                ? 'Product details'
                                : '상품 기본 정보'),
                    DropdownButtonFormField<String>(
                        initialValue: _program,
                        isExpanded: true,
                        items: [
                          DropdownMenuItem(
                              value: 'coupang',
                              child: Text(context.tr('쿠팡 파트너스'))),
                          DropdownMenuItem(
                              value: 'naver',
                              child: Text(context.tr('네이버 쇼핑 커넥트'))),
                          DropdownMenuItem(
                              value: 'youtube',
                              child: Text(context.tr('YouTube Shopping 영상'))),
                        ],
                        onChanged: _busy
                            ? null
                            : (v) => setState(() {
                                  _program = v!;
                                  _published = false;
                                  _verified = false;
                                  _mobile = false;
                                  _web = false;
                                  _note.clear();
                                })),
                    field(_title, '상품명', 120),
                    field(_category, '식자재 분류', 80),
                    field(_brand, '상품 브랜드', 80),
                    field(_code, '관리 번호', 80),
                    field(_spec, '규격·브랜드', 160),
                    if (_program == 'coupang') ...[
                      const LocalizedText('구매량 자동 계산용 판매 규격 (선택)'),
                      const LocalizedText(
                          '예: 500g × 2봉 상품은 내용량 500, 단위 g, 묶음 수 2입니다. 실제 판매 옵션을 확인하세요.'),
                      field(_packAmount, '개별 포장 내용량 (비우면 자동 계산 안 함)', 20),
                      DropdownButtonFormField<String>(
                          initialValue: _packUnit,
                          decoration:
                              InputDecoration(labelText: context.tr('내용량 단위')),
                          items: [
                            for (final u in ['g', 'kg', 'ml', 'l', 'ea'])
                              DropdownMenuItem(
                                  value: u,
                                  child: Text(u == 'ea' ? context.tr('개') : u))
                          ],
                          onChanged: _busy
                              ? null
                              : (v) => setState(() {
                                    _packUnit = v!;
                                    _verified = false;
                                    _published = false;
                                  })),
                      field(_packCount, '한 번 주문에 포함된 포장 수', 8),
                      field(_packLabel, '판매 단위 이름 (봉·병·묶음 등)', 30),
                      field(_packOption, '확인한 판매 옵션명', 160),
                    ],
                    field(_aliases, '재료 이름·별칭 (쉼표로 구분)', 2400),
                    ScoutSectionLabel(
                        number: '02',
                        title:
                            Localizations.localeOf(context).languageCode != 'ko'
                                ? 'Link and product verification'
                                : '링크와 실제 상품 확인'),
                    field(_link, '제휴 링크 또는 상품 태그 영상 주소', 2048),
                    field(_note, '사용 허용 근거·확인일', 2000),
                    TextButton.icon(
                        onPressed: _busy ||
                                affiliateUri(_program, _link.text.trim()) ==
                                    null
                            ? null
                            : () async {
                                try {
                                  if (await ref
                                          .read(shoppingLinkLauncherProvider)(
                                      affiliateUri(
                                          _program, _link.text.trim())!)) {
                                    return;
                                  }
                                } catch (_) {/* Display retry message below. */}
                                if (mounted) {
                                  setState(() =>
                                      _error = '주소를 열지 못했습니다. 다시 시도해 주세요.');
                                }
                              },
                        icon: const Icon(Icons.open_in_new),
                        label: const LocalizedText('실제 상품 확인')),
                    CheckboxListTile(
                        contentPadding: EdgeInsets.zero,
                        title: const LocalizedText('연결된 상품과 규격을 직접 확인했습니다.'),
                        value: _verified,
                        onChanged: _busy
                            ? null
                            : (v) => setState(() => _verified = v!)),
                    ScoutSectionLabel(
                        number: '03',
                        title:
                            Localizations.localeOf(context).languageCode != 'ko'
                                ? 'Publication settings'
                                : '공개 설정'),
                    const LocalizedText(
                        '승인된 게시 위치와 근거가 있어야 공개할 수 있습니다. 저장할 때마다 30일 후 재확인하도록 설정됩니다.'),
                    CheckboxListTile(
                        contentPadding: EdgeInsets.zero,
                        title: const LocalizedText('모바일 앱 게시 가능 확인'),
                        value: _mobile,
                        onChanged:
                            _busy ? null : (v) => setState(() => _mobile = v!)),
                    CheckboxListTile(
                        contentPadding: EdgeInsets.zero,
                        title: const LocalizedText('웹 게시 가능 확인'),
                        value: _web,
                        onChanged:
                            _busy ? null : (v) => setState(() => _web = v!)),
                    if (_changedLink)
                      const LocalizedText(
                          '제휴 링크를 변경하면 초안으로 저장됩니다. 저장 후 다시 열어 검토·공개해 주세요.'),
                    SwitchListTile(
                        contentPadding: EdgeInsets.zero,
                        title: const LocalizedText('공개 중'),
                        value: _published,
                        onChanged: _busy || _changedLink
                            ? null
                            : (v) => setState(() => _published = v)),
                    if (_error != null) LocalizedText(_error!),
                    if (['AFFILIATE_DUPLICATE', 'AFFILIATE_STALE']
                        .contains(_recoveryCode))
                      TextButton(
                          onPressed: _busy ? null : _recover,
                          child: LocalizedText(
                              _recoveryCode == 'AFFILIATE_DUPLICATE'
                                  ? '기존 상품 확인'
                                  : '최신 내용과 비교')),
                    if (_error != null &&
                        !['AFFILIATE_DUPLICATE', 'AFFILIATE_STALE']
                            .contains(_recoveryCode))
                      AccountRecoveryActions(
                          onRecovered: () => setState(() => _error = null)),
                    if (_busy) const LinearProgressIndicator(),
                  ])),
          actions: [
            TextButton(
                onPressed: _busy ? null : () => Navigator.of(context).pop(),
                child: const LocalizedText('취소')),
            FilledButton(
                onPressed: _busy ? null : _save,
                child: const LocalizedText('저장'))
          ]);
}
