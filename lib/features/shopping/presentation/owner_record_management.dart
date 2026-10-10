import '../../../core/format/user_number.dart';
import '../../../core/localization/localized_text.dart';
import 'package:go_router/go_router.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../auth/application/auth_providers.dart';
import '../data/owner_record_management_repository.dart';
import '../data/purchase_cleanup_repository.dart';
import 'shopping_assistant_dialogs.dart';

Future<Map<String, dynamic>?> manageOwnerRecord(
    BuildContext context, WidgetRef ref,
    {required String kind,
    required String id,
    String? workspace,
    String? currentUnit}) async {
  final account = ref.read(activeAccountIdProvider);
  if (account == null) return null;
  final result = await showDialog<Map<String, dynamic>>(
      context: context,
      barrierDismissible: false,
      builder: (_) => ShoppingAccountGuard(
          child: _OwnerRecordDialog(
              kind: kind,
              id: id,
              workspace: workspace,
              currentUnit: currentUnit)));
  if (!context.mounted || account != ref.read(activeAccountIdProvider)) {
    return null;
  }
  if (result != null) ref.invalidate(purchaseCleanupIndexProvider(workspace));
  return result;
}

class _OwnerRecordDialog extends ConsumerStatefulWidget {
  const _OwnerRecordDialog(
      {required this.kind, required this.id, this.workspace, this.currentUnit});
  final String kind, id;
  final String? workspace, currentUnit;
  @override
  ConsumerState<_OwnerRecordDialog> createState() => _OwnerRecordDialogState();
}

class _OwnerRecordDialogState extends ConsumerState<_OwnerRecordDialog> {
  final _unit = TextEditingController(), _factor = TextEditingController();
  late final _account = ref.read(activeAccountIdProvider);
  Map<String, dynamic>? _preview;
  String? _error;
  bool _busy = false, _confirmed = false;
  bool get _conversion => widget.kind == 'stock_unit';
  bool get _current => mounted && _account == ref.read(activeAccountIdProvider);
  String t(String ko, String en) => shopText(context, ko, en);
  @override
  void initState() {
    super.initState();
    if (!_conversion) Future.microtask(_load);
  }

  @override
  void dispose() {
    _unit.dispose();
    _factor.dispose();
    super.dispose();
  }

  String _message(Object error) {
    final code = error.toString();
    if (code.contains('MANAGEMENT_RESERVED')) {
      return t('진행 중인 조리 예약을 먼저 해제해 주세요.',
          'Release active cooking reservations first.');
    }
    if (code.contains('MANAGEMENT_RECEIPTS')) {
      return t('연결된 구매요청서를 먼저 정리해 주세요. 입고 기록만 지우면 중복 입고될 수 있습니다.',
          'Manage the linked purchase requests first. Erasing only receipts could allow duplicate deliveries.');
    }
    if (code.contains('MANAGEMENT_PRECISION')) {
      return t('환산 결과가 허용 수량 또는 소수점 6자리 범위를 벗어납니다. 비율을 다시 확인해 주세요.',
          'The conversion exceeds quantity limits or six decimal places. Check the ratio.');
    }
    if (code.contains('MANAGEMENT_DUPLICATE')) {
      return t('같은 재료·규격·단위의 품목이 이미 있습니다. 기존 품목을 확인해 주세요.',
          'An item with this name, specification and unit already exists. Review it first.');
    }
    if (code.contains('MANAGEMENT_STALE') ||
        code.contains('MANAGEMENT_DELETED')) {
      return t('확인 중 기록이 바뀌었거나 삭제되었습니다. 다시 확인을 눌러 최신 영향을 검토해 주세요.',
          'The record changed or was deleted. Review the latest effects again.');
    }
    if (code.contains('MANAGEMENT_DENIED')) {
      return t('소유자만 이 작업을 할 수 있습니다. 계정과 이용 권한을 확인해 주세요.',
          'Only the owner can perform this action. Check your account and access.');
    }
    return t('처리하지 못했습니다. 서버 업데이트와 입력값을 확인한 뒤 다시 시도해 주세요.',
        'Could not complete. Check the server update and inputs, then retry.');
  }

