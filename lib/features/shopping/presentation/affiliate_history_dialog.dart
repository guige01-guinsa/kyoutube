import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/localization/localized_text.dart';
import '../../auth/application/auth_providers.dart';
import '../data/shopping_affiliate_repository.dart';

class AffiliateHistoryDialog extends ConsumerStatefulWidget {
  const AffiliateHistoryDialog({super.key, required this.id});
  final String id;
  @override
  ConsumerState<AffiliateHistoryDialog> createState() =>
      _AffiliateHistoryDialogState();
}

class _AffiliateHistoryDialogState
    extends ConsumerState<AffiliateHistoryDialog> {
  static const _labels = {
    'title': '상품명',
    'specification': '규격·브랜드',
    'ingredients': '재료 이름·별칭 (쉼표로 구분)',
    'category': '식자재 분류',
    'brand': '상품 브랜드',
    'source_code': '관리 번호',
    'link': '제휴 링크 또는 상품 태그 영상 주소',
    'published': '공개 중',
    'deleted_at': '휴지통',
    'product_verified': '연결된 상품과 규격을 직접 확인했습니다.',
    'review_note': '사용 허용 근거·확인일',
    'mobile_allowed': '모바일 앱 게시 가능 확인',
    'web_allowed': '웹 게시 가능 확인',
  };
  static const _actions = {
    'create': '신규 등록',
    'update': '수정',
    'delete': '휴지통으로 이동',
    'restore': '복원',
    'publish': '선택 공개',
    'hide': '공개 중단'
  };
  final _rows = <Map<String, dynamic>>[];
  bool _busy = false, _more = true, _failed = false;
  @override
  void initState() {
    super.initState();
    Future.microtask(_load);
  }

  Future<void> _load() async {
    final account = ref.read(activeAccountIdProvider);
    setState(() {
      _busy = true;
      _failed = false;
    });
    try {
      final rows = await ref.read(shoppingAffiliateRepositoryProvider).history(
          widget.id,
          before: _rows.isEmpty ? null : _rows.last['id'] as int);
      if (mounted && ref.read(activeAccountIdProvider) == account) {
        setState(() {
          _rows.addAll(rows);
          _more = rows.length == 25;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _failed = true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
          scrollable: true,
          title: const LocalizedText('변경 이력'),
          content: SizedBox(
              width: 600,
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                for (final row in _rows)
                  ExpansionTile(
                      title: LocalizedText(
                          '${row['created_at']} · ${context.tr(_actions[row['action']] ?? '수정')}'),
                      subtitle: Text(row['actor_id'] as String? ?? '—'),
                      children: [
                        for (final key in const [
                          'title',
                          'specification',
                          'ingredients',
                          'category',
                          'brand',
                          'source_code',
                          'link',
                          'published',
                          'deleted_at',
                          'product_verified',
                          'review_note',
                          'mobile_allowed',
                          'web_allowed'
                        ])
                          if ((row['before_data'] as Map?)?[key].toString() !=
                              (row['after_data'] as Map)[key].toString())
                            ListTile(
                                title: LocalizedText(_labels[key]!),
                                subtitle: SelectableText(
                                    '${(row['before_data'] as Map?)?[key] ?? '—'} → ${(row['after_data'] as Map)[key]}')),
                      ]),
                if (_busy) const LinearProgressIndicator(),
                if (_failed) const LocalizedText('불러오지 못했습니다. 다시 시도해 주세요.'),
                if (_more)
                  TextButton(
                      onPressed: _busy ? null : _load,
                      child: const LocalizedText('더 불러오기')),
              ])),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(context),
                child: const LocalizedText('닫기'))
          ]);
}
