import '../../../core/localization/localized_text.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../auth/application/auth_providers.dart';
import '../../membership/application/membership_providers.dart';
import '../data/coupang_partners_repository.dart';
import 'shopping_assistant_dialogs.dart';

class CoupangProductDialog extends ConsumerStatefulWidget {
  const CoupangProductDialog({super.key});
  @override
  ConsumerState<CoupangProductDialog> createState() =>
      _CoupangProductDialogState();
}

class _CoupangProductDialogState extends ConsumerState<CoupangProductDialog> {
  final _keyword = TextEditingController();
  final _url = TextEditingController();
  late final String? _account;
  List<CoupangProduct> _products = [];
  String _searchedKeyword = '';
  String? _error;
  bool _busy = false, _searched = false;
  String t(String ko, String en) => shopText(context, ko, en);
  bool get _current =>
      mounted &&
      _account != null &&
      ref.read(activeAccountIdProvider) == _account &&
      ref.read(membershipInfoProvider).valueOrNull?.isAdmin == true;

  @override
  void initState() {
    super.initState();
    _account = ref.read(activeAccountIdProvider);
  }

  @override
  void dispose() {
    _keyword.dispose();
    _url.dispose();
    super.dispose();
  }

  String message(Object error) {
    final code = error is CoupangPartnersException ? error.code : '';
    return switch (code) {
      'not_configured' => t('쿠팡 API 연결 준비가 필요합니다. 운영자에게 연결 설정을 요청하세요.',
          'Coupang API setup is required. Ask the operator to configure it.'),
      'admin_mfa_required' => t('관리자 2단계 인증을 완료한 뒤 다시 시도하세요.',
          'Complete administrator two-step verification and try again.'),
      'unauthorized' ||
      'admin_required' =>
        t('관리자 계정으로 다시 로그인하세요.', 'Sign in again as an administrator.'),
      'rate_limited' || 'upstream_rate_limited' => t(
          '쿠팡 조회 한도에 도달했습니다. 잠시 후 다시 시도하세요. 일일 한도라면 다음 날 이용해 주세요.',
          'The request limit was reached. Try later, or tomorrow if the daily limit was reached.'),
      'coupang_access_denied' || 'coupang_request_rejected' => t(
          '쿠팡에서 요청을 승인하지 않았습니다. 파트너스 API 사용 권한과 연결 설정을 확인하세요.',
          'Coupang declined the request. Check Partners API access and connection settings.'),
      'invalid_input' => t('검색어 또는 쿠팡 상품 상세 주소를 확인하세요.',
          'Check the keyword or Coupang product URL.'),
      _ => t('쿠팡 정보를 불러오지 못했습니다. 다시 시도하거나 기존 발급 링크를 직접 등록하세요.',
          'Could not load Coupang data. Retry or add an existing issued link manually.'),
    };
  }