  Future<void> _load() async {
    if (_busy || !_current) return;
    final change = <String, dynamic>{};
    if (_conversion) {
      final value = parseUserNumber(_factor.text.trim());
      if (_unit.text.trim().isEmpty ||
          value == null ||
          !value.isFinite ||
          value <= 0) {
        setState(() => _error = t('새 단위와 0보다 큰 환산 비율을 입력해 주세요.',
            'Enter a new unit and a positive conversion ratio.'));
        return;
      }
      change.addAll({'unit': _unit.text.trim(), 'factor': value});
    }
    setState(() {
      _busy = true;
      _error = null;
      _preview = null;
      _confirmed = false;
    });
    try {
      final p = await ref.read(ownerRecordManagementRepositoryProvider).preview(
          widget.kind, widget.id,
          workspace: widget.workspace, change: change);
      if (_current) setState(() => _preview = p);
    } catch (e) {
      if (_current) setState(() => _error = _message(e));
    } finally {
      if (_current) setState(() => _busy = false);
    }
  }

  Future<void> _apply() async {
    final p = _preview;
    if (_busy ||
        !_confirmed ||
        !_current ||
        p == null ||
        p['blocked'] != null) {
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final result =
          await ref.read(ownerRecordManagementRepositoryProvider).apply(p);
      if (mounted && _current) Navigator.pop(context, result);
    } catch (e) {
      if (_current) {
        setState(() {
          _error = _message(e);
          _confirmed = false;
        });
      }
    } finally {
      if (_current) setState(() => _busy = false);
    }
  }

