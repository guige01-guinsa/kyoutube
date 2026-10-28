import 'dart:math';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../application/marketing_providers.dart';

typedef StandardRow = Map<String, dynamic>;

String standardRequestId() {
  final random = Random.secure();
  final bytes = List<int>.generate(16, (_) => random.nextInt(256));
  bytes[6] = (bytes[6] & 15) | 64;
  bytes[8] = (bytes[8] & 63) | 128;
  final value = bytes.map((v) => v.toRadixString(16).padLeft(2, '0')).join();
  return '${value.substring(0, 8)}-${value.substring(8, 12)}-${value.substring(12, 16)}-${value.substring(16, 20)}-${value.substring(20)}';
}

class StandardStudioRepository {
  Future<StandardRow> command(String action, StandardRow values) async {
    final result =
        await Supabase.instance.client.rpc('story_standard', params: {
      'p_action': action,
      'p': values,
    });
    return Map<String, dynamic>.from(result as Map);
  }

  Future<String> preview(String path, {required bool sample}) {
    final pattern =
        sample ? r'^[0-9a-f-]{36}/sample\.wav$' : r'^[0-9a-f-]{36}/ko\.mp4$';
    if (!RegExp(pattern).hasMatch(path)) throw StateError('invalid_preview');
    return Supabase.instance.client.storage
        .from(sample ? 'story-standard-samples' : 'story-previews')
        .createSignedUrl(path, 300);
  }
}

final standardStudioRepositoryProvider =
    Provider((ref) => StandardStudioRepository());
final standardStudioProvider =
    FutureProvider.autoDispose<StandardRow>((ref) async {
  if (!await ref.watch(marketingAdminProvider.future)) {
    throw StateError('marketing_admin_required');
  }
  return ref.watch(standardStudioRepositoryProvider).command('overview', {});
});

List<StandardRow> standardRows(StandardRow data, String key) =>
    (data[key] as List? ?? [])
        .map((e) => Map<String, dynamic>.from(e as Map))
        .toList();

String standardError(Object error) {
  final code = error is PostgrestException ? error.message : '';
  if (code.contains('STORY_DEMO_REQUIRED')) {
    return '개인정보 없는 실제 앱 화면이 준비되지 않았습니다. 제작비는 예약하지 않았습니다.';
  }
  if (code.contains('STORY_SAMPLE_REQUIRED')) {
    return '현재 원고의 시험 음성을 듣고 확인해 주세요.';
  }
  if (code.contains('STORY_PREVIEW_REQUIRED')) {
    return '현재 영상의 재생과 내용을 먼저 확인해 주세요.';
  }
  if (code.contains('STORY_NOT_READY')) {
    return '한국어 1분 제작 서버 연결 또는 비용 설정이 필요합니다.';
  }
  if (code.contains('STORY_MONTHLY_LIMIT') ||
      code.contains('STORY_BUDGET_LIMIT')) {
    return '제작 예산 또는 일일 작업 한도에 도달했습니다. 자동으로 한도를 올리지 않습니다.';
  }
  if (code.contains('ADMIN_MFA_REQUIRED')) return '관리자 추가 인증이 필요합니다.';
  if (code.contains('STORY_CONFLICT') || code.contains('STORY_QUOTE_CHANGED')) {
    return '원고나 비용 설정이 변경됐습니다. 새로고침 후 확인해 주세요.';
  }
  if (code.contains('STORY_INVALID')) return '원고 길이·출처·장면 구성을 확인해 주세요.';
  return '요청 결과가 불확실합니다. 새 요청을 만들지 말고 같은 요청을 확인하세요.';
}

String standardStatus(String value) =>
    const {
      'planning': '음식 기획',
      'draft_queued': '자료 조사 대기',
      'drafting': '자료 조사·원고 작성 중',
      'draft': '원고 검토',
      'sample_queued': '시험 음성 대기',
      'sampling': '시험 음성 제작 중',
      'sample_review': '시험 음성 확인',
      'sample_approved': '영상 제작 준비',
      'render_queued': '영상 제작 대기',
      'rendering': '영상 제작 중',
      'preview': '완성 영상 검토',
      'upload_queued': '비공개 업로드 대기',
      'uploading': '비공개 업로드 중',
      'uploaded': '비공개 업로드 완료',
      'needs_review': '작업 중단 · 진단 필요',
    }[value] ??
    '상태 확인 필요';