  Future<void> _search() async {
    if (_busy || !_current) return;
    final keyword = _keyword.text.trim();
    if (keyword.isEmpty || keyword.length > 80) {
      setState(() =>
          _error = message(const CoupangPartnersException('invalid_input')));
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
      _products = [];
      _searched = false;
    });
    try {
      final products =
          await ref.read(coupangPartnersRepositoryProvider).search(keyword);
      if (!_current) return;
      setState(() {
        _products = products;
        _searched = true;
        _searchedKeyword = keyword;
      });
    } catch (error) {
      if (_current) setState(() => _error = message(error));
    } finally {
      if (_current) setState(() => _busy = false);
    }
  }

  Future<void> _link({CoupangProduct? product}) async {
    if (_busy || !_current) return;
    final url = product?.url ?? _url.text.trim();
    if (!isCoupangProductUrl(url)) {
      setState(() =>
          _error = message(const CoupangPartnersException('invalid_input')));
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final link =
          await ref.read(coupangPartnersRepositoryProvider).deeplink(url);
      if (!mounted || !_current) return;
      Navigator.of(context).pop(<String, dynamic>{
        'program': 'coupang',
        'title': product?.title ?? '',
        'link': link,
        'ingredients': product == null ? <String>[] : [_searchedKeyword],
        'source_code': product?.id ?? '',
        'image_url': product?.imageUrl ?? '',
        'published': false,
        'product_verified': false,
        'mobile_allowed': false,
        'web_allowed': false,
      });
    } catch (error) {
      if (_current) setState(() => _error = message(error));
    } finally {
      if (_current) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    ref.watch(membershipInfoProvider);
    ref.watch(activeAccountIdProvider);
    return AlertDialog(
      scrollable: true,
      insetPadding: const EdgeInsets.all(16),
      title: Text(t('쿠팡 상품 검색·링크 생성', 'Coupang products and links')),
      content: SizedBox(
          width: 520,
          child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(t(
                    '상품을 검색하거나 쿠팡 상품 상세 주소를 붙여 넣으세요. 생성한 링크는 편집기에서 확인 후 저장합니다.',
                    'Search products or paste a Coupang product URL. Review the generated link in the editor before saving.')),
                const SizedBox(height: 12),
                TextField(
                    key: const ValueKey('coupang-keyword'),
                    controller: _keyword,
                    enabled: !_busy,
                    maxLength: 80,
                    onSubmitted: (_) => _search(),
                    decoration: InputDecoration(
                        labelText:
                            t('재료·상품 검색어', 'Ingredient / product keyword'))),
                FilledButton.icon(
                    onPressed: _busy ? null : _search,
                    icon: const Icon(Icons.search),
                    label: Text(t('쿠팡 상품 검색', 'Search Coupang'))),
                const SizedBox(height: 12),
                TextField(
                    key: const ValueKey('coupang-product-url'),
                    controller: _url,
                    enabled: !_busy,
                    maxLength: 2048,
                    maxLines: 3,
                    minLines: 1,
                    decoration: InputDecoration(
                        labelText: t('쿠팡 상품 상세 주소', 'Coupang product URL'),
                        hintText: 'https://www.coupang.com/vp/products/…')),
                OutlinedButton.icon(
                    onPressed: _busy ? null : () => _link(),
                    icon: const Icon(Icons.link),
                    label: Text(
                        t('주소로 제휴 링크 생성', 'Create affiliate link from URL'))),
                if (_busy) const LinearProgressIndicator(),
                if (_error != null)
                  Padding(
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      child: Text(_error!,
                          key: const ValueKey('coupang-api-error'))),
                if (_searched && _products.isEmpty)
                  Text(t('검색 결과가 없습니다. 다른 검색어를 입력하세요.',
                      'No results. Try another keyword.')),
                if (_products.isNotEmpty) ...[
                  const SizedBox(height: 12),
                  Text(t(
                      '가격은 조회 시점의 참고 정보입니다. 옵션·규격·최종 가격과 배송비는 쿠팡에서 다시 확인하세요.',
                      'Prices are a snapshot. Check options, size, final price and shipping on Coupang.')),
                  for (final product in _products)
                    Card(
                        child: Padding(
                            padding: const EdgeInsets.all(12),
                            child: Row(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  _ProductImage(imageUrl: product.imageUrl),
                                  const SizedBox(width: 12),
                                  Expanded(
                                      child: Column(
                                          crossAxisAlignment:
                                              CrossAxisAlignment.stretch,
                                          children: [
                                        Text(product.title),
                                        if (product.price != null)
                                          LocalizedText(
                                              '${product.price!.toStringAsFixed(0)} KRW'),
                                        OutlinedButton(
                                            onPressed: _busy
                                                ? null
                                                : () => _link(product: product),
                                            child: Text(t('링크 생성 후 검토',
                                                'Generate link and review'))),
                                      ])),
                                ]))),
                ],
              ])),
      actions: [
        TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: Text(t('닫기', 'Close')))
      ],
    );
  }
}

class _ProductImage extends StatelessWidget {
  const _ProductImage({this.imageUrl});
  final String? imageUrl;

  @override
  Widget build(BuildContext context) => Semantics(
      label: '쿠팡 상품 사진',
      image: true,
      child: ClipRRect(
          borderRadius: BorderRadius.circular(8),
          child: SizedBox(
              width: 72,
              height: 72,
              child: imageUrl == null
                  ? const ColoredBox(
                      color: Color(0xfff5f2f4),
                      child: Icon(Icons.shopping_bag_outlined))
                  : Image.network(imageUrl!,
                      fit: BoxFit.cover,
                      errorBuilder: (_, __, ___) => const ColoredBox(
                          color: Color(0xfff5f2f4),
                          child: Icon(Icons.shopping_bag_outlined))))));
}
