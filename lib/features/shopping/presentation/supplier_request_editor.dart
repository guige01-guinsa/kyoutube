import '../../../core/localization/localized_text.dart';
import '../domain/purchase_request_review.dart';
import 'purchase_review_dialog.dart';
import '../../guide/presentation/guide_help_button.dart';
import 'dart:async';
import 'package:url_launcher/url_launcher.dart';
import '../../suppliers/data/supplier_catalog_repository.dart';
import '../../suppliers/domain/supplier_product_link.dart';
import '../../suppliers/presentation/supplier_product_link_dialog.dart';
import 'dart:convert';
import '../application/purchase_workspace.dart';
import '../../workspace/application/workspace_navigation.dart';
import 'purchase_progress.dart';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../auth/application/auth_providers.dart';
import '../data/supplier_request_repository.dart';
import '../domain/shopping_assistant.dart';
import '../domain/supplier_request.dart';
import 'shopping_assistant_dialogs.dart';
import '../../suppliers/presentation/supplier_directory_page.dart';
import '../domain/business_registration.dart';
import '../data/business_document_store.dart';
import 'business_registration_widgets.dart';
import 'request_document_preview.dart';

class SupplierEditor extends ConsumerStatefulWidget {
  const SupplierEditor({super.key, this.supplier, this.returnSupplier = false});
  final bool returnSupplier;
  final ShoppingSupplier? supplier;
  @override
  ConsumerState<SupplierEditor> createState() => _SupplierEditorState();
}

