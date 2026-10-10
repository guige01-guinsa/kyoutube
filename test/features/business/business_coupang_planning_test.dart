import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:k_youtube/features/business/data/business_menu_fast_repository.dart';
import 'package:k_youtube/features/business/data/business_menu_repository.dart';
import 'package:k_youtube/features/shopping/data/shopping_affiliate_repository.dart';
import 'business_flow_test.dart' show MemoryBusiness, pumpBusiness;
import 'business_menu_fast_test.dart' show FastMemory;
import 'business_menu_test.dart' show MenuMemory;
import '../shopping/coupang_purchase_plan_test.dart' show PlannerOffers;
import '../workspace/workspace_reorganization_test.dart' show capturePreview;

void main() {
  setUpAll(() async {
    await (FontLoader('BusinessPreview')
          ..addFont(rootBundle.load('assets/fonts/NanumGothic-Regular.ttf')))
        .load();
  });
  testWidgets(
      'unmapped business ingredient can select Coupang and submit a draft plan, never buy before approval',
      (tester) async {
    final base =
        MemoryBusiness({'recipes.read', 'purchasing.read', 'purchasing.write'});
    final fast = FastMemory()..ready = false;
    final capture = GlobalKey();
    await tester.binding.setSurfaceSize(const Size(500, 1000));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await pumpBusiness(tester, base,
        initial: '/business-workspaces/shop/menu-fast',
        capture: capture,
        overrides: [
          businessMenuRepositoryProvider.overrideWithValue(MenuMemory(base)),
          businessMenuFastRepositoryProvider.overrideWithValue(fast),
          shoppingAffiliateRepositoryProvider
              .overrideWithValue(PlannerOffers()),
        ]);
    Future<void> tap(String text) async {
      final f = find.text(text);
      if (f.evaluate().isEmpty) {
        await tester.scrollUntilVisible(f, 250,
            scrollable: find.byType(Scrollable).first);
      }
      await tester.ensureVisible(f);
      await tester.pumpAndSettle();
      await tester.ensureVisible(f);
      await tester.pumpAndSettle();
      await tester.tap(f);
      await tester.pumpAndSettle();
    }

    await tester.tap(find.byType(CheckboxListTile).first);
    await tester.pumpAndSettle();
    await tap('재료·구매량 계산');
    await tap('이 상품으로 구매량 적용');
    expect(find.text('쿠팡 제휴 상품'), findsNothing);
    await tester.ensureVisible(find.text('소면 상품'));
    await tester.pumpAndSettle();
    await capturePreview(tester, capture, 'coupang-planning-business');
    expect(find.text('쿠팡에서 구매'), findsNothing);
    await tap('구매처·규격·환산·중복 요청·재고 예약을 확인했습니다.');
    await tap('업체별 초안 생성·재고 예약');
    expect(fast.calls, 1);
    final choice = fast.payloads.single['p_choices']['onion'];
    expect(choice['count'], 1);
    expect(choice['needed'], 800);
    expect(choice['unit'], 'g');
    expect(choice['offer']['purchase_pack']['amount'], 900);
    expect(tester.takeException(), isNull);
  });
}
