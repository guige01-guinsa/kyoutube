import 'shopping_affiliate.dart';

/// Remaining review work; never changes verification or publication flags.
List<String> affiliateReviewTasks(Map<String, dynamic> row,
    {bool english = false, DateTime? now}) {
  String t(String ko, String en) => english ? en : ko;
  final tasks = <String>[];
  if (affiliateUri(
          row['program'] as String? ?? '', row['link'] as String? ?? '') ==
      null) {
    tasks
        .add(t('• 발급받은 제휴 링크를 등록하세요.', '• Add a valid issued affiliate link.'));
  }
  if ((row['ingredients'] as List? ?? []).isEmpty) {
    tasks.add(
        t('• 검색에 사용할 재료 이름을 입력하세요.', '• Enter ingredient names for matching.'));
  }
  if (row['program'] == 'coupang' &&
      (row['product_verified'] != true ||
          (row['specification'] as String? ?? '').trim().isEmpty)) {
    tasks.add(t('• 실제 상품을 열어 상품명과 규격을 확인하세요.',
        '• Open the actual product and verify its name and size.'));
  }
  if (row['mobile_allowed'] != true && row['web_allowed'] != true) {
    tasks.add(t('• 게시 가능한 위치를 확인하세요.', '• Confirm an allowed placement.'));
  }
  if ((row['review_note'] as String? ?? '').trim().length < 10) {
    tasks.add(t('• 사용 허용 근거와 확인일을 기록하세요.',
        '• Record the placement basis and review date.'));
  }
  final expiry = DateTime.tryParse(row['expires_at'] as String? ?? '');
  if (row['published'] == true &&
      (expiry == null || !expiry.isAfter(now ?? DateTime.now()))) {
    tasks.add(t('• 확인 기간이 지났습니다. 재검토 후 저장하세요.',
        '• The review has expired. Review and save again.'));
  }
  if (tasks.isEmpty) {
    tasks.add(row['published'] == true
        ? t('실제 노출 확인에서 구매 화면을 확인하세요.',
            'Check the purchase screen using live visibility.')
        : t('검토 항목이 입력되었습니다. 수정에서 공개 여부를 결정하세요.',
            'Review fields are complete. Open Edit to decide whether to publish.'));
  }
  return tasks;
}
