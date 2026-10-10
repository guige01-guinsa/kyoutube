import '../../../core/localization/app_localizations.dart';
import '../../auth/presentation/account_recovery_actions.dart';
import '../domain/affiliate_review.dart';
import 'package:flutter/material.dart';
import '../../../core/widgets/scout_page.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/localization/localized_text.dart';
import '../../../core/localization/affiliate_ui_translations.dart';
import '../../auth/application/auth_providers.dart';
import '../../membership/application/membership_providers.dart';
import '../data/shopping_affiliate_repository.dart';
import '../data/coupang_partners_repository.dart';
import '../data/shopping_assistant_repository.dart';
import 'shopping_assistant_dialogs.dart';
import 'affiliate_editor.dart';
import 'affiliate_import_dialog.dart';
import 'affiliate_history_dialog.dart';
import 'coupang_product_dialog.dart';

typedef AffiliatePageQuery = ({String query, String status, int offset});
final affiliateAdminPageProvider = FutureProvider.autoDispose
    .family<Map<String, dynamic>, AffiliatePageQuery>((ref, key) async {
  if (ref.watch(activeAccountIdProvider) == null ||
      ref.watch(membershipInfoProvider).valueOrNull?.isAdmin != true) {
    return {'rows': <Map<String, dynamic>>[], 'total': 0};
  }
  return ref
      .watch(shoppingAffiliateRepositoryProvider)
      .page(key.query, key.status, key.offset);
});

class ShoppingAffiliateAdminPage extends ConsumerStatefulWidget {
  const ShoppingAffiliateAdminPage({super.key, this.guided = false});
  final bool guided;
  @override
  ConsumerState<ShoppingAffiliateAdminPage> createState() =>
      _ShoppingAffiliateAdminPageState();
}