  Future<void> _resolve() async {
    if (_busy || widget.workspace == null) return;
    setState(() => _busy = true);
    try {
      final rows = await ref
          .read(ownerRecordManagementRepositoryProvider)
          .stockRecovery(widget.workspace!, widget.id, _unit.text.trim());
      if (!mounted || !_current) return;
      final selected = await showDialog<Map<String, dynamic>>(
          context: context,
          builder: (ctx) => AlertDialog(
                  title: Text(t('관련 자료 확인', 'Review related records')),
                  content: SizedBox(
                      width: 500,
                      child: SingleChildScrollView(
                          child: Column(mainAxisSize: MainAxisSize.min, children: [
                        for (final row in rows)
                          ListTile(
                              title: Text(row['title'] as String),
                              subtitle: Text(row['kind'] == 'stock'
                                  ? t('재고·조리 예약', 'Stock & reservations')
                                  : t('연결된 구매요청서', 'Linked purchase request')),
                              trailing: const Icon(Icons.chevron_right),
                              onTap: () => Navigator.pop(ctx, row)),
                      ]))),
                  actions: [
                    TextButton(
                        onPressed: () => Navigator.pop(ctx),
                        child: Text(t('닫기', 'Close')))
                  ]));
      if (!mounted || !_current || selected == null) return;
      await context.push(
          '/business-workspaces/${widget.workspace}/${selected['kind'] == 'stock' ? 'inventory' : 'records'}/${selected['id']}');
      if (!_current) return;
      setState(() {
        _preview = null;
        _confirmed = false;
      });
    } catch (_) {
      if (_current) {
        setState(() => _error = t('관련 자료를 불러오지 못했습니다. 다시 시도해 주세요.',
            'Could not load related records. Retry.'));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
    if (_current) await _load();
  }

  void _changed() => setState(() {
        _preview = null;
        _confirmed = false;
        _error = null;
      });
  @override
  Widget build(BuildContext context) {
    final p = _preview;
    final counts = p?['counts'] as Map? ?? {};
    final labels = {
      'history': t('함께 삭제되는 이력', 'History erased'),
      'reviews': t('함께 삭제되는 거래 평가', 'Reviews erased'),
      'products': t('삭제되는 취급상품', 'Products erased'),
      'defaults': t('해제되는 기본 구매 연결', 'Purchasing mappings detached'),
      'movements': t('관련 수불 기록', 'Related stock movements'),
      'reservations': t('관련 예약 기록', 'Related reservations'),
      'retained_receipts':
          t('재고를 유지하는 입고·반품 기록', 'Receipts and returns retaining stock'),
      'linked_batches':
          t('삭제 상태를 표시할 구매 준비 내역', 'Preparation results marked deleted'),
    };
    return PopScope(
        canPop: !_busy,
        child: AlertDialog(
          scrollable: true,
          title: Text(_conversion
              ? t('재고 단위 변경', 'Change stock unit')
              : t('영구 삭제 확인', 'Review permanent deletion')),
          content: SizedBox(
              width: 560,
              child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (_conversion) ...[
                      LocalizedText(
                          '${t('현재 단위', 'Current unit')}: ${widget.currentUnit}'),
                      TextField(
                          controller: _unit,
                          enabled: !_busy,
                          maxLength: 30,
                          decoration:
                              InputDecoration(labelText: t('새 단위', 'New unit')),
                          onChanged: (v) {
                            final ratio = suggestedStockConversion(
                                widget.currentUnit ?? '', v);
                            _factor.text = ratio?.toString() ?? '';
                            _changed();
                          }),
                      TextField(
                          controller: _factor,
                          enabled: !_busy,
                          keyboardType: const TextInputType.numberWithOptions(
                              decimal: true),
                          decoration: InputDecoration(
                              labelText: t('기존 1단위에 해당하는 새 단위 수량',
                                  'New quantity for one old unit')),
                          onChanged: (_) => _changed()),
                      Text(t(
                          '개·봉·박스 등은 실제 규격을 확인해 비율을 입력하세요. 구매 포장 수량과 금액은 유지됩니다.',
                          'For pieces, bags or boxes, verify the pack size and enter the ratio. Purchased pack quantities and prices stay unchanged.')),
                      TextButton(
                          onPressed: _busy ? null : _load,
                          child: Text(t('환산 영향 확인', 'Preview conversion'))),
                    ],
                    if (_busy) const LinearProgressIndicator(),
                    if (_error != null)
                      Text(_error!,
                          style: TextStyle(
                              color: Theme.of(context).colorScheme.error)),
                    if (p != null) ...[
                      Text(p['title'] as String,
                          style: Theme.of(context).textTheme.titleMedium),
                      for (final entry in counts.entries)
                        if ((entry.value as num) > 0)
                          LocalizedText(
                              '${labels[entry.key] ?? entry.key}: ${entry.value}'),
                      if (_conversion) ...[
                        for (final metric in [
                          ('on_hand', t('현재고', 'On hand')),
                          ('reserved', t('예약량', 'Reserved')),
                          ('available', t('사용 가능', 'Available'))
                        ])
                          LocalizedText(
                              '${metric.$2}: ${p['balance'][metric.$1]} ${p['unit']} → ${p['after'][metric.$1]} ${p['change']['unit']}'),
                        Text(t(
                            '변경 후 레시피의 재고 연결을 다시 확인하세요. 이전 화면에서 입력하던 작업은 새로고침해야 합니다.',
                            'Recheck recipe-to-stock mappings afterward. Refresh any screens opened before the change.')),
                      ] else ...[
                        if (widget.kind == 'stock' && p['balance'] != null)
                          LocalizedText(
                              '${t('현재고', 'On hand')}: ${p['balance']['on_hand']} ${p['unit']}'),
                        Text(t(
                            '이 기록은 복구할 수 없습니다. 외부에 전달한 주문의 취소·환불은 별도로 처리해야 합니다.',
                            'This record cannot be restored. Cancel or refund externally shared orders separately.')),
                        if (widget.kind != 'stock')
                          Text(t('실제 재고 수량은 변경하지 않습니다.',
                              'Physical stock quantities are unchanged.')),
                        if (widget.kind == 'stock')
                          Text(t('이 품목의 현재고와 수불·예약 기록을 함께 삭제합니다.',
                              'This item, its on-hand stock, movements and reservation history will be erased.')),
                        if (widget.kind == 'product' &&
                            widget.workspace == null)
                          Text(t('공개 가능한 상품이 남지 않으면 공급업체도 비공개로 전환됩니다.',
                              'The supplier will be unpublished if no publishable products remain.')),
                      ],
                      if (p['blocked'] != null)
                        Text(_message(p['blocked'] as String))
                      else
                        CheckboxListTile(
                            contentPadding: EdgeInsets.zero,
                            value: _confirmed,
                            onChanged: _busy
                                ? null
                                : (v) => setState(() => _confirmed = v == true),
                            title: Text(t('변경 대상과 영향을 확인했습니다.',
                                'I reviewed the target and its effects.'))),
                    ],
                  ])),
          actions: [
            TextButton(
                onPressed: _busy ? null : () => Navigator.pop(context),
                child: Text(t('닫기', 'Close'))),
            if (widget.workspace != null &&
                ['stock', 'stock_unit'].contains(widget.kind))
              TextButton(
                  onPressed: _busy ? null : _resolve,
                  child: Text(
                      t('관련 예약·요청서 확인', 'Review reservations / requests'))),
            if (p == null && !_busy)
              TextButton(
                  onPressed: _load, child: Text(t('다시 확인', 'Review again'))),
            FilledButton(
                onPressed:
                    !_busy && _confirmed && p != null && p['blocked'] == null
                        ? _apply
                        : null,
                child: Text(_conversion
                    ? t('단위 변경 적용', 'Apply unit change')
                    : t('영구 삭제', 'Delete permanently'))),
          ],
        ));
  }
}
