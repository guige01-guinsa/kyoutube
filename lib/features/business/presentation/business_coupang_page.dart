import '../../../core/localization/localized_text.dart';
import '../../../core/auth/auth_return.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../auth/application/auth_providers.dart';
import '../../shopping/data/shopping_affiliate_repository.dart';
import '../../shopping/domain/shopping_affiliate.dart';
import '../../shopping/domain/coupang_purchase_plan.dart';
import '../../shopping/domain/shopping_assistant.dart';
import '../../shopping/presentation/shopping_assistant_dialogs.dart';
import '../../shopping/presentation/coupang_disclosure.dart';
import '../application/business_coupang_service.dart';
import '../data/business_repository.dart';
import '../domain/business_coupang.dart';
import '../domain/business_workspace.dart';

String _blockText(BuildContext context, BusinessCoupangBlock block) =>
    switch (block) {
      BusinessCoupangBlock.access => shopText(context,
          '구매 담당 권한이 있어야 쿠팡 상품을 열 수 있습니다.', 'Purchasing access is required.'),
      BusinessCoupangBlock.practice => shopText(
          context,
          '연습용 업소에서는 실제 구매 링크를 열 수 없습니다.',
          'Real purchases are disabled in practice workspaces.'),
      BusinessCoupangBlock.approval => shopText(
          context,
          '요청서를 승인한 뒤 쿠팡 상품을 확인할 수 있습니다.',
          'Approve the request before opening Coupang products.'),
      BusinessCoupangBlock.closed => shopText(
          context,
          '이미 전달·입고·취소된 요청입니다. 기존 주문과 입고 내역을 확인하세요.',
          'This request is no longer awaiting purchase. Check its orders and receipts.'),
      BusinessCoupangBlock.invalid => shopText(
          context, '구매요청서에서 이용해 주세요.', 'Open this from a purchase request.'),
    };

class BusinessCoupangEntry extends StatelessWidget {
  const BusinessCoupangEntry(
      {super.key,
      required this.business,
      required this.request,
      this.explainBlocked = false,
      this.enabled = true});
  final BusinessContext business;
  final BusinessRecord request;
  final bool explainBlocked, enabled;
  @override
  Widget build(BuildContext context) {
    final block = businessCoupangBlock(business, request);
    if (block != null) {
      return explainBlocked
          ? Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Text(_blockText(context, block)))
          : const SizedBox.shrink();
    }
    return OutlinedButton.icon(
        key: ValueKey('business-coupang-${request.id}'),
        onPressed: enabled
            ? () => context.push(
                '/business-workspaces/${request.workspace}/coupang/${request.id}')
            : null,
        icon: const Icon(Icons.shopping_bag_outlined),
        label: Text(shopText(context, '쿠팡 상품 확인', 'View Coupang products')));
  }
}

class BusinessCoupangPage extends ConsumerWidget {
  const BusinessCoupangPage(
      {super.key, required this.workspace, required this.recordId});
  final String workspace, recordId;
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final account = ref.watch(activeAccountIdProvider);
    final query = (workspace: workspace, id: recordId);
    void refresh() {
      ref.invalidate(businessContextProvider(workspace));
      ref.invalidate(businessRecordProvider(query));
      ref.invalidate(shoppingAffiliatesProvider);
    }

