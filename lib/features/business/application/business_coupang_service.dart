import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../shopping/data/shopping_affiliate_repository.dart';
import '../../shopping/domain/shopping_affiliate.dart';
import '../../shopping/domain/shopping_assistant.dart';
import '../../shopping/domain/coupang_purchase_plan.dart';
import '../data/business_repository.dart';
import '../domain/business_coupang.dart';
import '../domain/business_workspace.dart';

enum BusinessCoupangFailure {
  changed,
  unavailable,
  access,
  account,
  busy,
  open
}

/// Read-only boundary: no request transitions, receipts, stock or personal writes.
class BusinessCoupangService {
  BusinessCoupangService(this.business, this.affiliates, this.launch);
  final BusinessRepository business;
  final ShoppingAffiliateRepository affiliates;
  final Future<bool> Function(Uri) launch;
  bool _busy = false;

  Future<void> open({
    required BusinessRecord request,
    required int lineIndex,
    ShoppingAffiliate? offer,
    required bool Function() isCurrent,
  }) async {
    if (_busy) throw BusinessCoupangFailure.busy;
    final expected = snapshotBusinessPurchase(request);
    final selected = offer == null
        ? null
        : ShoppingAffiliate(Map<String, dynamic>.from(offer.data));
    _busy = true;
    void checkAccount() {
      if (!isCurrent()) throw BusinessCoupangFailure.account;
    }

    Future<void> checkRequest() async {
      final context = await business.context(request.workspace);
      checkAccount();
      final latest = await business.record(request.workspace, request.id);
      checkAccount();
      if (businessCoupangBlock(context, latest) != null) {
        throw BusinessCoupangFailure.access;
      }
      if (!sameBusinessPurchase(expected, latest)) {
        throw BusinessCoupangFailure.changed;
      }
    }

    try {
      checkAccount();
      await checkRequest();
      final line = businessCoupangLines(expected)
          .where((l) => l.index == lineIndex)
          .firstOrNull;
      if (line == null) throw BusinessCoupangFailure.changed;
      final plan = CoupangPurchasePlan.parse(
          (expected.data['lines'] as List)[lineIndex]['coupang']);
      if (plan != null &&
          (selected == null ||
              !plan.matches(selected) ||
              line.quantity != plan.count ||
              line.unit != plan.pack.label)) {
        throw BusinessCoupangFailure.changed;
      }
      final visible = businessCoupangOffers(await affiliates.find(line.name));
      checkAccount();
      if (selected == null
          ? visible.isNotEmpty
          : !visible.any((o) => sameCoupangOffer(o, selected))) {
        throw BusinessCoupangFailure.unavailable;
      }
      // Recheck after the product lookup as another employee may change approval.
      await checkRequest();
      checkAccount();
      final uri = selected?.uri ??
          shoppingSearchUri(ShoppingSearchStore.coupang, line.name);
      if (!await launch(uri)) throw BusinessCoupangFailure.open;
    } finally {
      _busy = false;
    }
  }
}

final businessCoupangLauncherProvider =
    Provider<Future<bool> Function(Uri)>((ref) => (uri) => launchUrl(uri,
        mode: LaunchMode.externalApplication,
        // Fresh server checks are asynchronous. Same-tab web navigation avoids
        // popup blocking; Back returns to the saved, unchanged request.
        webOnlyWindowName: '_self'));

final businessCoupangServiceProvider = Provider.autoDispose((ref) =>
    BusinessCoupangService(
        ref.watch(businessRepositoryProvider),
        ref.watch(shoppingAffiliateRepositoryProvider),
        ref.watch(businessCoupangLauncherProvider)));
