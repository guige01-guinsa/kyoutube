import 'dart:math';
import 'dart:async';
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
  Future<bool> requestStart(String jobId) async {
    try {
      final response = await Supabase.instance.client.functions
          .invoke('story_studio_dispatch', body: {'job_id': jobId});
      return response.status == 200 &&
          response.data is Map &&
          response.data['state'] == 'requested';
    } catch (_) {
      // Approved queue entry remains intact. Never create another paid job.
      return false;
    }
  }

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
  final repository = ref.watch(standardStudioRepositoryProvider);
  Timer? timer;
  var disposed = false;
  ref.onDispose(() {
    disposed = true;
    timer?.cancel();
  });
  if (!await ref.watch(marketingAdminProvider.future)) {
    throw StateError('marketing_admin_required');
  }
  final result = await repository.command('overview', {});
  if (!disposed &&
      standardRows(result, 'projects').any((p) => [
            'draft_queued',
            'drafting',
            'sample_queued',
            'sampling',
            'render_queued',
            'rendering',
            'upload_queued',
            'uploading'
          ].contains(p['status']))) {
    timer = Timer(const Duration(seconds: 3), ref.invalidateSelf);
  }
  return result;
});

String standardPipelineTiming(StandardRow artifact) {
  final elapsed = artifact['end_to_end_ms'];
  if (elapsed is num &&
      elapsed >= 0 &&
      artifact['privacy'] == 'private' &&
      artifact['youtube_id'] is String) {
    final met = artifact['target_ms'] == 180000 &&
        elapsed <= 180000 &&
        artifact['target_met'] == true;
    return '요청 접수 → 비공개 업로드 ${(elapsed / 1000).ceil()}초 · ${met ? '3분 목표 달성' : elapsed > 180000 ? '3분 목표 초과' : '목표 달성 미확인'}';
  }
  if (artifact['timing_scope'] == 'approved_request_to_private_upload') {
    return artifact['pipeline_state'] == 'duration_review_required'
        ? '영상 길이가 3분 이상입니다. 계속 업로드할지 확인이 필요합니다.'
        : '영상 제작 완료 · 비공개 업로드 완료 후 전체 소요 시간을 확인합니다.';
  }
  return artifact['production_ms'] is num
      ? '영상 처리 ${((artifact['production_ms'] as num) / 1000).ceil()}초 · 비공개 업로드 전체 시간은 별도 확인'
      : '전체 소요 시간 확인 필요';
}

List<StandardRow> standardRows(StandardRow data, String key) =>
    (data[key] as List? ?? [])
        .map((e) => Map<String, dynamic>.from(e as Map))
        .toList();

String? standardPipelineProgress(StandardRow project, DateTime now) {
  if (!['render_queued', 'rendering', 'upload_queued', 'uploading']
      .contains(project['status'])) {
    return null;
  }
  final raw = (project['source_receipt'] as Map?)?['pipeline_started_at'];
  final start = raw is String ? DateTime.tryParse(raw) : null;
  if (start == null) return null;
  final seconds = max(0, now.toUtc().difference(start.toUtc()).inSeconds);
  return '요청 접수 후 $seconds초 · ${seconds > 180 ? '3분 목표 초과' : '대기 시간 포함'}';
}

String standardError(Object error) {
  final code = error is PostgrestException ? error.message : '';
  if (code.contains('STORY_FAST_NOT_READY')) {
    return '빠른 제작 서버가 아직 준비되지 않았습니다. 기존 검토용 제작을 이용할 수 있습니다.';
  }
  if (code.contains('STORY_PRIVATE_UPLOAD_CONFIRMATION_REQUIRED')) {
    return '제작 후 비공개 업로드까지 진행한다는 승인이 필요합니다.';
  }
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
    return '한국어 제작 서버 연결 또는 비용 설정이 필요합니다.';
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