class _SupplierEditorState extends ConsumerState<SupplierEditor> {
  final _form = GlobalKey<FormState>();
  late final _id = widget.supplier?.id ?? newShoppingId();
  late final _name = TextEditingController(text: widget.supplier?.name);
  late final _contact = TextEditingController(text: widget.supplier?.contact);
  late final _phone = TextEditingController(text: widget.supplier?.phone);
  late final _products = TextEditingController(text: widget.supplier?.products);
  late final _website = TextEditingController(text: widget.supplier?.website);
  late final _address = TextEditingController(text: widget.supplier?.address);
  late final _memo = TextEditingController(text: widget.supplier?.memo);
  late bool _favorite = widget.supplier?.favorite ?? false;
  bool _busy = false;
  ShoppingSupplier? _submittedSupplier;
  String? _error;
  String t(String ko, String en) => shopText(context, ko, en);
  @override
  void dispose() {
    for (final c in [
      _name,
      _contact,
      _phone,
      _products,
      _website,
      _address,
      _memo
    ]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _save() async {
    if (!_form.currentState!.validate()) return;
    final owner = ref.read(activeAccountIdProvider);
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      if (owner == null) throw StateError('Sign in required');
      await ref.read(supplierRequestRepositoryProvider).saveSupplier(
          _submittedSupplier ??= ShoppingSupplier(
              id: _id,
              name: _name.text.trim(),
              contact: _contact.text.trim(),
              phone: _phone.text.trim(),
              products: _products.text.trim(),
              website: _website.text.trim(),
              address: _address.text.trim(),
              memo: _memo.text.trim(),
              favorite: _favorite),
          existing: widget.supplier != null);
      ref.invalidate(shoppingSuppliersProvider);
      if (mounted && ref.read(activeAccountIdProvider) == owner) {
        Navigator.pop(
            context, widget.returnSupplier ? _submittedSupplier : true);
      }
    } on PostgrestException catch (error) {
      if (mounted) {
        setState(() => _error = error.message.contains('SUPPLIER_LIMIT')
            ? t('요금제의 구매처 한도에 도달했습니다. 기존 구매처를 수정하거나 구독을 변경해 주세요.',
                'Your plan’s store limit is reached. Edit an existing store or change your subscription.')
            : t('저장하지 못했습니다. 다시 시도해 주세요.',
                'Could not save. Please try again.'));
      }
    } catch (_) {
      if (mounted) {
        setState(() => _error = t('저장하지 못했습니다. 연결을 확인하고 다시 시도해 주세요.',
            'Could not save. Check your connection and try again.'));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => PopScope(
      canPop: !_busy,
      child: AlertDialog(
          scrollable: true,
          title: Text(t('구매처 정보', 'Store details')),
          content: SizedBox(
              width: 420,
              child: Form(
                  key: _form,
                  child: Column(children: [
                    TextFormField(
                        controller: _name,
                        enabled: !_busy && _submittedSupplier == null,
                        maxLength: 120,
                        decoration: InputDecoration(
                            labelText: t('구매처 이름', 'Store name')),
                        validator: (v) => (v ?? '').trim().isEmpty
                            ? t('구매처 이름을 입력해 주세요.', 'Enter a store name.')
                            : null),
                    CheckboxListTile(
                        contentPadding: EdgeInsets.zero,
                        value: _favorite,
                        onChanged: _busy || _submittedSupplier != null
                            ? null
                            : (v) => setState(() => _favorite = v ?? false),
                        title: Text(t('자주 쓰는 구매처', 'Favorite store')),
                        subtitle: Text(t('목록 위에 먼저 표시합니다.',
                            'Show first in your directory.'))),
                    TextFormField(
                        controller: _website,
                        enabled: !_busy && _submittedSupplier == null,
                        maxLength: 2048,
                        keyboardType: TextInputType.url,
                        autocorrect: false,
                        decoration: InputDecoration(
                            labelText:
                                t('구매 사이트 링크 (선택)', 'Store website (optional)'),
                            hintText: 'https://'),
                        validator: (v) => (v ?? '').trim().isEmpty ||
                                shoppingProductUri(v!) != null
                            ? null
                            : t('https://로 시작하는 구매처 링크를 입력해 주세요.',
                                'Enter a valid https:// store link.')),
                    TextFormField(
                        controller: _contact,
                        enabled: !_busy && _submittedSupplier == null,
                        maxLength: 120,
                        decoration: InputDecoration(
                            labelText:
                                t('담당자 (선택)', 'Contact person (optional)'))),
                    TextFormField(
                        controller: _phone,
                        enabled: !_busy && _submittedSupplier == null,
                        maxLength: 60,
                        keyboardType: TextInputType.phone,
                        decoration: InputDecoration(
                            labelText: t('연락처 (선택)', 'Phone (optional)'))),
                    TextFormField(
                        controller: _products,
                        enabled: !_busy && _submittedSupplier == null,
                        maxLength: 500,
                        maxLines: 3,
                        decoration: InputDecoration(
                            labelText: t('주로 구매하는 재료', 'Usual ingredients'))),
                    TextFormField(
                        controller: _address,
                        enabled: !_busy && _submittedSupplier == null,
                        maxLength: 500,
                        maxLines: 2,
                        decoration: InputDecoration(
                            labelText:
                                t('구매처 주소 (선택)', 'Store address (optional)'))),
                    TextFormField(
                        controller: _memo,
                        enabled: !_busy && _submittedSupplier == null,
                        maxLength: 1000,
                        maxLines: 3,
                        decoration: InputDecoration(
                            labelText: t('나만의 구매처 메모', 'Private store notes'),
                            helperText: t('요청서와 공유 문서에는 포함되지 않습니다.',
                                'Not included in requests or shared documents.'),
                            helperMaxLines: 2)),
                    Text(t('카카오톡 받는 사람은 공유할 때 직접 선택합니다.',
                        'Choose the recipient in KakaoTalk when sharing.')),
                    if (_error != null)
                      Text(_error!,
                          style: TextStyle(
                              color: Theme.of(context).colorScheme.error)),
                  ]))),
          actions: [
            TextButton(
                onPressed: _busy ? null : () => Navigator.pop(context),
                child: Text(t('취소', 'Cancel'))),
            FilledButton(
                onPressed: _busy ? null : _save, child: Text(t('저장', 'Save'))),
          ]));
}

class SupplierRequestEditor extends ConsumerStatefulWidget {
  const SupplierRequestEditor(
      {super.key,
      required this.suppliers,
      required this.groups,
      this.request,
      this.initialSupplierId,
      this.initialLines = const []});
  final List<ShoppingSupplier> suppliers;
  final List<ShoppingPurchaseGroup> groups;
  final List<SupplierRequestLine> initialLines;
  final SupplierRequest? request;
  final String? initialSupplierId;
  @override
  ConsumerState<SupplierRequestEditor> createState() =>
      _SupplierRequestEditorState();
}

class _SupplierRequestEditorState extends ConsumerState<SupplierRequestEditor> {
  late final String? _owner;
  late final RequestEditCheckpoint? _checkpoint =
      ref.read(requestEditCheckpointsProvider)[widget.request?.id];
  late final SupplierRequest? _initial = _checkpoint?.request ?? widget.request;
  bool _kept = false, _allowClose = false;
  late final String _originalData;
  @override
  void initState() {
    super.initState();
    _owner = ref.read(activeAccountIdProvider);
    _originalData = jsonEncode(_draft().data);
    if (_uploadedPaths.isNotEmpty) {
      _documentStore = ref.read(businessDocumentStoreProvider);
    }
  }

  bool get _dirty =>
      !_savedConfirmed &&
      (_checkpoint != null ||
          _submitted != null ||
          jsonEncode(_draft().data) != _originalData ||
          (_initial?.revision == 0 && _lines.isNotEmpty));

  Future<bool> _keepForLater() async {
    if (_busy || _documentBusy) return false;
    if (_owner != ref.read(activeAccountIdProvider)) return true;
    if (_dirty) {
      ref.read(requestEditCheckpointsProvider.notifier).state = {
        ...ref.read(requestEditCheckpointsProvider),
        _id: RequestEditCheckpoint(
            request: _draft(),
            suppliers: List.unmodifiable(_suppliers),
            submitted: _submitted,
            uploadedPaths: Set.unmodifiable(_uploadedPaths)),
      };
      _kept = true;
    }
    return true;
  }

  Future<void> _close() async {
    if (!await _keepForLater() || !mounted) return;
    setState(() => _allowClose = true);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) Navigator.pop(context);
    });
  }

  Future<void> _discard() async {
    final yes = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
                title: Text(t('작성 중인 변경을 버릴까요?', 'Discard these edits?')),
                content: Text(t('서버에 저장한 요청서는 유지됩니다.',
                    'Requests already saved to the server stay available.')),
                actions: [
                  TextButton(
                      onPressed: () => Navigator.pop(ctx, false),
                      child: Text(t('계속 작성', 'Keep editing'))),
                  FilledButton(
                      onPressed: () => Navigator.pop(ctx, true),
                      child: Text(t('변경 버리기', 'Discard edits')))
                ]));
    if (yes != true ||
        !mounted ||
        _owner != ref.read(activeAccountIdProvider)) {
      return;
    }
    final remaining = {...ref.read(requestEditCheckpointsProvider)}
      ..remove(_id);
    ref.read(requestEditCheckpointsProvider.notifier).state = remaining;
    _kept = false;
    setState(() => _allowClose = true);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) Navigator.pop(context);
    });
  }

  final _form = GlobalKey<FormState>();
  late final _suppliers = <ShoppingSupplier>[
    ...widget.suppliers,
    if (_initial != null &&
        _initial.revision > 0 &&
        _initial.supplier.id.isNotEmpty &&
        !widget.suppliers.any((s) => s.id == _initial.supplier.id))
      _initial.supplier,
  ];
  late final _id = _initial?.id ?? newShoppingId();
  late ShoppingSupplier? _supplier = _initial == null &&
          widget.initialSupplierId == null
      ? _suppliers.firstOrNull
      : _suppliers.cast<ShoppingSupplier?>().firstWhere(
          (s) => s?.id == (_initial?.supplier.id ?? widget.initialSupplierId),
          orElse: () => null);
  late final _buyer = TextEditingController(text: _initial?.buyer);
  late final _phone = TextEditingController(text: _initial?.phone);
  late final _address = TextEditingController(text: _initial?.address);
  late final _date = TextEditingController(text: _initial?.deliveryDate);
  late final _window = TextEditingController(text: _initial?.deliveryWindow);
  late final _notes = TextEditingController(text: _initial?.notes);
  late final _lines = [...(_initial?.lines ?? widget.initialLines)];
  late String _currency = _initial?.currency ?? 'KRW';
  late BusinessRegistration _buyerBusiness =
      _initial?.buyerBusiness ?? const BusinessRegistration();
  late BusinessRegistration _supplierBusiness =
      _initial?.supplierBusiness ?? const BusinessRegistration();
  BusinessDocumentStore? _documentStore;
  late final _uploadedPaths = <String>{...?_checkpoint?.uploadedPaths};
  bool _documentBusy = false;
  bool _busy = false;
  late SupplierRequest? _submitted = _checkpoint?.submitted;
  bool _savedConfirmed = false;
  String? _error;
  bool get _editable => !_busy && !_documentBusy && _submitted == null;
  String t(String ko, String en) => shopText(context, ko, en);
  @override
  void dispose() {
    for (final c in [_buyer, _phone, _address, _date, _window, _notes]) {
      c.dispose();
    }
    // An unconfirmed save may still be running on the server. Keep its images.
    if (!_kept && (_submitted == null || _savedConfirmed)) {
      for (final path in _uploadedPaths) {
        unawaited(_documentStore?.discard(path).catchError((Object _) {}) ??
            Future<void>.value());
      }
    }
    super.dispose();
  }

  SupplierRequest _draft() => SupplierRequest(
      id: _id,
      supplier: _supplier ?? const ShoppingSupplier(id: '', name: ''),
      lines: List.unmodifiable(_lines),
      buyer: _buyer.text.trim(),
      buyerBusiness: _buyerBusiness,
      supplierBusiness: _supplierBusiness,
      phone: _phone.text.trim(),
      address: _address.text.trim(),
      deliveryDate: _date.text.trim(),
      deliveryWindow: _window.text.trim(),
      notes: _notes.text.trim(),
      currency: _currency,
      revision: _initial?.revision ?? 0);
  bool _valid() {
    if (!_form.currentState!.validate()) return false;
    // ListView may unmount fields outside the viewport; validate controllers too.
    if (_supplier == null) {
      setState(() => _error = t('협력업체를 선택해 주세요.', 'Choose a supplier.'));
      return false;
    }
    if (_buyer.text.trim().isEmpty) {
      setState(() => _error = t('요청자를 입력해 주세요.', 'Enter the buyer.'));
      return false;
    }
    if (!validRequestDate(_date.text.trim())) {
      setState(() => _error = t('올바른 날짜를 입력해 주세요.', 'Enter a valid date.'));
      return false;
    }
    if (_lines.isEmpty ||
        _lines.any(
            (l) => l.quantity == null || l.quantity! <= 0 || l.unit.isEmpty)) {
      setState(() => _error = t('품목을 추가하고 각 품목의 수량과 단위를 확인해 주세요.',
          'Add items and confirm a quantity and unit for each.'));
      return false;
    }
    if (!_buyerBusiness.valid || !_supplierBusiness.valid) {
      setState(() => _error = t('사업자등록번호는 숫자 10자리로 입력해 주세요. 등록증에는 번호도 필요합니다.',
          'Enter a 10-digit registration number. Certificates also require a number.'));
      return false;
    }
    return true;
  }

  PurchaseRequestReview? _reviewCache;
  String? _reviewCacheKey;
  List<SupplierRequestLine>? _beforeReview;
  String? _appliedReviewKey;

  Future<void> _reviewPurchase() async {
    final original = List<SupplierRequestLine>.unmodifiable(_lines);
    final fingerprint = purchaseReviewFingerprint(original);
    final cacheKey =
        '$fingerprint|$_currency|${Localizations.localeOf(context).languageCode}';
    final owner = ref.read(activeAccountIdProvider);
    final result = await showDialog<List<SupplierRequestLine>>(
        context: context,
        builder: (_) => ShoppingAccountGuard(
                child: PurchaseReviewDialog(
              lines: original,
              currency: _currency,
              cached: _reviewCacheKey == cacheKey ? _reviewCache : null,
              onReviewed: (review) {
                if (!mounted || ref.read(activeAccountIdProvider) != owner) {
                  return;
                }
                _reviewCache = review;
                _reviewCacheKey = cacheKey;
              },
            )));
    if (result == null ||
        !mounted ||
        ref.read(activeAccountIdProvider) != owner ||
        !_editable ||
        purchaseReviewFingerprint(_lines) != fingerprint) {
      return;
    }
    setState(() {
      _beforeReview = original;
      _lines
        ..clear()
        ..addAll(result);
      _appliedReviewKey = purchaseReviewFingerprint(_lines);
    });
  }

  void _undoReview() {
    if (_beforeReview == null ||
        purchaseReviewFingerprint(_lines) != _appliedReviewKey) {
      return;
    }
    setState(() {
      _lines
        ..clear()
        ..addAll(_beforeReview!);
      _beforeReview = null;
      _appliedReviewKey = null;
    });
  }

  Future<void> _preview() async {
    if (!_valid()) return;
    await showDialog<void>(
        context: context,
        builder: (_) => RequestDocumentPreview(request: _draft()));
  }

  Future<void> _save() async {
    if (!_valid()) return;
    final owner = ref.read(activeAccountIdProvider);
    _submitted ??= _draft();
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      if (owner == null) throw StateError('Sign in required');
      final result =
          await ref.read(supplierRequestRepositoryProvider).save(_submitted!);
      _savedConfirmed = true;
      if (mounted && ref.read(activeAccountIdProvider) == owner) {
        final remaining = {...ref.read(requestEditCheckpointsProvider)}
          ..remove(_id);
        ref.read(requestEditCheckpointsProvider.notifier).state = remaining;
      }
      ref.invalidate(supplierRequestsProvider);
      if (mounted && ref.read(activeAccountIdProvider) == owner) {
        setState(() => _allowClose = true);
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted && ref.read(activeAccountIdProvider) == owner) {
            Navigator.pop(context, result);
          }
        });
      }
    } on PostgrestException catch (error) {
      if (mounted) {
        setState(() => _error = error.message
                .contains('SUPPLIER_REQUEST_MONTHLY_LIMIT')
            ? t('이번 달 새 구매 요청서 한도에 도달했습니다. 기존 요청서는 계속 조회·수정할 수 있습니다.',
                'Your monthly new-request limit is reached. You can still view and edit existing requests.')
            : t('저장 결과를 확인하지 못했습니다. 같은 내용으로 다시 시도해 주세요.',
                'Could not confirm the save. Retry the same details.'));
      }
    } catch (_) {
      if (mounted) {
        setState(() => _error = t(
            '저장 결과를 확인하지 못했습니다. 같은 내용으로 재시도하거나 닫고 요청서 목록을 새로고침해 주세요.',
            'Could not confirm the save. Retry the same details, or close and refresh requests.'));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _addFromProductLink() async {
    final owner = ref.read(activeAccountIdProvider);
    final selection = await showDialog<SupplierProductLinkSelection>(
        context: context,
        builder: (_) => ShoppingAccountGuard(
            child: SupplierProductLinkDialog(
                suppliers: _suppliers,
                createSupplier: () => showDialog<ShoppingSupplier>(
                    context: context,
                    builder: (_) => const ShoppingAccountGuard(
                        child: SupplierEditor(returnSupplier: true))))));
    if (!mounted ||
        selection == null ||
        owner != ref.read(activeAccountIdProvider)) {
      return;
    }
    final saved = selection.supplier ??
        _suppliers
            .where((s) =>
                s.publicListingId == selection.reference?.id &&
                s.publicListingId != null)
            .firstOrNull;
    if (_lines.isNotEmpty && saved?.id != _supplier?.id) {
      setState(() => _error = t(
          '이 요청서에는 다른 업체의 품목이 있습니다. 해당 업체의 새 요청서를 작성해 주세요.',
          'This request already contains items for another supplier. Create a separate request for that supplier.'));
      return;
    }
    final line = await showDialog<SupplierRequestLine>(
        context: context,
        builder: (_) => ShoppingAccountGuard(
            child: SupplierRequestLineEditor(
                currency: _currency,
                line: SupplierRequestLine(
                    id: newShoppingId(),
                    name: '',
                    quantity: null,
                    unit: '',
                    productUrl: selection.url))));
    if (!mounted ||
        line == null ||
        owner != ref.read(activeAccountIdProvider)) {
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final supplier = saved ??
          await ref
              .read(supplierCatalogRepositoryProvider)
              .selectPublicReference(selection.reference!.id);
      if (!mounted || owner != ref.read(activeAccountIdProvider)) return;
      ref.invalidate(shoppingSuppliersProvider);
      setState(() {
        if (!_suppliers.any((s) => s.id == supplier.id)) {
          _suppliers.add(supplier);
        }
        if (_supplier?.id != supplier.id) {
          _supplierBusiness = const BusinessRegistration();
        }
        _supplier = supplier;
        _lines.add(line);
      });
    } catch (_) {
      if (mounted) {
        setState(() => _error = t('거래처를 연결하지 못했습니다. 연결과 거래처 한도를 확인해 주세요.',
            'Could not connect the supplier. Check your connection and supplier limit.'));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _openSupplierWebsite() async {
    final uri = shoppingProductUri(_supplier?.website ?? '');
    if (uri == null) return;
    try {
      if (await launchUrl(uri,
          mode: LaunchMode.externalApplication, webOnlyWindowName: '_blank')) {
        return;
      }
    } catch (_) {/* Show a useful error instead of losing the draft. */}
    if (mounted) {
      setState(() => _error = t('홈페이지를 열지 못했습니다. 거래처의 주소를 확인해 주세요.',
          'Could not open the website. Check the supplier address.'));
    }
  }

  Future<void> _editLine(int? index) async {
    final line = await showDialog<SupplierRequestLine>(
        context: context,
        builder: (_) => ShoppingAccountGuard(
            child: SupplierRequestLineEditor(
                line: index == null ? null : _lines[index],
                currency: _currency)));
    if (line != null && mounted) {
      setState(() {
        if (index == null) {
          _lines.add(line);
        } else {
          _lines[index] = line;
        }
      });
    }
  }

  Future<void> _choose() async {
    final chosen = <String>{};
    final groups = widget.groups
        .where((g) => !g.sources
            .any((s) => _lines.any((l) => l.sourceIds.contains(s.item.id))))
        .toList();
    final result = await showDialog<bool>(
        context: context,
        builder: (ctx) => ShoppingAccountGuard(
            child: StatefulBuilder(
                builder: (ctx, change) => AlertDialog(
                        title:
                            Text(t('장보기 재료 선택', 'Choose shopping ingredients')),
                        content: SizedBox(
                            width: 420,
                            height: 360,
                            child: groups.isEmpty
                                ? Center(
                                    child: Text(t('추가할 미구매 재료가 없습니다.',
                                        'No pending ingredients to add.')))
                                : ListView(children: [
                                    for (final g in groups)
                                      CheckboxListTile(
                                          title: Text(g.name),
                                          subtitle: LocalizedText(
                                              '${shoppingNumber(g.neededQuantity)} ${shopUnit(context, g.unit)}'),
                                          value: chosen.contains(g.key),
                                          onChanged: (v) => change(() {
                                                if (v == true) {
                                                  chosen.add(g.key);
                                                } else {
                                                  chosen.remove(g.key);
                                                }
                                              }))
                                  ])),
                        actions: [
                          TextButton(
                              onPressed: () => Navigator.pop(ctx, false),
                              child: Text(t('취소', 'Cancel'))),
                          FilledButton(
                              onPressed: chosen.isEmpty ||
                                      chosen.length + _lines.length > 100
                                  ? null
                                  : () => Navigator.pop(ctx, true),
                              child: Text(t('추가', 'Add'))),
                        ]))));
    if (result == true && mounted) {
      setState(() => _lines.addAll(groups
          .where((g) => chosen.contains(g.key))
          .map(SupplierRequestLine.fromGroup)));
    }
  }

  Widget _field(TextEditingController c, String label, int max,
          {int lines = 1, String? Function(String?)? validator}) =>
      Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: TextFormField(
              controller: c,
              enabled: _editable,
              maxLength: max,
              maxLines: lines,
              decoration: InputDecoration(labelText: label),
              validator: validator));
  @override
  Widget build(BuildContext context) => WorkspaceEditGuard(
      dirty: _dirty,
      busy: _busy || _documentBusy,
      confirmLeave: _keepForLater,
      child: PopScope(
          canPop: _allowClose && !_busy && !_documentBusy,
          onPopInvokedWithResult: (didPop, _) {
            if (!didPop) _close();
          },
          child: Dialog.fullscreen(
              child: Scaffold(
            appBar: AppBar(
                title: Text(t('구매 요청서 작성', 'Write purchase request')),
                actions: [
                  GuideHelpButton(
                      lesson: 'buy-request', enabled: !_busy && !_documentBusy),
                  TextButton(
                      onPressed: _busy || _documentBusy ? null : _discard,
                      child: Text(t('변경 버리기', 'Discard edits')))
                ],
                leading: IconButton(
                    onPressed: _busy || _documentBusy ? null : _close,
                    tooltip: t('나중에 계속', 'Continue later'),
                    icon: const Icon(Icons.close))),
            body: Form(
                onChanged: () {
                  if (mounted) setState(() {});
                },
                key: _form,
                child: ListView(padding: const EdgeInsets.all(20), children: [
                  const PurchaseProgress(step: 2),
                  Text(t('닫으면 현재 앱에서 이어 쓸 수 있습니다. 앱 종료·새로고침 전에 저장해 주세요.',
                      'Continue later in this app session. Save before closing or refreshing the app.')),
                  const SizedBox(height: 8),
                  Text(t('요청서를 저장한 뒤 내용을 확인하고 공유합니다.',
                      'Save the request, review it, then share.')),
                  const SizedBox(height: 16),
                  DropdownButtonFormField<String>(
                      key: ValueKey(_supplier?.id),
                      initialValue: _supplier?.id,
                      validator: (v) => v == null
                          ? t('협력업체를 선택해 주세요.', 'Choose a supplier.')
                          : null,
                      isExpanded: true,
                      decoration:
                          InputDecoration(labelText: t('협력업체', 'Supplier')),
                      items: [
                        for (final s in _suppliers)
                          DropdownMenuItem(
                              value: s.id,
                              child:
                                  Text(s.name, overflow: TextOverflow.ellipsis))
                      ],
                      onChanged: _editable
                          ? (id) => setState(() {
                                if (_supplier?.id != id) {
                                  _supplierBusiness =
                                      const BusinessRegistration();
                                }
                                _supplier =
                                    _suppliers.firstWhere((s) => s.id == id);
                              })
                          : null),
                  TextButton.icon(
                      onPressed: !_editable
                          ? null
                          : () async {
                              final selected =
                                  await showDialog<ShoppingSupplier>(
                                      context: context,
                                      barrierDismissible: false,
                                      builder: (ctx) => ShoppingAccountGuard(
                                          child: Dialog.fullscreen(
                                              child: SupplierDirectoryPage(
                                                  selectMode: true,
                                                  onSelected: (s) =>
                                                      Navigator.of(ctx)
                                                          .pop(s)))));
                              if (selected != null && mounted) {
                                setState(() {
                                  if (!_suppliers
                                      .any((s) => s.id == selected.id)) {
                                    _suppliers.add(selected);
                                  }
                                  if (_supplier?.id != selected.id) {
                                    _supplierBusiness =
                                        const BusinessRegistration();
                                  }
                                  _supplier = selected;
                                });
                              }
                            },
                      icon: const Icon(Icons.storefront_outlined),
                      label: Text(t('공개 업체에서 선택 · 내 거래처 등록',
                          'Choose public supplier · add to my suppliers'))),
                  if (shoppingProductUri(_supplier?.website ?? '') != null)
                    TextButton.icon(
                        onPressed: _editable ? _openSupplierWebsite : null,
                        icon: const Icon(Icons.open_in_new),
                        label: Text(t('홈페이지에서 상품 찾기',
                            'Find products on supplier website'))),
                  OutlinedButton.icon(
                      onPressed: _editable && _lines.length < 100
                          ? _addFromProductLink
                          : null,
                      icon: const Icon(Icons.add_link),
                      label: Text(t('상품 링크로 업체 연결·품목 추가',
                          'Connect supplier and add item from link'))),
                  const SizedBox(height: 16),
                  _field(
                      _buyer, t('요청자 또는 사업장명', 'Buyer or business name'), 120,
                      validator: (v) => (v ?? '').trim().isEmpty
                          ? t('요청자를 입력해 주세요.', 'Enter the buyer.')
                          : null),
                  _field(
                      _phone, t('회신 연락처 (선택)', 'Reply phone (optional)'), 60),
                  for (final buyer in [true, false])
                    BusinessRegistrationInput(
                      key: ValueKey(buyer
                          ? 'buyer-business'
                          : 'supplier-business-${_supplier?.id}'),
                      title: buyer
                          ? t('요청 업소 사업자 정보 (선택)',
                              'Buyer business details (optional)')
                          : t('공급업체 사업자 정보 (선택)',
                              'Supplier business details (optional)'),
                      value: buyer ? _buyerBusiness : _supplierBusiness,
                      enabled: _editable,
                      onChanged: (v) => setState(() {
                        if (buyer) {
                          _buyerBusiness = v;
                        } else {
                          _supplierBusiness = v;
                        }
                      }),
                      onUploaded: (path) {
                        _documentStore ??=
                            ref.read(businessDocumentStoreProvider);
                        _uploadedPaths.add(path);
                      },
                      onBusyChanged: (v) {
                        if (mounted) setState(() => _documentBusy = v);
                      },
                    ),
                  _field(
                      _date,
                      t('희망 납품일 (YYYY-MM-DD, 선택)',
                          'Delivery date (YYYY-MM-DD, optional)'),
                      10,
                      validator: (v) => validRequestDate((v ?? '').trim())
                          ? null
                          : t('올바른 날짜를 입력해 주세요.', 'Enter a valid date.')),
                  _field(_window, t('희망 시간대 (선택)', 'Delivery time (optional)'),
                      120),
                  _field(_address,
                      t('납품 장소 (선택)', 'Delivery address (optional)'), 500,
                      lines: 2),
                  DropdownButtonFormField<String>(
                      initialValue: _currency,
                      decoration:
                          InputDecoration(labelText: t('통화', 'Currency')),
                      items: [
                        for (final c in ['KRW', 'USD'])
                          DropdownMenuItem(value: c, child: Text(c))
                      ],
                      onChanged: _editable
                          ? (v) => setState(() => _currency = v!)
                          : null),
                  const SizedBox(height: 16),
                  OutlinedButton.icon(
                      onPressed:
                          _editable && _lines.isNotEmpty && _lines.length <= 20
                              ? _reviewPurchase
                              : null,
                      icon: const Icon(Icons.auto_awesome_outlined),
                      label: Text(t(
                          'AI 검토·대안 만들기', 'Create AI review and alternative'))),
                  if (_lines.length > 20)
                    Text(t('AI 검토는 요청서당 최대 20품목까지 지원합니다.',
                        'AI review supports up to 20 items per request.')),
                  if (_beforeReview != null &&
                      purchaseReviewFingerprint(_lines) == _appliedReviewKey)
                    TextButton(
                        onPressed: _editable ? _undoReview : null,
                        child: Text(t('AI 반영 전 품목으로 되돌리기',
                            'Restore items before AI edits'))),
                  Text(t('요청 품목', 'Requested items'),
                      style: Theme.of(context).textTheme.titleLarge),
                  Text(t(
                      '구매할 수량을 확인하세요. 단가는 입력한 구매 단위 1개당 금액이며, 비워 두면 견적을 요청합니다.',
                      'Check purchase quantities. Unit price is per one purchase unit; leave it blank to request a quote.')),
                  const SizedBox(height: 12),
                  for (var i = 0; i < _lines.length; i++)
                    Card(
                        margin: const EdgeInsets.only(bottom: 10),
                        child: ListTile(
                            title: Text(_lines[i].name),
                            subtitle: LocalizedText(
                                '${shoppingNumber(_lines[i].quantity)} ${shopUnit(context, _lines[i].unit)}\n${_lines[i].details}'),
                            onTap: _editable ? () => _editLine(i) : null,
                            trailing: IconButton(
                                tooltip: t('품목 삭제', 'Remove item'),
                                icon: const Icon(Icons.remove_circle_outline),
                                onPressed: _editable
                                    ? () => setState(() => _lines.removeAt(i))
                                    : null))),
                  Wrap(spacing: 8, runSpacing: 8, children: [
                    OutlinedButton.icon(
                        onPressed:
                            _editable && _lines.length < 100 ? _choose : null,
                        icon: const Icon(Icons.checklist),
                        label: Text(t('장보기에서 선택', 'Choose from shopping'))),
                    TextButton.icon(
                        onPressed: _editable && _lines.length < 100
                            ? () => _editLine(null)
                            : null,
                        icon: const Icon(Icons.add),
                        label: Text(t('품목 직접 추가', 'Add an item'))),
                  ]),
                  const SizedBox(height: 16),
                  _field(_notes, t('요청사항 (선택)', 'Notes (optional)'), 1000,
                      lines: 3),
                  if (_error != null)
                    Text(_error!,
                        style: TextStyle(
                            color: Theme.of(context).colorScheme.error)),
                ])),
            bottomNavigationBar: SafeArea(
                top: false,
                child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(mainAxisSize: MainAxisSize.min, children: [
                      TextButton.icon(
                          onPressed: _editable ? _preview : null,
                          icon: const Icon(Icons.preview_outlined),
                          label: Text(
                              t('저장 전 PDF 미리보기', 'Preview PDF before saving'))),
                      FilledButton.icon(
                          onPressed: _busy || _documentBusy ? null : _save,
                          icon: const Icon(Icons.description_outlined),
                          label: Text(t('저장하고 미리보기', 'Save and preview')))
                    ]))),
          ))));
}

class SupplierRequestLineEditor extends StatefulWidget {
  const SupplierRequestLineEditor(
      {super.key, this.line, required this.currency});
  final SupplierRequestLine? line;
  final String currency;
  @override
  State<SupplierRequestLineEditor> createState() =>
      _SupplierRequestLineEditorState();
}

class _SupplierRequestLineEditorState extends State<SupplierRequestLineEditor> {
  final _form = GlobalKey<FormState>();
  late final _name = TextEditingController(text: widget.line?.name);
  late final _quantity = TextEditingController(
      text: widget.line?.quantity == null
          ? ''
          : shoppingNumber(widget.line!.quantity));
  late final _unit = TextEditingController(text: widget.line?.unit);
  late final _spec = TextEditingController(text: widget.line?.spec);
  late final _productUrl = TextEditingController(text: widget.line?.productUrl);
  late final _price = TextEditingController(
      text:
          widget.line?.price == null ? '' : shoppingNumber(widget.line!.price));
  String t(String ko, String en) => shopText(context, ko, en);
  @override
  void dispose() {
    for (final c in [_name, _quantity, _unit, _spec, _price, _productUrl]) {
      c.dispose();
    }
    super.dispose();
  }

  String? _required(String? v) =>
      (v ?? '').trim().isEmpty ? t('내용을 입력해 주세요.', 'Enter a value.') : null;
  @override
  Widget build(BuildContext context) => AlertDialog(
          scrollable: true,
          title: Text(t('요청 품목 수정', 'Edit requested item')),
          content: SizedBox(
              width: 420,
              child: Form(
                  key: _form,
                  child: Column(children: [
                    TextFormField(
                        controller: _name,
                        maxLength: 250,
                        decoration: InputDecoration(
                            labelText: t('재료명', 'Ingredient name')),
                        validator: _required),
                    TextFormField(
                        controller: _quantity,
                        keyboardType: const TextInputType.numberWithOptions(
                            decimal: true),
                        decoration: InputDecoration(
                            labelText: t('구매 요청 수량', 'Requested quantity')),
                        validator: (v) {
                          final n = shoppingInput(v ?? '');
                          return n == null ||
                                  n <= 0 ||
                                  n > 1e9 ||
                                  (n * 1e6 - (n * 1e6).round()).abs() > 0.001
                              ? t('양수와 소수점 6자리 이내로 입력해 주세요.',
                                  'Enter a positive number with up to 6 decimal places.')
                              : null;
                        }),
                    const SizedBox(height: 12),
                    TextFormField(
                        controller: _unit,
                        maxLength: 30,
                        decoration: InputDecoration(
                            labelText: t('구매 단위 (직접 입력 가능)',
                                'Purchase unit (custom allowed)')),
                        validator: _required),
                    Wrap(spacing: 6, children: [
                      for (final u in [
                        'g',
                        'kg',
                        'ml',
                        'l',
                        'ea',
                        'pack',
                        'box'
                      ])
                        ActionChip(
                            label: Text(shopUnit(context, u)),
                            onPressed: () => setState(() => _unit.text = u))
                    ]),
                    const SizedBox(height: 12),
                    TextFormField(
                        controller: _spec,
                        maxLength: 300,
                        maxLines: 2,
                        decoration: InputDecoration(
                            labelText: t('규격·브랜드·포장 설명',
                                'Specification, brand or pack details'))),
                    TextFormField(
                        controller: _productUrl,
                        maxLength: 2048,
                        keyboardType: TextInputType.url,
                        autocorrect: false,
                        decoration: InputDecoration(
                            labelText:
                                t('상품 링크 (선택)', 'Product link (optional)'),
                            helperText: t(
                                '링크는 요청서에 함께 저장됩니다. 상품명·규격·수량을 확인해 주세요.',
                                'Saved with the request. Confirm the product name, specification and quantity.'),
                            helperMaxLines: 3),
                        validator: (v) => (v ?? '').trim().isEmpty ||
                                shoppingProductUri(v!) != null
                            ? null
                            : t('올바른 https:// 상품 링크를 입력해 주세요.',
                                'Enter a valid https:// product link.')),
                    TextFormField(
                        controller: _price,
                        keyboardType: const TextInputType.numberWithOptions(
                            decimal: true),
                        decoration: InputDecoration(
                            labelText: t('단가 (선택)', 'Unit price (optional)'),
                            suffixText: widget.currency),
                        validator: (v) {
                          if ((v ?? '').trim().isEmpty) return null;
                          final n = shoppingInput(v!);
                          return n == null || n < 0 || n > 1e12
                              ? t('금액을 확인해 주세요.', 'Check the amount.')
                              : null;
                        }),
                  ]))),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(context),
                child: Text(t('취소', 'Cancel'))),
            FilledButton(
                onPressed: () {
                  if (!_form.currentState!.validate()) return;
                  Navigator.pop(
                      context,
                      SupplierRequestLine(
                          id: widget.line?.id ?? newShoppingId(),
                          name: _name.text.trim(),
                          quantity: shoppingInput(_quantity.text),
                          unit: _unit.text.trim(),
                          spec: _spec.text.trim(),
                          productUrl: _productUrl.text.trim(),
                          price: shoppingInput(_price.text),
                          sourceIds: widget.line?.sourceIds ?? []));
                },
                child: Text(t('확인', 'Confirm'))),
          ]);
}
