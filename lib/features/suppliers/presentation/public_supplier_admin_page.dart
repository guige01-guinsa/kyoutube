import '../../../core/localization/localized_text.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../auth/application/auth_providers.dart';
import '../../membership/application/membership_providers.dart';
import '../data/public_supplier_repository.dart';
import '../domain/public_supplier.dart';
import '../domain/supplier_catalog.dart';
import '../../shopping/domain/shopping_assistant.dart';
import 'public_supplier_card.dart';
import 'supplier_business_page.dart';

class PublicSupplierAdminPage extends ConsumerWidget {
  const PublicSupplierAdminPage({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final membership = ref.watch(membershipInfoProvider);
    final owner = ref.watch(activeAccountIdProvider);
    if (owner != null && membership.valueOrNull?.isAdmin == true) {
      return _AdminDirectory(key: ValueKey(owner));
    }
    return Scaffold(
        appBar: AppBar(
            title: Text(catalogText(
                context, '공개 업체 자료 관리', 'Manage public supplier listings'))),
        body: Center(
            child: membership.isLoading
                ? const CircularProgressIndicator()
                : Text(catalogText(context, '관리자 로그인과 2단계 인증이 필요합니다.',
                    'Administrator sign-in and two-factor authentication are required.'))));
  }
}

class _AdminDirectory extends ConsumerStatefulWidget {
  const _AdminDirectory({super.key});
  @override
  ConsumerState<_AdminDirectory> createState() => _AdminDirectoryState();
}

class _AdminDirectoryState extends ConsumerState<_AdminDirectory> {
  final _query = TextEditingController();
  List<PublicSupplier> _rows = [];
  final _selected = <String>{};
  bool _busy = false, _more = false;
  String _mode = 'candidate';
  String? _error;
  String t(String ko, String en) => catalogText(context, ko, en);
  @override
  void initState() {
    super.initState();
    _search();
  }

  @override
  void dispose() {
    _query.dispose();
    super.dispose();
  }

  String errorText(Object e) {
    final code = e is PostgrestException ? e.code : '';
    final details = e is PostgrestException
        ? e.message
        : e is FunctionException
            ? '${e.details}'
            : '';
    if (code == '23505') {
      return t('같은 홈페이지의 업체가 이미 있습니다. 저장된 업체를 검색해 수정해 주세요.',
          'This website already has a listing. Search saved listings to update it.');
    }
    if (details.contains('CONFLICT')) {
      return t('다른 작업에서 변경된 정보입니다. 다시 검색한 뒤 확인해 주세요.',
          'This listing changed elsewhere. Search again to review the latest version.');
    }
    if (details.contains('QUOTA') || details.contains('search_quota')) {
      return t('검색 횟수 제한에 도달했습니다. 잠시 후 또는 내일 다시 이용해 주세요.',
          'Search limit reached. Try again shortly or tomorrow.');
    }
    if (details.contains('SOURCE_REVIEW') ||
        details.contains('INVALID_CHECK_DATE')) {
      return t('출처와 확인일을 다시 검토해 주세요. 공개하려면 최근 90일 이내 확인한 자료가 필요합니다.',
          'Review sources and the check date. Publishing requires a review within the last 90 days.');
    }
    return t('작업을 완료하지 못했습니다. 관리자 인증·입력 항목·연결 상태를 확인해 주세요.',
        'Could not complete the action. Check admin authentication, fields and connection.');
  }

