import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:k_youtube/features/business/application/business_coupang_service.dart';
import 'business_coupang_test.dart'
    show buyer, purchase, MemoryOffers, product, pumpCoupang, confirm;

void main() {
  testWidgets(
      'business fallback confirmation checks approval and never records an order',
      (tester) async {
    final repo = buyer(),
        catalog = MemoryOffers()..offers = [],
        opened = <Uri>[];
    await pumpCoupang(tester, repo, catalog, opened);
    final button = find.text('쿠팡에서 다른 상품 찾기');
    await tester.ensureVisible(button);
    await tester.tap(button);
    await tester.pumpAndSettle();
    final open = find.byKey(const Key('business-coupang-open'));
    expect(tester.widget<FilledButton>(open).onPressed, isNull);
    await confirm(tester);
    await tester.ensureVisible(open);
    await tester.tap(open);
    await tester.pumpAndSettle();
    expect(opened.single.queryParameters, {'q': '국간장'});
    expect(repo.writes, 0);
    expect(repo.data['request']!.status, 'approved');
    expect(tester.takeException(), isNull);
  });

  test(
      'general search opens only an unchanged approved request with no affiliate and writes nothing',
      () async {
    final repo = buyer();
    final catalog = MemoryOffers()..offers = [];
    final opened = <Uri>[];
    final service = BusinessCoupangService(repo, catalog, (u) async {
      opened.add(u);
      return true;
    });
    final before = repo.data['request'];
    await service.open(
        request: purchase(), lineIndex: 0, isCurrent: () => true);
    expect(opened.single.host, 'www.coupang.com');
    expect(opened.single.queryParameters, {'q': '국간장'});
    expect(repo.data['request'], same(before));
  });
  test('general search preserves approval, account and fresh product checks',
      () async {
    for (final status in ['draft', 'review', 'sent', 'received', 'cancelled']) {
      final repo = buyer()..data['request'] = purchase(status: status);
      final service =
          BusinessCoupangService(repo, MemoryOffers()..offers = [], (_) async {
        fail('must not launch');
      });
      await expectLater(
          service.open(
              request: purchase(), lineIndex: 0, isCurrent: () => true),
          throwsA(BusinessCoupangFailure.access));
    }
    final repo = buyer();
    final catalog = MemoryOffers()..offers = [];
    final service = BusinessCoupangService(repo, catalog, (_) async {
      fail('must not launch');
    });
    await expectLater(
        service.open(request: purchase(), lineIndex: 0, isCurrent: () => false),
        throwsA(BusinessCoupangFailure.account));
    catalog.beforeFind = () async {
      repo.data['request'] = purchase(status: 'cancelled');
    };
    await expectLater(
        service.open(request: purchase(), lineIndex: 0, isCurrent: () => true),
        throwsA(BusinessCoupangFailure.access));
    repo.data['request'] = purchase();
    catalog.beforeFind = null;
    catalog.offers = [product()];
    await expectLater(
        service.open(request: purchase(), lineIndex: 0, isCurrent: () => true),
        throwsA(BusinessCoupangFailure.unavailable));
  });
}
