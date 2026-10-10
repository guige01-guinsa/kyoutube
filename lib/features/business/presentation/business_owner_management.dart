part of 'business_pages.dart';

Future<bool> _eraseBusinessRecord(BuildContext context, WidgetRef ref,
    String workspace, String kind, String id) async {
  final result = await manageOwnerRecord(context, ref,
      workspace: workspace, kind: kind, id: id);
  if (result == null || !context.mounted) return false;
  _refreshStock(ref, workspace);
  ref.invalidate(businessSuppliersProvider(workspace));
  ref.invalidate(businessSupplierProductsProvider);
  ref.invalidate(businessSupplierSnapshotProvider);
  return true;
}

Future<void> _manageStockIdentity(BuildContext context, WidgetRef ref,
    String workspace, BusinessStockItem item, bool conversion,
    {bool detail = false}) async {
  final result = await manageOwnerRecord(context, ref,
      workspace: workspace,
      kind: conversion ? 'stock_unit' : 'stock',
      id: item.id,
      currentUnit: item.unit);
  if (result == null || !context.mounted) return;
  _refreshStock(ref, workspace);
  if (detail) context.go('/business-workspaces/$workspace/inventory');
}
