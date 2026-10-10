enum ShoppingStage { prepare, active, records }

ShoppingStage shoppingStage(String? value) => switch (value) {
      'active' => ShoppingStage.active,
      'records' || 'history' || 'completed' => ShoppingStage.records,
      _ => ShoppingStage.prepare,
    };

String shoppingPath(
        {ShoppingStage stage = ShoppingStage.prepare,
        String? listId,
        String? view,
        String? requestId}) =>
    Uri(path: '/shopping', queryParameters: {
      'stage': stage.name,
      if (listId != null) 'list': listId,
      if (view != null) 'view': view,
      if (requestId != null) 'request': requestId,
    }).toString();

/// Preserve bookmarked links and notification targets during menu consolidation.
String? legacyShoppingRedirect(Uri uri) {
  final stage = switch (uri.path) {
    '/shopping-preparation' || '/shopping-assistant' => ShoppingStage.prepare,
    '/kitchen' => uri.queryParameters['tab'] == 'history'
        ? ShoppingStage.records
        : ShoppingStage.active,
    '/purchases' || '/supplier-requests' => switch (
          uri.queryParameters['stage']) {
        'active' => ShoppingStage.active,
        'completed' => ShoppingStage.records,
        _ => ShoppingStage.prepare,
      },
    '/supplier-request-ledger' => ShoppingStage.records,
    _ => null,
  };
  if (stage == null) return null;
  final view = switch (uri.path) {
    '/purchases' ||
    '/supplier-requests' ||
    '/supplier-request-ledger' =>
      'requests',
    '/kitchen' => 'lists',
    _ => null,
  };
  return shoppingPath(
      stage: stage,
      listId: uri.queryParameters['list'],
      view: view,
      requestId: uri.queryParameters['request']);
}

ShoppingStage businessShoppingStage(String status) => switch (status) {
      'review' || 'approved' || 'sent' => ShoppingStage.active,
      'received' || 'cancelled' => ShoppingStage.records,
      _ => ShoppingStage.prepare,
    };