  Future<void> _search({bool more = false}) async {
    if (_busy) return;
    if (_mode == 'web' && _query.text.trim().length < 2) {
      setState(() => _error = t(
          '검색어를 두 글자 이상 입력해 주세요.', 'Enter at least two characters to search.'));
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
      if (!more) _selected.clear();
    });
    try {
      final repo = ref.read(publicSupplierAdminRepositoryProvider);
      final rows = _mode == 'web'
          ? await repo.discover(_query.text.trim())
          : await repo.search(_query.text.trim(), _mode,
              offset: more ? _rows.length : 0);
      if (mounted) {
        setState(() {
          _rows = more ? [..._rows, ...rows] : rows;
          _more = _mode != 'web' && rows.length == 30;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _error = errorText(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _edit(PublicSupplier original) async {
    final updated = await showDialog<PublicSupplier>(
        context: context,
        barrierDismissible: false,
        builder: (_) => PublicSupplierEditDialog(supplier: original));
    if (updated == null || !mounted) return;
    // New search results stay local until the operator explicitly saves them.
    if (_mode == 'web' &&
        original.revision == 0 &&
        _rows.any((r) => r.id == original.id)) {
      setState(() =>
          _rows = _rows.map((r) => r.id == original.id ? updated : r).toList());
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await ref
          .read(publicSupplierAdminRepositoryProvider)
          .save(updated, confirmed: updated.status == 'published');
      if (mounted) {
        setState(() {
          _busy = false;
          if (_mode == 'web') {
            _mode = updated.status;
            _query.clear();
          }
        });
        await _search();
      }
    } catch (e) {
      if (mounted) setState(() => _error = errorText(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _publish() async {
    final rows = _rows.where((r) => _selected.contains(r.id)).toList();
    if (rows.isEmpty || _busy) return;
    if (rows.any((r) => r.deliveryRegions.isEmpty)) {
      setState(() => _error = t('배송 지역이 미확인인 업체가 있습니다. 출처를 확인한 후 수정해 주세요.',
          'Some delivery areas are unconfirmed. Review the sources and edit these listings.'));
      return;
    }
    bool confirmed = false;
    final yes = await showDialog<bool>(
        context: context,
        builder: (context) => StatefulBuilder(
            builder: (context, setDialog) => AlertDialog(
                    title:
                        Text(t('선택한 업체 공개 저장', 'Publish selected suppliers')),
                    content: SizedBox(
                        width: 560,
                        child: SingleChildScrollView(
                            child: Column(
                                mainAxisSize: MainAxisSize.min,
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                              Text(t('로그인한 모든 회원에게 아래 정보가 공개됩니다.',
                                  'The following information will be visible to all signed-in members.')),
                              for (final r in rows)
                                PublicSupplierCard(supplier: r),
                              CheckboxListTile(
                                  contentPadding: EdgeInsets.zero,
                                  value: confirmed,
                                  title: Text(t(
                                      '모든 선택 업체의 공식 출처·취급 품목·배송 조건을 확인했습니다.',
                                      'I reviewed the official sources, products and delivery terms for every selected supplier.')),
                                  onChanged: (v) =>
                                      setDialog(() => confirmed = v ?? false)),
                            ]))),
                    actions: [
                      TextButton(
                          onPressed: () => Navigator.pop(context, false),
                          child: Text(t('취소', 'Cancel'))),
                      FilledButton(
                          onPressed: confirmed
                              ? () => Navigator.pop(context, true)
                              : null,
                          child: Text(t('공개 저장', 'Publish')))
                    ])));
    if (yes != true || !mounted) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await ref.read(publicSupplierAdminRepositoryProvider).publish(rows);
      if (mounted) {
        setState(() {
          _busy = false;
          _mode = 'published';
          _query.clear();
          _selected.clear();
        });
        await _search();
      }
    } catch (e) {
      if (mounted) setState(() => _error = errorText(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
        appBar: AppBar(
            title: Text(t('공개 업체 자료 관리', 'Manage public supplier listings'))),
        bottomNavigationBar: _selected.isEmpty
            ? null
            : SafeArea(
                child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: FilledButton.icon(
                        onPressed: _busy ? null : _publish,
                        icon: const Icon(Icons.publish),
                        label: LocalizedText(
                            '${t('선택한 업체 공개 저장', 'Publish selected suppliers')} · ${_selected.length}')))),
        body: Center(
            child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 1000),
                child: ListView(padding: const EdgeInsets.all(20), children: [
                  Text(t('찾고, 확인하고, 공개하세요', 'Find, review, publish'),
                      style: Theme.of(context).textTheme.headlineSmall),
                  const SizedBox(height: 8),
                  Text(t(
                      '인터넷 검색 → 업체 선택 → 정보·출처 확인 → 공개 저장. 저장 전까지 검색 결과는 회원에게 보이지 않습니다.',
                      'Search online → select suppliers → review details and sources → publish. Search results stay private until saved.')),
                  const SizedBox(height: 16),
                  Wrap(spacing: 8, runSpacing: 8, children: [
                    for (final item in <String, String>{
                      'web': t('인터넷 검색', 'Search the web'),
                      'candidate': t('저장한 후보', 'Saved candidates'),
                      'published': t('공개 중', 'Published'),
                      'hidden': t('비공개', 'Hidden')
                    }.entries)
                      ChoiceChip(
                          label: Text(item.value),
                          selected: _mode == item.key,
                          onSelected: _busy
                              ? null
                              : (v) {
                                  if (v) {
                                    setState(() {
                                      _mode = item.key;
                                      _rows = [];
                                      _selected.clear();
                                      _error = null;
                                      _more = false;
                                    });
                                    if (_mode != 'web') _search();
                                  }
                                })
                  ]),
                  const SizedBox(height: 16),
                  TextField(
                      controller: _query,
                      maxLength: 120,
                      onSubmitted: (_) => _search(),
                      decoration: InputDecoration(
                          labelText: t('업체·품목·지역 검색',
                              'Search business, product or region'),
                          hintText: t('예: 전국 배송 수산물 도매',
                              'e.g. seafood wholesale nationwide delivery'),
                          suffixIcon: IconButton(
                              onPressed: _busy ? null : () => _search(),
                              icon: const Icon(Icons.search)))),
                  if (_mode == 'web')
                    Text(t(
                        '관리자별 하루 20회 · 전체 하루 50회 · 검색 간격 20초. 한 번에 최대 5곳을 조사합니다.',
                        '20 searches per admin/day, 50 total/day, 20 seconds apart. Up to 5 suppliers per search.')),
                  Align(
                      alignment: Alignment.centerLeft,
                      child: TextButton.icon(
                          onPressed: _busy
                              ? null
                              : () => _edit(const PublicSupplier()),
                          icon: const Icon(Icons.add),
                          label: Text(
                              t('직접 조사한 업체 추가', 'Add a researched supplier')))),
                  if (_busy) const LinearProgressIndicator(),
                  if (_error != null)
                    Padding(
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        child: Text(_error!,
                            style: TextStyle(
                                color: Theme.of(context).colorScheme.error))),
                  if (!_busy && _rows.isEmpty)
                    Padding(
                        padding: const EdgeInsets.all(24),
                        child: Text(t('표시할 업체가 없습니다. 검색하거나 새 후보를 추가하세요.',
                            'No suppliers to display. Search or add a new candidate.'))),
                  for (final row in _rows)
                    Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          CheckboxListTile(
                              key: ValueKey('select-${row.id}'),
                              contentPadding: EdgeInsets.zero,
                              title: Text(row.name),
                              subtitle: LocalizedText(row.revision == 0
                                  ? t('저장 전 검색 결과', 'Unsaved search result')
                                  : '${t('기존 등록 업체', 'Saved supplier')} · ${t('확인일', 'Checked')}: ${row.checkedOn}'),
                              value: _selected.contains(row.id),
                              onChanged: _busy ||
                                      (_mode == 'web' &&
                                          row.status == 'published' &&
                                          row.revision > 0)
                                  ? null
                                  : (v) => setState(() {
                                        if (v == true) {
                                          if (_selected.length < 20) {
                                            _selected.add(row.id);
                                          }
                                        } else {
                                          _selected.remove(row.id);
                                        }
                                      })),
                          PublicSupplierCard(
                              supplier: row,
                              action: TextButton.icon(
                                  onPressed: _busy ? null : () => _edit(row),
                                  icon: const Icon(Icons.edit_outlined),
                                  label:
                                      Text(t('정보 확인·수정', 'Review and edit')))),
                        ]),
                  if (_more)
                    TextButton(
                        onPressed: _busy ? null : () => _search(more: true),
                        child: Text(t('더 보기', 'Load more'))),
                ]))));
  }
}

class PublicSupplierEditDialog extends StatefulWidget {
  const PublicSupplierEditDialog({super.key, required this.supplier});
  final PublicSupplier supplier;
  @override
  State<PublicSupplierEditDialog> createState() =>
      _PublicSupplierEditDialogState();
}

class _PublicSupplierEditDialogState extends State<PublicSupplierEditDialog> {
  final _form = GlobalKey<FormState>();
  late final _name = TextEditingController(text: widget.supplier.name);
  late final _website = TextEditingController(text: widget.supplier.website);
  late final _phone = TextEditingController(text: widget.supplier.phone);
  late final _products = TextEditingController(text: widget.supplier.products);
  late final _shipping =
      TextEditingController(text: widget.supplier.shippingNote);
  late final _sources =
      TextEditingController(text: widget.supplier.sourceUrls.join('\n'));
  late final _date = TextEditingController(
      text: widget.supplier.checkedOn.isEmpty
          ? DateTime.now().toIso8601String().substring(0, 10)
          : widget.supplier.checkedOn);
  late final _categories = widget.supplier.categories.toSet();
  late final _regions = widget.supplier.deliveryRegions.toSet();
  late String _kind = widget.supplier.businessKind,
      _status = widget.supplier.status;
  bool _confirmed = false, _missing = false;
  String t(String ko, String en) => catalogText(context, ko, en);
  @override
  void dispose() {
    for (final c in [
      _name,
      _website,
      _phone,
      _products,
      _shipping,
      _sources,
      _date
    ]) {
      c.dispose();
    }
    super.dispose();
  }

  Widget field(TextEditingController c, String ko, String en, int max,
          {bool required = true, bool url = false, int lines = 1}) =>
      Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: TextFormField(
              controller: c,
              maxLength: max,
              minLines: lines,
              maxLines: lines + 2,
              decoration: InputDecoration(labelText: t(ko, en)),
              validator: (v) {
                if (required && (v ?? '').trim().isEmpty) {
                  return t('필수 항목입니다.', 'This field is required.');
                }
                if (url && shoppingProductUri((v ?? '').trim()) == null) {
                  return t('https 공식 주소를 입력해 주세요.',
                      'Enter an official HTTPS address.');
                }
                return null;
              }));
  void save() {
    final valid = _form.currentState!.validate();
    final urls = _sources.text
        .split('\n')
        .map((s) => s.trim())
        .where((s) => s.isNotEmpty)
        .toList();
    final date = DateTime.tryParse(_date.text.trim());
    final now = DateTime.now();
    final dateValid =
        RegExp(r'^\d{4}-\d{2}-\d{2}$').hasMatch(_date.text.trim()) &&
            date != null &&
            date.toIso8601String().substring(0, 10) == _date.text.trim() &&
            !date.isAfter(DateTime(now.year, now.month, now.day)) &&
            date.year >= 2020;
    if (!valid ||
        _categories.isEmpty ||
        _regions.isEmpty ||
        urls.isEmpty ||
        urls.length > 5 ||
        urls.any((u) => shoppingProductUri(u) == null) ||
        !dateValid ||
        (_status == 'published' && !_confirmed)) {
      setState(() => _missing = true);
      return;
    }
    Navigator.pop(
        context,
        PublicSupplier(
            id: widget.supplier.id,
            name: _name.text.trim(),
            website: _website.text.trim(),
            phone: _phone.text.trim(),
            products: _products.text.trim(),
            categories: _categories.toList(),
            deliveryRegions: _regions.toList(),
            shippingNote: _shipping.text.trim(),
            businessKind: _kind,
            sourceUrls: urls,
            checkedOn: _date.text.trim(),
            status: _status,
            revision: widget.supplier.revision));
  }

  @override
  Widget build(BuildContext context) {
    final en = Localizations.localeOf(context).languageCode != 'ko';
    return AlertDialog(
        title: Text(t('공개 업체 정보 검토', 'Review public supplier information')),
        content: SizedBox(
            width: 640,
            child: SingleChildScrollView(
                child: Form(
                    key: _form,
                    child: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          field(_name, '업체명', 'Business name', 120),
                          field(_website, '공식 홈페이지', 'Official website', 2048,
                              url: true),
                          field(_phone, '대표 연락처 (선택)',
                              'Business phone (optional)', 60,
                              required: false),
                          field(_products, '취급 품목', 'Products supplied', 500,
                              lines: 2),
                          Text(
                              t('품목 분류 (필수)', 'Product categories (required)')),
                          Wrap(spacing: 6, children: [
                            for (final c in supplierCategories.keys)
                              FilterChip(
                                  label: Text(supplierCategoryLabel(c, en)),
                                  selected: _categories.contains(c),
                                  onSelected: (v) => setState(() {
                                        if (v) {
                                          _categories.add(c);
                                        } else {
                                          _categories.remove(c);
                                        }
                                      }))
                          ]),
                          const SizedBox(height: 12),
                          Text(t('배송 지역 (필수)', 'Delivery areas (required)')),
                          Wrap(spacing: 6, children: [
                            for (final r in supplierRegions)
                              FilterChip(
                                  label: Text(supplierRegionLabel(r, en)),
                                  selected: _regions.contains(r),
                                  onSelected: (v) => setState(() {
                                        if (v) {
                                          if (r == '전국') {
                                            _regions.clear();
                                          } else {
                                            _regions.remove('전국');
                                          }
                                          _regions.add(r);
                                        } else {
                                          _regions.remove(r);
                                        }
                                      }))
                          ]),
                          const SizedBox(height: 12),
                          field(_shipping, '배송 조건·제한',
                              'Delivery terms and exclusions', 700,
                              lines: 3),
                          DropdownButtonFormField<String>(
                              initialValue: _kind,
                              isExpanded: true,
                              decoration: InputDecoration(
                                  labelText: t('업체 유형', 'Business type')),
                              items: [
                                DropdownMenuItem(
                                    value: 'store',
                                    child: Text(t('온라인 식자재몰',
                                        'Online ingredient store'))),
                                DropdownMenuItem(
                                    value: 'distributor',
                                    child: Text(
                                        t('계약 납품 업체', 'Contract distributor'))),
                                DropdownMenuItem(
                                    value: 'marketplace',
                                    child: Text(t('중개 플랫폼', 'Marketplace')))
                              ],
                              onChanged: (v) => setState(() => _kind = v!)),
                          const SizedBox(height: 16),
                          field(
                              _sources,
                              '공식 출처 주소 (한 줄에 하나, 최대 5개)',
                              'Official source URLs (one per line, up to 5)',
                              10240,
                              lines: 3),
                          field(_date, '자료 확인일 (YYYY-MM-DD)',
                              'Source check date (YYYY-MM-DD)', 10),
                          DropdownButtonFormField<String>(
                              initialValue: _status,
                              isExpanded: true,
                              decoration: InputDecoration(
                                  labelText: t('저장 상태', 'Save status')),
                              items: [
                                DropdownMenuItem(
                                    value: 'candidate',
                                    child:
                                        Text(t('후보로 보관', 'Keep as candidate'))),
                                DropdownMenuItem(
                                    value: 'published',
                                    child: Text(
                                        t('회원에게 공개', 'Publish to members'))),
                                DropdownMenuItem(
                                    value: 'hidden',
                                    child: Text(t('비공개', 'Hidden')))
                              ],
                              onChanged: (v) => setState(() => _status = v!)),
                          if (_status == 'published')
                            CheckboxListTile(
                                contentPadding: EdgeInsets.zero,
                                value: _confirmed,
                                title: Text(t('공식 출처와 공개할 정보를 확인했습니다.',
                                    'I reviewed the official sources and information to publish.')),
                                onChanged: (v) =>
                                    setState(() => _confirmed = v ?? false)),
                          if (_missing)
                            Text(
                                t('필수 분류·배송 지역·출처·확인일 및 공개 동의를 확인해 주세요.',
                                    'Check required categories, delivery areas, sources, date and publishing confirmation.'),
                                style: TextStyle(
                                    color:
                                        Theme.of(context).colorScheme.error)),
                        ])))),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context),
              child: Text(t('취소', 'Cancel'))),
          FilledButton(
              onPressed: save,
              child: Text(t('검토 내용 저장', 'Save reviewed details')))
        ]);
  }
}
