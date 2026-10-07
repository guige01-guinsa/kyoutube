import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:url_launcher/url_launcher.dart';

import '../application/marketing_providers.dart';

class MarketingPage extends ConsumerStatefulWidget {
  const MarketingPage({super.key});

  @override
  ConsumerState<MarketingPage> createState() => _MarketingPageState();
}

class _MarketingPageState extends ConsumerState<MarketingPage> {
  String _topic = 'youtube';
  bool _busy = false;

  Future<void> _run(Future<void> Function() operation) async {
    setState(() => _busy = true);
    try {
      await operation();
      ref.invalidate(marketingCampaignsProvider);
    } catch (error) {
      if (mounted) {
        final details = error is FunctionException ? error.details : null;
        final message = details is Map && details['message'] is String
            ? details['message'] as String
            : '처리하지 못했습니다. 권한·연결 상태와 예약 시간을 확인하세요.';
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(message)));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _approve(Map<String, dynamic> campaign) async {
    final now = DateTime.now();
    final date = await showDatePicker(
      context: context,
      initialDate: now.add(const Duration(days: 1)),
      firstDate: now,
      lastDate: now.add(const Duration(days: 29)),
    );
    if (date == null || !mounted) return;
    final time = await showTimePicker(
      context: context,
      initialTime: const TimeOfDay(hour: 18, minute: 0),
    );
    if (time == null || !mounted) return;
    final scheduled = DateTime(
      date.year,
      date.month,
      date.day,
      time.hour,
      time.minute,
    );
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('검토 완료 · 예약 승인'),
        content: Text(
          '제목·설명·3개 장면을 확인하셨습니까?\n\n'
          '${DateFormat('yyyy-MM-dd HH:mm').format(scheduled)} (기기 시간) 이후 '
          '자동 업로드 작업이 실행됩니다. 영상은 24초 무음 카드 형식이며, '
          '기본값은 비공개 업로드입니다. 업로드 후 YouTube Studio에서 '
          '일부공개 또는 공개로 변경할 수 있습니다.',
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('돌아가기'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('승인'),
          ),
        ],
      ),
    );
    if (confirmed == true && mounted) {
      await _run(
        () => ref
            .read(marketingServiceProvider)
            .schedule(campaign['id'] as String, scheduled),
      );
    }
  }

  Future<void> _openVideo(String id) async {
    if (!RegExp(r'^[A-Za-z0-9_-]{11}$').hasMatch(id)) return;
    try {
      final opened = await launchUrl(
        Uri.https('www.youtube.com', '/watch', {'v': id}),
        mode: LaunchMode.externalApplication,
      );
      if (!opened) throw StateError('not_opened');
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('영상 페이지를 열 수 없습니다.')));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final admin = ref.watch(marketingAdminProvider);
    return Scaffold(
      appBar: AppBar(
        title: const Text('마케팅 자동화'),
        actions: <Widget>[
          IconButton(
            onPressed: _busy
                ? null
                : () {
                    ref.invalidate(marketingAdminProvider);
                    ref.invalidate(marketingCampaignsProvider);
                  },
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: admin.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (_, __) =>
            const Center(child: Text('마케팅 기능 배포 및 관리자 설정이 필요합니다.')),
        data: (allowed) => allowed
            ? _dashboard()
            : const Center(child: Text('마케팅 관리자만 이용할 수 있습니다.')),
      ),
    );
  }

  Widget _dashboard() {
    final campaigns = ref.watch(marketingCampaignsProvider);
    return ListView(
      padding: const EdgeInsets.all(20),
      children: <Widget>[
        const Text('앱 기능 홍보 초안 → 검토·예약 승인 → 영상 제작·업로드'),
        const SizedBox(height: 12),
        DropdownButtonFormField<String>(
          initialValue: _topic,
          decoration: const InputDecoration(labelText: '홍보 주제'),
          items: const <DropdownMenuItem<String>>[
            DropdownMenuItem(value: 'youtube', child: Text('3분 이내 요리 영상 검색')),
            DropdownMenuItem(value: 'shopping', child: Text('장보기 목록 정리')),
            DropdownMenuItem(
              value: 'ingredients',
              child: Text('보유 재료로 레시피 검색'),
            ),
          ],
          onChanged: _busy
              ? null
              : (value) => setState(() => _topic = value ?? _topic),
        ),
        const SizedBox(height: 12),
        FilledButton.icon(
          onPressed: _busy
              ? null
              : () => _run(
                  () => ref.read(marketingServiceProvider).generate(_topic),
                ),
          icon: const Icon(Icons.auto_awesome),
          label: Text(_busy ? '처리 중…' : 'AI 홍보 초안 생성'),
        ),
        const SizedBox(height: 12),
        const Text(
          '하루 최대 5회 생성. 예약은 최소 5분 뒤부터 가능합니다. '
          '운영 작업은 약 1시간 간격이며 실행이 지연될 수 있습니다. '
          'Shorts에서는 채널 프로필의 앱 링크를 안내합니다. '
          '조회·좋아요는 설치 수와 별도 지표입니다.',
        ),
        const SizedBox(height: 20),
        campaigns.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (_, __) => const Text('콘텐츠를 불러오지 못했습니다. 새로고침해 주세요.'),
          data: (rows) => rows.isEmpty
              ? const Text('첫 홍보 초안을 만들어 보세요.')
              : Column(children: rows.map(_campaignCard).toList()),
        ),
      ],
    );
  }

  Widget _campaignCard(Map<String, dynamic> row) {
    const labels = <String, String>{
      'draft': '검토 대기',
      'scheduled': '예약됨',
      'publishing': '업로드 중',
      'published': '업로드 완료',
      'failed': '실패',
      'needs_review': '채널에서 결과 확인 필요',
      'cancelled': '취소됨',
    };
    final status = row['status'] as String;
    final scenes = (row['scenes'] as List).cast<String>();
    final scheduled = DateTime.tryParse(row['scheduled_at'] as String? ?? '');
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            Text(
              row['title'] as String,
              style: Theme.of(context).textTheme.titleMedium,
            ),
            Text(labels[status] ?? status),
            if (scheduled != null)
              Text(
                '예약: ${DateFormat('yyyy-MM-dd HH:mm').format(scheduled.toLocal())} (기기 시간)',
              ),
            const SizedBox(height: 12),
            SelectableText(row['description'] as String),
            const Divider(),
            ...scenes.asMap().entries.map(
              (entry) => Padding(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: Text('장면 ${entry.key + 1} · 8초\n${entry.value}'),
              ),
            ),
            if (status == 'draft')
              FilledButton(
                onPressed: _busy ? null : () => _approve(row),
                child: const Text('검토 완료 · 예약 승인'),
              ),
            if (status == 'draft' || status == 'scheduled')
              TextButton(
                onPressed: _busy
                    ? null
                    : () => _run(
                        () => ref
                            .read(marketingServiceProvider)
                            .cancel(row['id'] as String),
                      ),
                child: const Text('취소'),
              ),
            if (status == 'published') ...<Widget>[
              Text('조회 ${row['views']} · 좋아요 ${row['likes']}'),
              if (row['metrics_at'] != null)
                Text('지표 갱신: ${row['metrics_at']}'),
              TextButton(
                onPressed: () => _openVideo(row['youtube_video_id'] as String),
                child: const Text('YouTube에서 확인'),
              ),
            ],
            if (status == 'failed' || status == 'needs_review')
              const Text('채널 업로드 결과와 운영 설정을 확인하세요. 중복 방지를 위해 자동 재시도하지 않습니다.'),
          ],
        ),
      ),
    );
  }
}
