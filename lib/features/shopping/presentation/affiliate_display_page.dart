import '../../../core/localization/app_localizations.dart';
import '../../auth/presentation/account_recovery_actions.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../auth/application/auth_providers.dart';
import '../../membership/application/membership_providers.dart';
import '../data/shopping_affiliate_repository.dart';
import 'shopping_affiliate_panel.dart';
import 'coupang_disclosure.dart';

/// Uses the customer-facing RPC and card, never an admin draft preview.
class AffiliateDisplayPage extends ConsumerStatefulWidget {
  const AffiliateDisplayPage(
      {super.key, required this.ingredient, this.expectedId});
  final String ingredient;
  final String? expectedId;
  @override
  ConsumerState<AffiliateDisplayPage> createState() =>
      _AffiliateDisplayPageState();
}

class _AffiliateDisplayPageState extends ConsumerState<AffiliateDisplayPage> {
  late final _search = TextEditingController(text: widget.ingredient);
  late String _query = widget.ingredient.trim();
  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  void _refresh() {
    setState(() => _query = _search.text.trim());
    ref.invalidate(shoppingAffiliatesProvider(_query));
  }

  @override
  Widget build(BuildContext context) {
    String t(String ko, String en) =>
        AppLocalizations(Localizations.localeOf(context)).bilingual(ko, en);
    final allowed = ref.watch(activeAccountIdProvider) != null &&
        ref.watch(membershipInfoProvider).valueOrNull?.isAdmin == true;
    return Scaffold(
      appBar: AppBar(title: Text(t('실제 노출 확인', 'Check live visibility'))),
      bottomNavigationBar:
          allowed ? CoupangDisclosureFooter(ingredients: [_query]) : null,
      body: !allowed
          ? Center(child: AccountRecoveryActions(onRecovered: _refresh))
          : ListView(padding: const EdgeInsets.all(20), children: [
              Text(t('현재 기기에서 회원에게 공개되는 상품을 조회합니다. 초안이나 만료된 상품은 표시하지 않습니다.',
                  'Shows products available to customers on this platform. Drafts and expired products are excluded.')),
              const SizedBox(height: 16),
              TextField(
                  controller: _search,
                  maxLength: 120,
                  decoration:
                      InputDecoration(labelText: t('재료 이름', 'Ingredient name')),
                  onSubmitted: (_) => _refresh()),
              FilledButton.icon(
                  onPressed: _refresh,
                  icon: const Icon(Icons.refresh),
                  label: Text(t('조회·새로고침', 'Search / refresh'))),
              const SizedBox(height: 16),
              if (_query.isNotEmpty) ...[
                ref.watch(shoppingAffiliatesProvider(_query)).when(
                    loading: () => const LinearProgressIndicator(),
                    error: (_, __) => const SizedBox.shrink(),
                    data: (offers) => offers.isEmpty ||
                            (widget.expectedId != null &&
                                !offers.any(
                                    (offer) => offer.id == widget.expectedId))
                        ? Text(t(
                            '선택한 상품이 표시되지 않습니다. 공개 상태, 현재 기기의 게시 허용, 확인 만료일과 재료 이름을 확인하세요.',
                            'The selected product is not visible. Check publication, placement permission for this platform, review expiry and ingredient names.'))
                        : const SizedBox.shrink()),
                ShoppingAffiliatePanel(
                    ingredient: _query, showCoupangDisclosure: false),
              ],
            ]),
    );
  }
}