    Widget retry() => Center(
        child: TextButton(
            onPressed: refresh,
            child: Text(shopText(context, '최신 권한과 요청서를 확인하지 못했습니다. 다시 확인',
                'Could not check access and the request. Retry'))));
    const loading = Center(child: CircularProgressIndicator());
    return Scaffold(
        appBar: AppBar(
            title: Text(shopText(context, '쿠팡 상품 확인', 'View Coupang products')),
            actions: [
              IconButton(
                  onPressed: () async {
                    await context.push(
                        '/business-workspaces/$workspace/records/$recordId');
                    if (context.mounted &&
                        ref.read(activeAccountIdProvider) == account) {
                      refresh();
                    }
                  },
                  icon: const Icon(Icons.edit_note),
                  tooltip:
                      shopText(context, '요청서 확인·수정', 'Review / edit request')),
              IconButton(
                  onPressed: refresh,
                  icon: const Icon(Icons.refresh),
                  tooltip: shopText(context, '최신 자료 다시 확인', 'Refresh'))
            ]),
        body: account == null
            ? Center(
                child: FilledButton(
                    onPressed: () => context.push(loginFor(
                        GoRouterState.of(context).uri.toString(),
                        resume: true)),
                    child: Text(shopText(context, '로그인', 'Sign in'))))
            : ref.watch(businessContextProvider(workspace)).when(
                // Keep an open comparison during the periodic access refresh.
                // Revocation/errors block the page; opening checks fresh access.
                skipLoadingOnRefresh: true,
                skipLoadingOnReload: false,
                loading: () => loading,
                error: (_, __) => retry(),
                data: (business) {
                  if (!business.can('purchasing.read')) {
                    return Center(
                        child: Text(
                            _blockText(context, BusinessCoupangBlock.access)));
                  }
                  return ref.watch(businessRecordProvider(query)).when(
                      skipLoadingOnRefresh: false,
                      skipLoadingOnReload: false,
                      loading: () => loading,
                      error: (_, __) => retry(),
                      data: (request) {
                        final block = businessCoupangBlock(business, request);
                        if (block != null) {
                          return Center(
                              child: Padding(
                                  padding: const EdgeInsets.all(24),
                                  child: Text(_blockText(context, block))));
                        }
                        return _CoupangRequest(
                            key: ValueKey(
                                '$account:$workspace:$recordId:${request.revision}:${request.status}'),
                            account: account,
                            request: request);
                      });
                }));
  }
}

class _CoupangRequest extends ConsumerStatefulWidget {
  const _CoupangRequest(
      {super.key, required this.account, required this.request});
  final String account;
  final BusinessRecord request;
  @override
  ConsumerState<_CoupangRequest> createState() => _CoupangRequestState();
}

class _CoupangRequestState extends ConsumerState<_CoupangRequest> {
  int? _index;
  bool _opened = false;
  String t(String ko, String en) => shopText(context, ko, en);
  Future<void> _review(
      BusinessCoupangLine line, ShoppingAffiliate? offer) async {
    final request = snapshotBusinessPurchase(widget.request);
    final opened = await showDialog<bool>(
        context: context,
        barrierDismissible: false,
        builder: (_) => ShoppingAccountGuard(
            child: _CoupangConfirmation(
                request: request,
                line: line,
                offer: offer == null
                    ? null
                    : ShoppingAffiliate(Map<String, dynamic>.from(offer.data)),
                account: widget.account,
                isCurrent: () =>
                    mounted &&
                    ref.read(activeAccountIdProvider) == widget.account &&
                    sameBusinessPurchase(widget.request, request))));
    if (mounted && opened == true) setState(() => _opened = true);
  }

