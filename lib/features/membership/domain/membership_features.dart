/// Server capabilities are independent from a subscription's billing period.
/// UI hints only: financial RPCs and AI reservations still authorize on server.
class MembershipFeatures {
  const MembershipFeatures({
    required this.canManageCosts,
    required this.canManageSales,
    required this.canShareRequestPdf,
    required this.videoMonthlyLimit,
    required this.supplierLimit,
    this.requestMonthlyLimit,
  });

  factory MembershipFeatures.fromJson(Map<String, dynamic> json) {
    if (json['schema_version'] != 1 ||
        json['can_manage_costs'] is! bool ||
        json['can_manage_sales'] is! bool ||
        json['can_share_request_pdf'] is! bool ||
        json['video_monthly_limit'] is! int ||
        json['supplier_limit'] is! int ||
        (json['request_monthly_limit'] != null &&
            json['request_monthly_limit'] is! int)) {
      throw const FormatException('Invalid membership capabilities');
    }
    final video = json['video_monthly_limit'] as int;
    final suppliers = json['supplier_limit'] as int;
    final requests = json['request_monthly_limit'] as int?;
    if (video < 0 || suppliers < 0 || (requests != null && requests < 0)) {
      throw const FormatException('Invalid membership limits');
    }
    return MembershipFeatures(
      canManageCosts: json['can_manage_costs'] as bool,
      canManageSales: json['can_manage_sales'] as bool,
      canShareRequestPdf: json['can_share_request_pdf'] as bool,
      videoMonthlyLimit: video,
      supplierLimit: suppliers,
      requestMonthlyLimit: requests,
    );
  }

  final bool canManageCosts, canManageSales, canShareRequestPdf;
  final int videoMonthlyLimit, supplierLimit;
  final int? requestMonthlyLimit;
}
