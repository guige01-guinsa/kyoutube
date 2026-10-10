import '../../../core/localization/localized_text.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../shopping/data/shopping_assistant_repository.dart';
import '../../shopping/domain/shopping_assistant.dart';
import '../domain/public_supplier.dart';
import '../domain/supplier_catalog.dart';
import 'supplier_business_page.dart';

Future<void> openSupplierSource(
    BuildContext context, WidgetRef ref, String url) async {
  final uri = shoppingProductUri(url);
  try {
    if (uri == null || !await ref.read(shoppingLinkLauncherProvider)(uri)) {
      throw StateError('Invalid source');
    }
  } catch (_) {
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(catalogText(context, '링크를 열지 못했습니다. 주소를 확인해 주세요.',
              'Could not open the link. Check the address.'))));
    }
  }
}

class PublicSupplierCard extends ConsumerWidget {
  const PublicSupplierCard({super.key, required this.supplier, this.action});
  final PublicSupplier supplier;
  final Widget? action;
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    String t(String ko, String en) => catalogText(context, ko, en);
    final s = supplier;
    final en = Localizations.localeOf(context).languageCode != 'ko';
    final kind = switch (s.businessKind) {
      'marketplace' =>
        t('중개 플랫폼 · 실제 판매자 확인', 'Marketplace · check the actual seller'),
      'distributor' =>
        t('계약 납품 · 상담 필요', 'Contract supplier · contact to confirm'),
      _ => t('온라인 식자재몰', 'Online ingredient store')
    };
    return Card(
        margin: const EdgeInsets.symmetric(vertical: 8),
        child: Padding(
            padding: const EdgeInsets.all(18),
            child:
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(t('공개 정보 업체', 'Public information listing'),
                  style: Theme.of(context).textTheme.labelMedium),
              const SizedBox(height: 6),
              Text(s.name, style: Theme.of(context).textTheme.titleLarge),
              Text(kind),
              const SizedBox(height: 8),
              Wrap(spacing: 8, runSpacing: 4, children: [
                for (final c in s.categories)
                  Chip(label: Text(supplierCategoryLabel(c, en)))
              ]),
              Text(s.products),
              const SizedBox(height: 8),
              Text(s.shippingNote),
              if (s.phone.isNotEmpty) Text(s.phone),
              const SizedBox(height: 8),
              LocalizedText('${t('자료 확인일', 'Sources checked')}: ${s.checkedOn}',
                  style: Theme.of(context).textTheme.bodySmall),
              Text(
                  t('공식 공개 자료를 정리한 정보입니다. 업체 직접 등록·사업자 인증·가격 견적이 아닙니다.',
                      'Compiled from official public sources. Not supplier registration, business verification or a price quote.'),
                  style: Theme.of(context).textTheme.bodySmall),
              Wrap(spacing: 8, runSpacing: 4, children: [
                TextButton.icon(
                    onPressed: () =>
                        openSupplierSource(context, ref, s.website),
                    icon: const Icon(Icons.open_in_new),
                    label: Text(t('공식 홈페이지', 'Official website'))),
                if (action != null) action!,
              ]),
              ExpansionTile(
                  tilePadding: EdgeInsets.zero,
                  title: Text(t('확인한 출처', 'Source references')),
                  children: [
                    for (final url in s.sourceUrls)
                      Align(
                          alignment: Alignment.centerLeft,
                          child: TextButton(
                              onPressed: () =>
                                  openSupplierSource(context, ref, url),
                              child: Text(url, softWrap: true)))
                  ])
            ])));
  }
}