  @override
  Widget build(BuildContext context) {
    final request = widget.request;
    final lines = businessCoupangLines(request);
    final line =
        lines.where((l) => l.index == _index).firstOrNull ?? lines.firstOrNull;
    return Center(
        child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 900),
            child: CoupangDisclosureLayout(
                ingredients: [if (line != null) line.name],
                child: ListView(padding: const EdgeInsets.all(20), children: [
                  Text(request.title,
                      style: Theme.of(context).textTheme.titleLarge),
                  Text(t('승인된 요청서 · v${request.revision}',
                      'Approved request · v${request.revision}')),
                  const SizedBox(height: 12),
                  Text(t(
                      '요청서의 거래처·상품·규격·금액과 다르면 수정 후 다시 승인받으세요. 쿠팡에서 최종 옵션과 배송비를 확인합니다.',
                      'If the supplier, product, specification or amount differs, edit and reapprove the request. Check final options and shipping at Coupang.')),
                  const SizedBox(height: 12),
                  if (_opened)
                    Card(
                        child: Padding(
                            padding: const EdgeInsets.all(12),
                            child: Text(t(
                                '상품 페이지를 열었습니다. 실제 주문 여부는 쿠팡 주문 내역에서 확인하세요.',
                                'Product page opened. Check Coupang order history to confirm an actual order.')))),
                  if (line == null)
                    Text(t('확인할 수 있는 재료·수량이 없습니다. 요청서를 다시 확인하세요.',
                        'No valid ingredient quantities. Review the request.'))
                  else ...[
                    DropdownButtonFormField<int>(
                        key: ValueKey('coupang-lines-${request.id}'),
                        initialValue: line.index,
                        isExpanded: true,
                        decoration: InputDecoration(
                            labelText: t('구매할 재료', 'Ingredient')),
                        items: [
                          for (final item in lines)
                            DropdownMenuItem(
                                value: item.index,
                                child: LocalizedText('${item.index + 1}. ${item.name}',
                                    overflow: TextOverflow.ellipsis))
                        ],
                        onChanged: (value) => setState(() {
                              _index = value;
                              _opened = false;
                            })),
                    const SizedBox(height: 12),
                    _RequestLine(request: request, line: line),
                    const SizedBox(height: 16),
                    ref.watch(shoppingAffiliatesProvider(line.name)).when(
                        skipLoadingOnRefresh: false,
                        loading: () => const LinearProgressIndicator(),
                        error: (_, __) => TextButton.icon(
                            onPressed: () => ref.invalidate(
                                shoppingAffiliatesProvider(line.name)),
                            icon: const Icon(Icons.refresh),
                            label: Text(t('상품을 불러오지 못했습니다. 다시 확인',
                                'Could not load products. Retry'))),
                        data: (all) {
                          final plan = CoupangPurchasePlan.parse(
                              (request.data['lines'] as List)[line.index]
                                  ['coupang']);
                          final offers = businessCoupangOffers(all)
                              .where((o) => plan == null || plan.matches(o))
                              .toList();
                          if (offers.isEmpty) {
                            return Column(children: [
                              Text(t('이 재료에 공개된 쿠팡 상품이 없습니다.',
                                  'No published Coupang products for this ingredient.')),
                              if (plan == null)
                                OutlinedButton.icon(
                                    onPressed: () => _review(line, null),
                                    icon: const Icon(Icons.open_in_new),
                                    label: Text(t('쿠팡에서 다른 상품 찾기',
                                        'Find other products on Coupang'))),
                              if (plan != null)
                                TextButton(
                                    onPressed: () async {
                                      await context.push(
                                          '/business-workspaces/${request.workspace}/records/${request.id}');
                                      if (!mounted ||
                                          ref.read(activeAccountIdProvider) !=
                                              widget.account) {
                                        return;
                                      }
                                      ref.invalidate(businessRecordProvider((
                                        workspace: request.workspace,
                                        id: request.id
                                      )));
                                      ref.invalidate(
                                          shoppingAffiliatesProvider);
                                    },
                                    child: Text(t(
                                        '요청서 확인·수정', 'Review / edit request'))),
                              Text(plan == null
                                  ? t('일반 검색은 제휴 링크가 아닙니다. 승인된 규격·수량을 확인하고 실제 구매 내역을 기록하세요.',
                                      'General search is not an affiliate link. Check approved specifications and quantities and record the actual purchase.')
                                  : t('승인된 상품이 변경되었습니다. 요청서를 수정하고 다시 승인해 주세요.',
                                      'The approved product changed. Edit and reapprove the request.')),
                            ]);
                          }
                          return Column(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                for (final offer in offers)
                                  Card(
                                      child: Padding(
                                          padding: const EdgeInsets.all(14),
                                          child: Column(
                                              crossAxisAlignment:
                                                  CrossAxisAlignment.stretch,
                                              children: [
                                                Text(offer.title,
                                                    style: Theme.of(context)
                                                        .textTheme
                                                        .titleMedium),
                                                Text(t(
                                                    '상품 규격: ${offer.specification.isEmpty ? '쿠팡에서 확인' : offer.specification}',
                                                    'Product size: ${offer.specification.isEmpty ? 'Check at Coupang' : offer.specification}')),
                                                OutlinedButton.icon(
                                                    onPressed: () =>
                                                        _review(line, offer),
                                                    icon: const Icon(Icons
                                                        .fact_check_outlined),
                                                    label: Text(t('요청서와 비교·구매',
                                                        'Compare with request & buy'))),
                                              ]))),
                              ]);
                        }),
                  ],
                  const SizedBox(height: 20),
                  Text(t(
                      '쿠팡 주문 후 요청서에서 ‘전달 완료로 기록’을 선택하고, 수령 후 ‘품목별 입고·반품’에서 실제 수량을 확인하세요. 링크를 열어도 구매 상태와 재고는 바뀌지 않습니다.',
                      'After ordering, use “Record sharing” on the request, then record actual quantities under “Item receipts & returns” on delivery. Opening a link does not change purchase status or stock.')),
                  TextButton(
                      onPressed: () => context.go(
                          '/business-workspaces/${request.workspace}/records/${request.id}'),
                      child: Text(t('요청서로 돌아가기', 'Back to request'))),
                ]))));
  }
}