class _ShoppingAffiliateAdminPageState
    extends ConsumerState<ShoppingAffiliateAdminPage> {
  final _search = TextEditingController();
  String _query = '';
  late String _status = widget.guided ? 'draft' : 'active';
  int _offset = 0;
  bool _busy = false;
  final _selected = <String, Map<String, dynamic>>{};
  String? _result;
  AffiliatePageQuery get _key =>
      (query: _query, status: _status, offset: _offset);
  bool _same(String? account) =>
      mounted &&
      account != null &&
      ref.read(activeAccountIdProvider) == account &&
      ref.read(membershipInfoProvider).valueOrNull?.isAdmin == true;
  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  void _refresh() {
    _selected.clear();
    ref.invalidate(affiliateAdminPageProvider);
    ref.invalidate(shoppingAffiliatesProvider);
    setState(() {});
  }

  Future<void> _edit(Map<String, dynamic> row) async {
    await showDialog<void>(
        context: context,
        barrierDismissible: false,
        builder: (_) =>
            ShoppingAccountGuard(child: AffiliateEditor(data: row)));
    if (mounted) _refresh();
  }

  Future<void> _import() async {
    await showDialog<void>(
        context: context,
        barrierDismissible: false,
        builder: (_) =>
            const ShoppingAccountGuard(child: AffiliateImportDialog()));
    if (mounted) _refresh();
  }

  Future<void> _coupang() async {
    final account = ref.read(activeAccountIdProvider);
    if (_busy || !_same(account)) return;
    final draft = await showDialog<Map<String, dynamic>>(
        context: context,
        barrierDismissible: false,
        builder: (_) =>
            const ShoppingAccountGuard(child: CoupangProductDialog()));
    if (draft != null && _same(account)) await _edit(draft);
  }

  Future<void> _verifyAndPublish(Map<String, dynamic> row) async {
    final account = ref.read(activeAccountIdProvider);
    if (_busy || !_same(account)) return;
    if (row['program'] != 'coupang' ||
        (row['specification'] as String? ?? '').trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content:
              LocalizedText('쿠팡 상품과 판매 규격을 먼저 확인할 수 있도록 상품 정보를 수정해 주세요.')));
      return;
    }

    setState(() {
      _busy = true;
      _result = null;
    });
    var saved = false;
    try {
      final title = (row['title'] as String? ?? '').trim();
      final products = await ref
          .read(coupangPartnersRepositoryProvider)
          .search(title.length > 80 ? title.substring(0, 80) : title);
      if (!mounted || !_same(account)) return;
      final candidates = products
          .where((product) => product.imageUrl != null)
          .take(10)
          .toList();
      if (candidates.isEmpty) {
        throw const CoupangPartnersException('no_product_image');
      }

      final selected = await showDialog<CoupangProduct>(
          context: context,
          builder: (dialogContext) => ShoppingAccountGuard(
                  child: AlertDialog(
                      title: const LocalizedText('쿠팡 상품과 이미지 확인'),
                      content: SizedBox(
                          width: 520,
                          child: SingleChildScrollView(
                              child: Column(
                                  crossAxisAlignment:
                                      CrossAxisAlignment.stretch,
                                  children: [
                                LocalizedText('등록 상품: $title'),
                                LocalizedText(
                                    '규격: ${row['specification'] ?? ''}'),
                                const SizedBox(height: 8),
                                const LocalizedText(
                                    '같은 상품과 판매 규격인지 사진·상품명을 확인하고 선택하세요. 선택한 쿠팡 사진이 저장되고 장보기에 공개됩니다.'),
                                for (final product in candidates)
                                  Card(
                                      child: ListTile(
                                          leading: ClipRRect(
                                              borderRadius:
                                                  BorderRadius.circular(8),
                                              child: Image.network(product.imageUrl!,
                                                  width: 64,
                                                  height: 64,
                                                  fit: BoxFit.cover,
                                                  errorBuilder: (_, __, ___) =>
                                                      const SizedBox(
                                                          width: 64,
                                                          height: 64,
                                                          child: Icon(Icons
                                                              .image_not_supported_outlined)))),
                                          title: Text(product.title),
                                          subtitle: product.price == null
                                              ? null
                                              : Text(
                                                  '${product.price!.toStringAsFixed(0)}원 · 조회 시점 참고 가격'),
                                          trailing:
                                              const Icon(Icons.chevron_right),
                                          onTap: () =>
                                              Navigator.pop(dialogContext, product)))
                              ]))),
                      actions: [
                    TextButton(
                        onPressed: () => Navigator.pop(dialogContext),
                        child: const LocalizedText('취소'))
                  ])));
      if (!mounted || selected == null || !_same(account)) return;

      final confirm = await showDialog<bool>(
          context: context,
          builder: (dialogContext) => ShoppingAccountGuard(
                  child: AlertDialog(
                      title: const LocalizedText('장보기에 공개할까요?'),
                      content: SingleChildScrollView(
                          child: Column(
                              mainAxisSize: MainAxisSize.min,
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                            Text(title,
                                style: Theme.of(dialogContext)
                                    .textTheme
                                    .titleMedium),
                            Text('판매 규격: ${row['specification']}'),
                            const SizedBox(height: 12),
                            Center(
                                child: Image.network(selected.imageUrl!,
                                    width: 160,
                                    height: 160,
                                    fit: BoxFit.contain,
                                    errorBuilder: (_, __, ___) => const SizedBox(
                                        width: 160,
                                        height: 160,
                                        child: Icon(
                                            Icons.image_not_supported_outlined,
                                            size: 48)))),
                            Text(selected.title),
                            const SizedBox(height: 12),
                            const LocalizedText(
                                '확인하면 쿠팡 상품 사진을 저장하고 앱 장보기 목록에 공개합니다. 발급받은 제휴 링크는 그대로 유지되며 30일 뒤 다시 확인하도록 설정됩니다.')
                          ])),
                      actions: [
                    TextButton(
                        onPressed: () => Navigator.pop(dialogContext, false),
                        child: const LocalizedText('취소')),
                    FilledButton(
                        onPressed: () => Navigator.pop(dialogContext, true),
                        child: const LocalizedText('확인·공개'))
                  ])));
      if (!mounted || confirm != true || !_same(account)) return;

      final existingNote = (row['review_note'] as String? ?? '').trim();
      final verifiedAt = DateTime.now();
      final evidence =
          '${context.tr('쿠팡 검색 상품·사진을 관리자 확인함')} (${verifiedAt.toIso8601String()})';
      final note = existingNote.isEmpty ? evidence : '$existingNote\n$evidence';
      await ref.read(shoppingAffiliateRepositoryProvider).save({
        ...row,
        'product_verified': true,
        'image_url': selected.imageUrl,
        'review_note':
            note.length > 2000 ? note.substring(note.length - 2000) : note,
        'mobile_allowed': true,
        'published': true,
        'expires_at':
            verifiedAt.toUtc().add(const Duration(days: 30)).toIso8601String(),
      });
      if (!mounted || !_same(account)) return;
      saved = true;
      final ingredients = row['ingredients'] as List? ?? const [];
      final lookupName =
          ingredients.isEmpty ? title : ingredients.first.toString();
      var visibleInMobileShopping = false;
      try {
        final visibleOffers = await ref
            .read(shoppingAffiliateRepositoryProvider)
            .findForSurface(lookupName, 'mobile');
        visibleInMobileShopping = visibleOffers.any((offer) =>
            offer.id == row['id'] && offer.imageUrl == selected.imageUrl);
      } catch (_) {
        // Saving succeeded; keep the item and report that live lookup was unavailable.
      }
      if (!mounted || !_same(account)) return;
      final message = visibleInMobileShopping
          ? '${context.tr('쿠팡 상품 사진 저장 및 앱 장보기 노출을 확인했습니다')}: $title'
          : context.tr(
              '상품과 사진은 저장·공개했지만 앱 장보기에서 즉시 확인하지 못했습니다. 공개 상태와 연결을 확인해 주세요.');
      setState(() => _result = message);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(visibleInMobileShopping
              ? context.tr('쿠팡 상품 사진 저장 및 앱 장보기 노출을 확인했습니다.')
              : context.tr('저장은 완료했지만 장보기 노출을 확인하지 못했습니다.'))));
    } catch (error) {
      if (mounted && _same(account)) {
        final message = error is CoupangPartnersException
            ? switch (error.code) {
                'not_configured' => context.tr('쿠팡 파트너스 API 연결 설정이 필요합니다.'),
                'admin_mfa_required' => context.tr('관리자 2단계 인증 후 다시 시도해 주세요.'),
                'unauthorized' ||
                'admin_required' =>
                  context.tr('관리자 계정으로 다시 로그인해 주세요.'),
                'rate_limited' ||
                'upstream_rate_limited' =>
                  context.tr('쿠팡 조회 한도에 도달했습니다. 잠시 후 다시 시도해 주세요.'),
                'no_product_image' =>
                  context.tr('사진이 포함된 쿠팡 상품을 찾지 못했습니다. 공개하지 않았습니다.'),
                _ => context.tr('쿠팡 상품을 확인하지 못했습니다. 연결 상태를 확인한 뒤 다시 시도해 주세요.')
              }
            : context.tr('저장하지 못했습니다. 관리자 권한과 상품 정보를 확인한 뒤 다시 시도해 주세요.');
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(message)));
      }
    } finally {
      if (mounted && _same(account)) {
        setState(() => _busy = false);
        if (saved) _refresh();
      }
    }
  }

  Future<void> _change(String action, List<Map<String, dynamic>> rows) async {
    final account = ref.read(activeAccountIdProvider);
    if (_busy || !_same(account) || rows.isEmpty) return;
    final confirmed = await showDialog<bool>(
        context: context,
        builder: (_) => ShoppingAccountGuard(
                child: AlertDialog(
                    title: LocalizedText(_actions[action]!),
                    content: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          LocalizedText('${rows.length}'),
                          LocalizedText(action == 'delete'
                              ? '선택한 상품을 휴지통으로 이동합니다. 기존 레시피와 구매 기록은 유지됩니다.'
                              : action == 'restore'
                                  ? '초안으로 복원합니다. 확인 후 다시 공개하세요.'
                                  : '선택한 상품에 적용합니다. 공개 조건을 충족하지 못한 상품은 변경되지 않습니다.'),
                        ]),
                    actions: [
                  TextButton(
                      onPressed: () => Navigator.pop(context, false),
                      child: const LocalizedText('취소')),
                  FilledButton(
                      onPressed: () => Navigator.pop(context, true),
                      child: const LocalizedText('확인'))
                ])));
    if (confirmed != true || !_same(account)) return;
    setState(() {
      _busy = true;
      _result = null;
    });
    var saved = 0, failed = 0;
    for (final row in rows) {
      if (!_same(account)) break;
      try {
        await ref.read(shoppingAffiliateRepositoryProvider).change(row, action);
        saved++;
      } catch (_) {
        failed++;
      }
    }
    if (!_same(account)) {
      if (mounted) setState(() => _busy = false);
      return;
    }
    setState(() {
      _busy = false;
      _result = '${context.tr('처리 완료')}: $saved / ${context.tr('실패')}: $failed';
    });
    _refresh();
  }

  static const _actions = {
    'publish': '선택 공개',
    'hide': '공개 중단',
    'delete': '휴지통으로 이동',
    'restore': '복원'
  };
  @override
  Widget build(BuildContext context) {
    String t(String ko, String en) =>
        AppLocalizations.of(context).bilingual(ko, en);
    final account = ref.watch(activeAccountIdProvider);
    ref.listen(activeAccountIdProvider, (previous, next) {
      if (previous != next) {
        _selected.clear();
        _result = null;
        _offset = 0;
      }
    });
    final admin =
        ref.watch(membershipInfoProvider).valueOrNull?.isAdmin == true;
    return Scaffold(
        appBar: AppBar(
            title: Text(widget.guided
                ? t('상품 등록·공개 도우미', 'Product publishing assistant')
                : context.tr('제휴 상품 관리'))),
        body: account == null || !admin
            ? Center(child: AccountRecoveryActions(onRecovered: _refresh))
            : ScoutPageBody(
                child: ListView(padding: const EdgeInsets.all(20), children: [
                ScoutPageHeading(
                  title: widget.guided
                      ? t('등록부터 공개 확인까지', 'From registration to live display')
                      : t('식자재 구매 목록 관리', 'Manage ingredient shopping links'),
                  eyebrow: t('관리자 · 제휴 상품', 'ADMIN · AFFILIATE PRODUCTS'),
                  subtitle: t('상품을 등록하고 실제 상품과 규격을 확인한 뒤 사용자에게 공개하세요.',
                      'Add products, verify their details and package sizes, then publish for customers.'),
                  icon: Icons.inventory_2_outlined,
                ),
                if (widget.guided)
                  Padding(
                      padding: const EdgeInsets.only(top: 16),
                      child: Text(t(
                          '① 링크 등록 → ② 실제 상품·규격 확인 → ③ 게시 근거와 공개 설정 → ④ 실제 노출 확인\n검토가 필요한 초안부터 표시합니다. API 키가 없어도 발급받은 링크를 직접 등록할 수 있습니다.',
                          '1. Add a link → 2. Verify the product and size → 3. Confirm placement and publish → 4. Check live visibility\nDrafts are shown first. You can enter an issued link without API keys.'))),
                const SizedBox(height: 24),
                ScoutSectionLabel(
                    title: t('상품 등록', 'Add products'),
                    number: '01',
                    subtitle: t('한 개씩 추가하거나 목록에서 필요한 항목을 가져올 수 있습니다.',
                        'Add a single product or import the items you need from a list.')),
                Wrap(spacing: 12, runSpacing: 8, children: [
                  FilledButton.icon(
                      onPressed: _busy ? null : () => _edit({}),
                      icon: const Icon(Icons.add),
                      label: const LocalizedText('제휴 상품 추가')),
                  OutlinedButton.icon(
                      onPressed: _busy ? null : _import,
                      icon: const Icon(Icons.upload_file),
                      label: const LocalizedText('목록 가져오기')),
                  OutlinedButton.icon(
                      onPressed: _busy ? null : _coupang,
                      icon: const Icon(Icons.search),
                      label: Text(
                          t('쿠팡 상품 검색·링크 생성', 'Coupang products and links'))),
                  TextButton.icon(
                      onPressed: _busy ? null : _refresh,
                      icon: const Icon(Icons.refresh),
                      label: const LocalizedText('새로고침')),
                ]),
                const SizedBox(height: 12),
                ExpansionTile(
                    initiallyExpanded: false,
                    title: const LocalizedText('가입·연결 순서'),
                    children: [
                      for (final step in affiliateSetupSteps)
                        ListTile(
                            title: Text(
                                Localizations.localeOf(context).languageCode ==
                                        'en'
                                    ? step.$2
                                    : step.$1),
                            subtitle: TextButton(
                                onPressed: () async {
                                  try {
                                    if (await ref
                                            .read(shoppingLinkLauncherProvider)(
                                        Uri.parse(step.$3))) {
                                      return;
                                    }
                                  } catch (_) {/* show error */}
                                  if (context.mounted && _same(account)) {
                                    ScaffoldMessenger.of(context).showSnackBar(
                                        const SnackBar(
                                            content: LocalizedText(
                                                '주소를 열지 못했습니다. 다시 시도해 주세요.')));
                                  }
                                },
                                child: const LocalizedText('공식 안내 열기'))),
                    ]),
                const SizedBox(height: 24),
                ScoutSectionLabel(
                    title: t('상품 검색과 검토', 'Find and review products'),
                    number: '02'),
                TextField(
                    controller: _search,
                    maxLength: 160,
                    enabled: !_busy,
                    decoration: InputDecoration(
                        labelText: context.tr('상품·재료·분류 검색'),
                        prefixIcon: const Icon(Icons.search),
                        counterText: '',
                        suffixIcon: IconButton(
                            icon: const Icon(Icons.search),
                            onPressed: _busy
                                ? null
                                : () => setState(() {
                                      _query = _search.text.trim();
                                      _offset = 0;
                                      _selected.clear();
                                    }))),
                    onSubmitted: (v) => setState(() {
                          _query = v.trim();
                          _offset = 0;
                          _selected.clear();
                        })),
                const SizedBox(height: 12),
                DropdownButtonFormField<String>(
                    decoration: InputDecoration(
                        labelText: t('공개 상태', 'Publication status')),
                    initialValue: _status,
                    isExpanded: true,
                    items: [
                      for (final e in const {
                        'active': '전체 상품',
                        'draft': '초안·숨김',
                        'published': '공개 중',
                        'expired': '만료됨·숨김',
                        'trash': '휴지통'
                      }.entries)
                        DropdownMenuItem(
                            value: e.key, child: LocalizedText(e.value))
                    ],
                    onChanged: _busy
                        ? null
                        : (v) => setState(() {
                              _status = v!;
                              _offset = 0;
                              _selected.clear();
                            })),
                if (_busy) const LinearProgressIndicator(),
                if (_result != null)
                  Padding(
                      padding: const EdgeInsets.all(12), child: Text(_result!)),
                if (_result != null)
                  const LocalizedText('실패한 항목은 새로고침 후 상태와 공개 조건을 확인해 주세요.'),
                const SizedBox(height: 16),
                ref.watch(affiliateAdminPageProvider(_key)).when(
                    loading: () => const LinearProgressIndicator(),
                    error: (_, __) => const LocalizedText(
                        '저장하지 못했습니다. 관리자 2단계 인증·입력값을 확인하거나 새로고침 후 다시 시도하세요.'),
                    data: (page) {
                      final rows = (page['rows'] as List)
                          .map((e) => Map<String, dynamic>.from(e))
                          .toList();
                      final total = page['total'] as int;
                      return Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            ScoutSectionLabel(
                                title:
                                    t('상품 목록 · $total개', 'Products · $total'),
                                subtitle: t('확인할 상품을 선택한 후 아래 작업을 적용하세요.',
                                    'Select products and apply an action below.')),
                            CheckboxListTile(
                                controlAffinity:
                                    ListTileControlAffinity.leading,
                                contentPadding: EdgeInsets.zero,
                                title: const LocalizedText('현재 페이지 모두 선택'),
                                subtitle: LocalizedText(
                                    '${_selected.length} / ${rows.length}'),
                                value: rows.isNotEmpty &&
                                    rows.every(
                                        (r) => _selected.containsKey(r['id'])),
                                onChanged: _busy || rows.isEmpty
                                    ? null
                                    : (v) => setState(() {
                                          _selected.clear();
                                          if (v == true) {
                                            for (final r in rows) {
                                              _selected[r['id'] as String] = r;
                                            }
                                          }
                                        })),
                            Wrap(spacing: 8, children: [
                              for (final action in _status == 'trash'
                                  ? ['restore']
                                  : ['publish', 'hide', 'delete'])
                                OutlinedButton(
                                    onPressed: _busy || _selected.isEmpty
                                        ? null
                                        : () => _change(
                                            action, _selected.values.toList()),
                                    child: LocalizedText(_actions[action]!))
                            ]),
                            if (rows.isEmpty)
                              const Padding(
                                  padding: EdgeInsets.all(24),
                                  child: LocalizedText('표시할 상품이 없습니다.')),
                            for (final row in rows)
                              Card(
                                  margin: const EdgeInsets.only(top: 12),
                                  child: Padding(
                                      padding: const EdgeInsets.all(16),
                                      child: Column(
                                          crossAxisAlignment:
                                              CrossAxisAlignment.stretch,
                                          children: [
                                            CheckboxListTile(
                                                contentPadding: EdgeInsets.zero,
                                                controlAffinity:
                                                    ListTileControlAffinity
                                                        .leading,
                                                title: Text(
                                                    row['title'] as String),
                                                subtitle: Text([
                                                  row['source_code'],
                                                  row['category'],
                                                  row['specification']
                                                ]
                                                    .whereType<String>()
                                                    .where((v) => v.isNotEmpty)
                                                    .join(' · ')),
                                                value: _selected
                                                    .containsKey(row['id']),
                                                onChanged: _busy
                                                    ? null
                                                    : (v) => setState(() {
                                                          if (v == true) {
                                                            _selected[row['id']
                                                                    as String] =
                                                                row;
                                                          } else {
                                                            _selected.remove(
                                                                row['id']);
                                                          }
                                                        })),
                                            Align(
                                                alignment: Alignment.centerLeft,
                                                child: Chip(
                                                    label: LocalizedText(row[
                                                                'deleted_at'] !=
                                                            null
                                                        ? '휴지통'
                                                        : row['published'] !=
                                                                true
                                                            ? '초안·숨김'
                                                            : DateTime.parse(row[
                                                                            'expires_at']
                                                                        as String)
                                                                    .isAfter(
                                                                        DateTime
                                                                            .now())
                                                                ? '공개 중'
                                                                : '만료됨·숨김'))),
                                            if (widget.guided &&
                                                row['deleted_at'] == null)
                                              Padding(
                                                  padding: const EdgeInsets
                                                      .symmetric(vertical: 8),
                                                  child: Text(affiliateReviewTasks(
                                                          row,
                                                          english: Localizations
                                                                      .localeOf(
                                                                          context)
                                                                  .languageCode ==
                                                              'en')
                                                      .join('\n'))),
                                            Wrap(spacing: 8, children: [
                                              if (row['deleted_at'] == null)
                                                TextButton.icon(
                                                    onPressed: _busy
                                                        ? null
                                                        : () =>
                                                            _verifyAndPublish(
                                                                row),
                                                    icon: const Icon(Icons
                                                        .verified_outlined),
                                                    label: const LocalizedText(
                                                        '쿠팡 상품 확인·장보기 공개')),
                                              if (row['deleted_at'] == null)
                                                TextButton.icon(
                                                    onPressed: _busy
                                                        ? null
                                                        : () => _edit(row),
                                                    icon: const Icon(
                                                        Icons.edit_outlined),
                                                    label: const LocalizedText(
                                                        '수정')),
                                              TextButton(
                                                  onPressed: _busy
                                                      ? null
                                                      : () => showDialog<void>(
                                                          context: context,
                                                          builder: (_) =>
                                                              ShoppingAccountGuard(
                                                                  child: AffiliateHistoryDialog(
                                                                      id: row['id']
                                                                          as String))),
                                                  child: const LocalizedText(
                                                      '변경 이력')),
                                              TextButton(
                                                  onPressed: _busy
                                                      ? null
                                                      : () => _change(
                                                          row['deleted_at'] !=
                                                                  null
                                                              ? 'restore'
                                                              : 'delete',
                                                          [row]),
                                                  child: LocalizedText(
                                                      row['deleted_at'] != null
                                                          ? '복원'
                                                          : '휴지통으로 이동')),
                                            ]),
                                          ]))),
                            Wrap(
                                alignment: WrapAlignment.center,
                                crossAxisAlignment: WrapCrossAlignment.center,
                                spacing: 12,
                                children: [
                                  TextButton(
                                      onPressed: _busy || _offset == 0
                                          ? null
                                          : () => setState(() {
                                                _offset -= 25;
                                                _selected.clear();
                                              }),
                                      child: const LocalizedText('이전')),
                                  LocalizedText(
                                      '${total == 0 ? 0 : _offset + 1}–${(_offset + rows.length)} / $total'),
                                  TextButton(
                                      onPressed: _busy || _offset + 25 >= total
                                          ? null
                                          : () => setState(() {
                                                _offset += 25;
                                                _selected.clear();
                                              }),
                                      child: const LocalizedText('다음')),
                                ]),
                          ]);
                    }),
              ])));
  }
}