class _RequestLine extends StatelessWidget {
  const _RequestLine({required this.request, required this.line});
  final BusinessRecord request;
  final BusinessCoupangLine line;
  @override
  Widget build(BuildContext context) {
    String t(String ko, String en) => shopText(context, ko, en);
    return Card(
        child: Padding(
            padding: const EdgeInsets.all(14),
            child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(t('요청서의 구매 기준', 'Request purchasing details'),
                      style: Theme.of(context).textTheme.titleSmall),
                  LocalizedText('${request.data['supplier'] ?? ''} · ${line.name}'),
                  if (CoupangPurchasePlan.parse((request.data['lines']
                          as List)[line.index]['coupang'])
                      case final plan?) ...[
                    LocalizedText('${plan.offer.title} · ${plan.pack.option}'),
                    Text(t(
                        '추가 필요 ${shoppingNumber(plan.needed)} ${plan.unit} → 구매 총량 ${shoppingNumber(plan.total)} ${plan.unit}',
                        'Needed ${shoppingNumber(plan.needed)} ${plan.unit} → purchase total ${shoppingNumber(plan.total)} ${plan.unit}')),
                  ],
                  Text(t('구매량: ${shoppingNumber(line.quantity)} ${line.unit}',
                      'Quantity: ${shoppingNumber(line.quantity)} ${line.unit}')),
                  if (line.spec.isNotEmpty)
                    Text(t('규격: ${line.spec}', 'Specification: ${line.spec}')),
                  Text(line.price == null
                      ? t('단가: 미정', 'Unit price: not set')
                      : t('단가: ${shoppingNumber(line.price)} ${request.data['currency'] ?? 'KRW'} / ${line.unit}',
                          'Unit price: ${shoppingNumber(line.price)} ${request.data['currency'] ?? 'KRW'} / ${line.unit}')),
                  Text(t('쿠팡 옵션의 포장 수량과 요청서 단위는 직접 확인하세요.',
                      'Check Coupang package quantities against the request units.')),
                ])));
  }
}

class _CoupangConfirmation extends ConsumerStatefulWidget {
  const _CoupangConfirmation(
      {required this.request,
      required this.line,
      required this.offer,
      required this.account,
      required this.isCurrent});
  final BusinessRecord request;
  final BusinessCoupangLine line;
  final ShoppingAffiliate? offer;
  final String account;
  final bool Function() isCurrent;
  @override
  ConsumerState<_CoupangConfirmation> createState() =>
      _CoupangConfirmationState();
}

class _CoupangConfirmationState extends ConsumerState<_CoupangConfirmation> {
  bool _matches = false, _notOrdered = false, _busy = false;
  String? _error;
  String t(String ko, String en) => shopText(context, ko, en);
  Future<void> _open() async {
    if (_busy || !_matches || !_notOrdered) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await ref.read(businessCoupangServiceProvider).open(
          request: widget.request,
          lineIndex: widget.line.index,
          offer: widget.offer,
          isCurrent: () =>
              mounted &&
              widget.isCurrent() &&
              ref.read(activeAccountIdProvider) == widget.account);
      if (mounted) Navigator.of(context).pop(true);
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _error = switch (error) {
          BusinessCoupangFailure.changed => t(
              '요청서가 변경됐습니다. 닫고 최신 자료를 다시 확인하세요.',
              'The request changed. Close and refresh it.'),
          BusinessCoupangFailure.unavailable => t(
              '상품이 변경되었거나 공개가 중단됐습니다. 닫고 상품을 다시 확인하세요.',
              'The product changed or is no longer published. Close and refresh.'),
          BusinessCoupangFailure.access || BusinessCoupangFailure.account => t(
              '현재 계정의 권한과 승인 상태를 확인해 주세요.',
              'Check the current account, permissions and approval.'),
          BusinessCoupangFailure.open => t('상품을 열지 못했습니다. 다시 확인 후 시도해 주세요.',
              'Could not open the product. Check and try again.'),
          _ => t('최신 정보를 확인하지 못했습니다. 연결을 확인하고 다시 시도해 주세요.',
              'Could not verify current details. Check your connection and retry.'),
        };
        _matches = false;
        _notOrdered = false;
      });
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => PopScope(
      canPop: !_busy,
      child: AlertDialog(
          scrollable: true,
          title: Text(t('쿠팡 구매 전 확인', 'Before buying at Coupang')),
          content: SizedBox(
              width: 520,
              child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _RequestLine(request: widget.request, line: widget.line),
                    const SizedBox(height: 12),
                    if (widget.offer != null) ...[
                      Text(widget.offer!.title,
                          style: Theme.of(context).textTheme.titleMedium),
                      Text(widget.offer!.specification),
                    ] else
                      Text(t(
                          '쿠팡 일반 검색으로 이동합니다. 제휴 링크가 아니며 주문·입고는 자동 기록되지 않습니다.',
                          'This opens general Coupang search, not an affiliate link. Orders and receipts are not recorded automatically.')),
                    Text(t(
                        '상품과 승인 내용이 다르면 먼저 요청서를 수정·재승인하세요. 최종 옵션·가격·배송비는 쿠팡에서 확인합니다.',
                        'If this differs from the approval, edit and reapprove the request first. Check final options, price and shipping at Coupang.')),
                    CheckboxListTile(
                        key: const Key('coupang-match-confirm'),
                        contentPadding: EdgeInsets.zero,
                        value: _matches,
                        onChanged: _busy
                            ? null
                            : (v) => setState(() => _matches = v == true),
                        title: Text(widget.offer == null
                            ? t('승인된 거래처·규격·구매량·금액을 확인했고, 조건이 다르면 요청서를 수정·재승인하겠습니다.',
                                'I reviewed the approved purchasing terms and will edit and reapprove the request if they differ.')
                            : t('거래처·상품·규격·구매량·금액이 승인 내용과 맞는지 확인했습니다.',
                                'I checked the supplier, product, size, quantity and amount against the approval.'))),
                    CheckboxListTile(
                        key: const Key('coupang-order-confirm'),
                        contentPadding: EdgeInsets.zero,
                        value: _notOrdered,
                        onChanged: _busy
                            ? null
                            : (v) => setState(() => _notOrdered = v == true),
                        title: Text(t('이미 주문했거나 다른 담당자가 주문 중인 건이 아닌지 확인했습니다.',
                            'I checked that this has not already been ordered and no other buyer is ordering it.'))),
                    if (_busy) const LinearProgressIndicator(),
                    if (_error != null)
                      Text(_error!,
                          style: TextStyle(
                              color: Theme.of(context).colorScheme.error)),
                  ])),
          actions: [
            TextButton(
                onPressed:
                    _busy ? null : () => Navigator.of(context).pop(false),
                child: Text(t('닫기', 'Close'))),
            FilledButton.icon(
                key: const Key('business-coupang-open'),
                onPressed: _busy || !_matches || !_notOrdered ? null : _open,
                icon: const Icon(Icons.open_in_new),
                label: Text(widget.offer == null
                    ? t('쿠팡에서 다른 상품 찾기', 'Find other products on Coupang')
                    : t('쿠팡에서 구매', 'Buy at Coupang'))),
          ]));
}
