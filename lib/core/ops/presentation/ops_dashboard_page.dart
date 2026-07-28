import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../config/env.dart';
import '../../firebase/firebase_messaging_service.dart';
import '../../widgets/centered_state_view.dart';
import '../ops_report_formatter.dart';
import '../ops_monitor_service.dart';

class OpsDashboardPage extends StatefulWidget {
  const OpsDashboardPage({super.key});

  @override
  State<OpsDashboardPage> createState() => _OpsDashboardPageState();
}

class _OpsDashboardPageState extends State<OpsDashboardPage> {
  static const List<int> _aiMetricWindows = <int>[7, 30, 90];
  static const double _helpfulRateTarget = 85.0;

  Future<OpsBackendCheckResult>? _backendCheck;
  Future<AiQualityMetrics>? _aiMetrics;
  Future<Map<String, int>>? _eventCounters;
  int _selectedAiMetricWindowDays = 30;

  @override
  void initState() {
    super.initState();
    _aiMetrics = _loadAiQualityMetrics(_selectedAiMetricWindowDays);
    _eventCounters = OpsMonitorService.getEventCounters();
  }

  Future<OpsBackendCheckResult> _runBackendCheck() async {
    final uri = Uri.parse('${Env.supabaseUrl}/rest/v1/recipes_public')
        .replace(queryParameters: <String, String>{
      'select': 'id',
      'limit': '1',
    });

    try {
      final rows = await Supabase.instance.client
          .from('recipes_public')
          .select('id')
          .limit(1)
          .timeout(const Duration(seconds: 5));
      return OpsBackendCheckResult(
        label: 'Supabase 연결 확인',
        status: 'ok',
        details: 'REST 응답 수신: ${jsonEncode(rows)}',
      );
    } catch (error) {
      return OpsBackendCheckResult(
        label: 'Supabase 연결 확인',
        status: 'failed',
        details: 'REST: $error\nURI: $uri',
      );
    }
  }

  Future<AiQualityMetrics> _loadAiQualityMetrics(int windowDays) async {
    final user = Supabase.instance.client.auth.currentUser;
    if (user == null) {
      return AiQualityMetrics.requiresAuth(windowDays: windowDays);
    }

    final since = DateTime.now().subtract(Duration(days: windowDays)).toUtc();
    final sinceIso = since.toIso8601String();

    try {
      final usageRows = await Supabase.instance.client
          .from('ai_usage_logs')
          .select('status, meta')
          .eq('endpoint', 'ai_recipe_assistant')
          .gte('created_at', sinceIso)
          .limit(1000);

      final feedbackRows = await Supabase.instance.client
          .from('ai_assistant_feedback')
          .select('liked')
          .gte('created_at', sinceIso)
          .limit(1000);

      final usageList = List<Map<String, dynamic>>.from(usageRows as List);
      final feedbackList =
          List<Map<String, dynamic>>.from(feedbackRows as List);

      final totalCalls = usageList.length;
      final degradedCalls = usageList
          .where((Map<String, dynamic> row) => row['status'] == 'degraded')
          .length;
      final blockedCalls = usageList
          .where((Map<String, dynamic> row) => row['status'] == 'blocked')
          .length;

      final Map<String, int> errorCodeCounts = <String, int>{};
      for (final Map<String, dynamic> row in usageList) {
        final dynamic metaRaw = row['meta'];
        if (metaRaw is! Map) {
          continue;
        }

        final dynamic codeRaw = metaRaw['error_code'];
        if (codeRaw == null) {
          continue;
        }

        final code = codeRaw.toString().trim();
        if (code.isEmpty) {
          continue;
        }
        errorCodeCounts[code] = (errorCodeCounts[code] ?? 0) + 1;
      }

      final totalFeedback = feedbackList.length;
      final likedFeedback = feedbackList
          .where((Map<String, dynamic> row) => row['liked'] == true)
          .length;

      return AiQualityMetrics(
        windowDays: windowDays,
        totalCalls: totalCalls,
        degradedCalls: degradedCalls,
        blockedCalls: blockedCalls,
        totalFeedback: totalFeedback,
        likedFeedback: likedFeedback,
        errorCodeCounts: errorCodeCounts,
      );
    } catch (error) {
      return AiQualityMetrics.error(
        error.toString(),
        windowDays: windowDays,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final opsState = OpsMonitorService.state.value;
    final fcmState = FirebaseMessagingService.debugState.value;

    return Scaffold(
      appBar: AppBar(
        title: const Text('운영 대시보드'),
        actions: <Widget>[
          IconButton(
            onPressed: () {
              setState(() {
                _backendCheck = _runBackendCheck();
                _aiMetrics = _loadAiQualityMetrics(_selectedAiMetricWindowDays);
                _eventCounters = OpsMonitorService.getEventCounters();
              });
            },
            icon: const Icon(Icons.refresh),
            tooltip: '연결 확인',
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: <Widget>[
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(
                    '앱 상태',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  const SizedBox(height: 8),
                  Text('환경: ${opsState.appEnv}'),
                  Text('현재 단계: ${opsState.phase}'),
                  Text('준비 완료: ${opsState.isReady ? '예' : '아니오'}'),
                  Text(
                    '최근 시작 시간: ${opsState.startupTotalMs == null ? '-' : '${opsState.startupTotalMs}ms'}',
                  ),
                  if (opsState.lastStartupMeasuredAt != null)
                    Text(
                      '측정 시각: ${opsState.lastStartupMeasuredAt!.toLocal()}',
                    ),
                  Text('시작 오류: ${opsState.startupError ?? '-'}'),
                  Text('최근 오류: ${opsState.recentErrors.length}건'),
                  if (opsState.startupPhaseDurationsMs.isNotEmpty) ...<Widget>[
                    const SizedBox(height: 8),
                    Text(
                      '시작 단계별 소요 시간',
                      style: Theme.of(context).textTheme.titleSmall,
                    ),
                    const SizedBox(height: 6),
                    ...opsState.startupPhaseDurationsMs.entries.map(
                      (entry) => Text('${entry.key}: ${entry.value}ms'),
                    ),
                  ],
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(
                    '네트워크 재시도 지표',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  const SizedBox(height: 8),
                  FutureBuilder<Map<String, int>>(
                    future: _eventCounters,
                    builder: (BuildContext context,
                        AsyncSnapshot<Map<String, int>> snapshot) {
                      if (snapshot.connectionState != ConnectionState.done) {
                        return const Padding(
                          padding: EdgeInsets.symmetric(vertical: 12),
                          child: Center(child: CircularProgressIndicator()),
                        );
                      }

                      if (snapshot.hasError) {
                        return Text('지표 조회 실패: ${snapshot.error}');
                      }

                      final counters = snapshot.data ?? const <String, int>{};
                      final youtubeSearchSuccess =
                          counters['youtube.search.success'] ?? 0;
                      final youtubeSearchFailed = counters.entries
                          .where(
                            (entry) => entry.key.startsWith(
                              'youtube.search.failed.',
                            ),
                          )
                          .fold<int>(0, (sum, entry) => sum + entry.value);
                      return Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: <Widget>[
                          _buildRetryMetricRow(
                            label: '홈 목록',
                            clicked:
                                counters['network.retry.home_list.clicked'] ??
                                    0,
                            success:
                                counters['network.retry.home_list.success'] ??
                                    0,
                            successWithin2: counters[
                                    'network.retry.home_list.success_within_2'] ??
                                0,
                          ),
                          const SizedBox(height: 8),
                          _buildRetryMetricRow(
                            label: '레시피 상세',
                            clicked: counters[
                                    'network.retry.recipe_detail.clicked'] ??
                                0,
                            success: counters[
                                    'network.retry.recipe_detail.success'] ??
                                0,
                            successWithin2: counters[
                                    'network.retry.recipe_detail.success_within_2'] ??
                                0,
                          ),
                          const SizedBox(height: 8),
                          _buildRetryMetricRow(
                            label: '바로 요리 모드',
                            clicked:
                                counters['network.retry.quick_cook.clicked'] ??
                                    0,
                            success:
                                counters['network.retry.quick_cook.success'] ??
                                    0,
                            successWithin2: counters[
                                    'network.retry.quick_cook.success_within_2'] ??
                                0,
                          ),
                          const SizedBox(height: 12),
                          Text(
                            'Fallback 이벤트',
                            style: Theme.of(context).textTheme.titleSmall,
                          ),
                          const SizedBox(height: 4),
                          Text(
                            '목록 cache hit: ${counters['network.fetch.public_list.cache_hit'] ?? 0} | '
                            '목록 no-cache 실패: ${counters['network.fetch.public_list.fail_no_cache'] ?? 0}',
                          ),
                          Text(
                            '상세 cache hit: ${counters['network.fetch.recipe_detail.cache_hit'] ?? 0} | '
                            '상세 no-cache 실패: ${counters['network.fetch.recipe_detail.fail_no_cache'] ?? 0}',
                          ),
                          const SizedBox(height: 12),
                          Text(
                            '온보딩 이벤트',
                            style: Theme.of(context).textTheme.titleSmall,
                          ),
                          const SizedBox(height: 4),
                          Text(
                            'viewed: ${counters['onboarding.viewed'] ?? 0} | '
                            'next_step: ${counters['onboarding.next_step'] ?? 0} | '
                            'skipped: ${counters['onboarding.skipped'] ?? 0} | '
                            'completed: ${counters['onboarding.completed'] ?? 0}',
                          ),
                          const SizedBox(height: 12),
                          Text(
                            'YouTube 검색/가져오기 퍼널',
                            style: Theme.of(context).textTheme.titleSmall,
                          ),
                          const SizedBox(height: 4),
                          Text(
                            'search submitted (yt/public): '
                            '${counters['search.submitted.youtube'] ?? 0} / ${counters['search.submitted.public'] ?? 0}',
                          ),
                          Text(
                            'search success/failed: '
                            '$youtubeSearchSuccess / $youtubeSearchFailed',
                          ),
                          Text(
                            'result open clicked/success/failed: '
                            '${counters['youtube.result.open.clicked'] ?? 0} / '
                            '${counters['youtube.result.open.success'] ?? 0} / '
                            '${counters['youtube.result.open.failed'] ?? 0}',
                          ),
                          Text(
                            'import clicked/canceled/completed/failed: '
                            '${counters['youtube.import.clicked'] ?? 0} / '
                            '${counters['youtube.import.canceled'] ?? 0} / '
                            '${counters['youtube.import.completed'] ?? 0} / '
                            '${counters['youtube.import.failed'] ?? 0}',
                          ),
                        ],
                      );
                    },
                  ),
                  const SizedBox(height: 8),
                  OutlinedButton.icon(
                    onPressed: () {
                      setState(() {
                        _eventCounters = OpsMonitorService.getEventCounters();
                      });
                    },
                    icon: const Icon(Icons.analytics_outlined),
                    label: const Text('이벤트 지표 새로고침'),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(
                    'AI 품질 지표',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: _aiMetricWindows.map((int days) {
                      return ChoiceChip(
                        label: Text('$days일'),
                        selected: _selectedAiMetricWindowDays == days,
                        onSelected: (bool selected) {
                          if (!selected) {
                            return;
                          }
                          setState(() {
                            _selectedAiMetricWindowDays = days;
                            _aiMetrics = _loadAiQualityMetrics(days);
                          });
                        },
                      );
                    }).toList(),
                  ),
                  const SizedBox(height: 8),
                  FutureBuilder<AiQualityMetrics>(
                    future: _aiMetrics,
                    builder: (BuildContext context,
                        AsyncSnapshot<AiQualityMetrics> snapshot) {
                      if (snapshot.connectionState != ConnectionState.done) {
                        return const Padding(
                          padding: EdgeInsets.symmetric(vertical: 12),
                          child: Center(child: CircularProgressIndicator()),
                        );
                      }

                      if (snapshot.hasError) {
                        return Text('지표 조회 실패: ${snapshot.error}');
                      }

                      final metrics = snapshot.data ??
                          const AiQualityMetrics(
                            windowDays: 30,
                            totalCalls: 0,
                            degradedCalls: 0,
                            blockedCalls: 0,
                            totalFeedback: 0,
                            likedFeedback: 0,
                          );

                      final sortedErrorEntries = metrics.errorCodeCounts.entries
                          .toList()
                        ..sort((a, b) => b.value.compareTo(a.value));

                      if (metrics.requiresAuth) {
                        return const Text('로그인 후 개인 AI 지표를 확인할 수 있습니다.');
                      }

                      if (metrics.errorMessage != null) {
                        return Text('지표 조회 실패: ${metrics.errorMessage}');
                      }

                      return Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: <Widget>[
                          Text('AI 호출 수: ${metrics.totalCalls}'),
                          Text('저하 응답 수: ${metrics.degradedCalls}'),
                          Text('예산 차단 수: ${metrics.blockedCalls}'),
                          Text('피드백 수: ${metrics.totalFeedback}'),
                          const SizedBox(height: 6),
                          Text('집계 기간: 최근 ${metrics.windowDays}일'),
                          Text('도움률: ${metrics.helpfulRateLabel}'),
                          Text('저하율: ${metrics.degradedRateLabel}'),
                          Text('차단율: ${metrics.blockedRateLabel}'),
                          const SizedBox(height: 8),
                          _buildHelpfulRateBadge(metrics),
                          const SizedBox(height: 8),
                          Text(
                            'errorCode 분포',
                            style: Theme.of(context).textTheme.titleSmall,
                          ),
                          const SizedBox(height: 4),
                          if (metrics.errorCodeCounts.isEmpty)
                            const Text('기록된 errorCode가 없습니다.')
                          else
                            ...sortedErrorEntries.map(
                              (entry) => Text('${entry.key}: ${entry.value}건'),
                            ),
                        ],
                      );
                    },
                  ),
                  const SizedBox(height: 8),
                  OutlinedButton.icon(
                    onPressed: () {
                      setState(() {
                        _aiMetrics = _loadAiQualityMetrics(
                          _selectedAiMetricWindowDays,
                        );
                      });
                    },
                    icon: const Icon(Icons.query_stats),
                    label: const Text('지표 재집계'),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(
                    'Supabase 연결',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  const SizedBox(height: 8),
                  SelectableText('URL: ${Env.supabaseUrl}'),
                  const SelectableText('환경: ${Env.appEnv}'),
                  const SizedBox(height: 12),
                  FilledButton.icon(
                    onPressed: () {
                      setState(() {
                        _backendCheck = _runBackendCheck();
                      });
                    },
                    icon: const Icon(Icons.network_check),
                    label: const Text('연결 다시 확인'),
                  ),
                  if (_backendCheck != null) ...<Widget>[
                    const SizedBox(height: 12),
                    FutureBuilder<OpsBackendCheckResult>(
                      future: _backendCheck,
                      builder: (BuildContext context,
                          AsyncSnapshot<OpsBackendCheckResult> snapshot) {
                        if (snapshot.connectionState != ConnectionState.done) {
                          return const Center(
                            child: Padding(
                              padding: EdgeInsets.all(12),
                              child: CircularProgressIndicator(),
                            ),
                          );
                        }

                        if (snapshot.hasError) {
                          return CenteredStateView(
                            icon: Icons.cloud_off_outlined,
                            title: '연결 확인 실패',
                            message: snapshot.error.toString(),
                          );
                        }

                        final result = snapshot.data!;
                        return DecoratedBox(
                          decoration: BoxDecoration(
                            color: Theme.of(context)
                                .colorScheme
                                .surfaceContainerHighest,
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Padding(
                            padding: const EdgeInsets.all(12),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: <Widget>[
                                Text(result.label),
                                const SizedBox(height: 4),
                                Text('상태: ${result.status}'),
                                const SizedBox(height: 4),
                                Text(result.details),
                              ],
                            ),
                          ),
                        );
                      },
                    ),
                  ],
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(
                    'FCM 상태',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  const SizedBox(height: 8),
                  Text('지원 플랫폼: ${fcmState.isSupportedPlatform ? '예' : '아니오'}'),
                  Text('초기화됨: ${fcmState.isInitialized ? '예' : '아니오'}'),
                  Text('권한 상태: ${fcmState.permissionStatus}'),
                  Text('토큰: ${fcmState.token == null ? '없음' : '발급됨'}'),
                  if (fcmState.errorMessage != null) ...<Widget>[
                    const SizedBox(height: 8),
                    Text(
                      '오류: ${fcmState.errorMessage}',
                      style:
                          TextStyle(color: Theme.of(context).colorScheme.error),
                    ),
                  ],
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Row(
                    children: <Widget>[
                      Expanded(
                        child: Text(
                          '최근 오류',
                          style: Theme.of(context).textTheme.titleMedium,
                        ),
                      ),
                      IconButton(
                        onPressed: opsState.recentErrors.isEmpty
                            ? null
                            : () async {
                                await OpsMonitorService.clearRecentErrors();
                                if (mounted) {
                                  setState(() {});
                                }
                                if (context.mounted) {
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    const SnackBar(
                                      content: Text('최근 오류를 지웠습니다.'),
                                    ),
                                  );
                                }
                              },
                        icon: const Icon(Icons.delete_outline),
                        tooltip: '최근 오류 지우기',
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  if (opsState.recentErrors.isEmpty)
                    const Text('저장된 오류가 없습니다.')
                  else
                    ...opsState.recentErrors.map((event) {
                      return Padding(
                        padding: const EdgeInsets.only(bottom: 8),
                        child: DecoratedBox(
                          decoration: BoxDecoration(
                            color: Theme.of(context)
                                .colorScheme
                                .surfaceContainerHighest,
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Padding(
                            padding: const EdgeInsets.all(12),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: <Widget>[
                                Text(
                                    '${event.timestamp.toLocal()} | ${event.source}'),
                                const SizedBox(height: 4),
                                Text(event.message),
                              ],
                            ),
                          ),
                        ),
                      );
                    }),
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: <Widget>[
              OutlinedButton.icon(
                onPressed: () async {
                  await OpsMonitorService.clearRecentErrors();
                  if (mounted) {
                    setState(() {});
                  }
                  if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('최근 오류를 지웠습니다.')),
                    );
                  }
                },
                icon: const Icon(Icons.delete_outline),
                label: const Text('최근 오류 지우기'),
              ),
              OutlinedButton.icon(
                onPressed: () async {
                  OpsBackendCheckResult? backendResult;
                  if (_backendCheck != null) {
                    try {
                      backendResult = await _backendCheck!;
                    } catch (_) {
                      backendResult = null;
                    }
                  }
                  final counters = await OpsMonitorService.getEventCounters();

                  final report = OpsReportFormatter.buildStandardReport(
                    opsState: OpsMonitorService.state.value,
                    fcmState: FirebaseMessagingService.debugState.value,
                    backendStatus: backendResult?.status,
                    backendDetails: backendResult?.details,
                    eventCounters: counters,
                  );
                  await Clipboard.setData(ClipboardData(text: report));
                  if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('운영 리포트를 복사했습니다.')),
                    );
                  }
                },
                icon: const Icon(Icons.copy),
                label: const Text('리포트 복사'),
              ),
              OutlinedButton.icon(
                onPressed: () => context.pop(),
                icon: const Icon(Icons.arrow_back),
                label: const Text('돌아가기'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class OpsBackendCheckResult {
  const OpsBackendCheckResult({
    required this.label,
    required this.status,
    required this.details,
  });

  final String label;
  final String status;
  final String details;
}

class AiQualityMetrics {
  const AiQualityMetrics({
    required this.windowDays,
    required this.totalCalls,
    required this.degradedCalls,
    required this.blockedCalls,
    required this.totalFeedback,
    required this.likedFeedback,
    this.errorCodeCounts = const <String, int>{},
    this.requiresAuth = false,
    this.errorMessage,
  });

  const AiQualityMetrics.requiresAuth({required this.windowDays})
      : totalCalls = 0,
        degradedCalls = 0,
        blockedCalls = 0,
        totalFeedback = 0,
        likedFeedback = 0,
        errorCodeCounts = const <String, int>{},
        requiresAuth = true,
        errorMessage = null;

  factory AiQualityMetrics.error(String message, {required int windowDays}) {
    return AiQualityMetrics(
      windowDays: windowDays,
      totalCalls: 0,
      degradedCalls: 0,
      blockedCalls: 0,
      totalFeedback: 0,
      likedFeedback: 0,
      errorMessage: message,
    );
  }

  final int windowDays;
  final int totalCalls;
  final int degradedCalls;
  final int blockedCalls;
  final int totalFeedback;
  final int likedFeedback;
  final Map<String, int> errorCodeCounts;
  final bool requiresAuth;
  final String? errorMessage;

  double get helpfulRateValue {
    if (totalFeedback <= 0) {
      return 0;
    }
    return (likedFeedback / totalFeedback) * 100;
  }

  String get helpfulRateLabel => _asPercent(likedFeedback, totalFeedback);
  String get degradedRateLabel => _asPercent(degradedCalls, totalCalls);
  String get blockedRateLabel => _asPercent(blockedCalls, totalCalls);

  String _asPercent(int numerator, int denominator) {
    if (denominator <= 0) {
      return '0.0%';
    }

    final rate = (numerator / denominator) * 100;
    return '${rate.toStringAsFixed(1)}%';
  }
}

extension on _OpsDashboardPageState {
  Widget _buildRetryMetricRow({
    required String label,
    required int clicked,
    required int success,
    required int successWithin2,
  }) {
    String asPercent(int numerator, int denominator) {
      if (denominator <= 0) {
        return '0.0%';
      }
      final rate = (numerator / denominator) * 100;
      return '${rate.toStringAsFixed(1)}%';
    }

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(
            label,
            style: Theme.of(context).textTheme.titleSmall,
          ),
          const SizedBox(height: 4),
          Text('재시도 클릭: $clicked'),
          Text('복구 성공: $success (${asPercent(success, clicked)})'),
          Text(
            '2회 이내 복구: $successWithin2 (${asPercent(successWithin2, clicked)})',
          ),
        ],
      ),
    );
  }

  Widget _buildHelpfulRateBadge(AiQualityMetrics metrics) {
    final hasFeedback = metrics.totalFeedback > 0;
    final meetsTarget =
        metrics.helpfulRateValue >= _OpsDashboardPageState._helpfulRateTarget;

    final Color backgroundColor;
    final Color foregroundColor;
    final String label;

    if (!hasFeedback) {
      backgroundColor = Theme.of(context).colorScheme.surfaceContainerHighest;
      foregroundColor = Theme.of(context).colorScheme.onSurfaceVariant;
      label =
          '피드백 데이터 부족 (목표 ${_OpsDashboardPageState._helpfulRateTarget.toStringAsFixed(0)}%)';
    } else if (meetsTarget) {
      backgroundColor = Colors.green.withValues(alpha: 0.14);
      foregroundColor = Colors.green.shade800;
      label =
          '목표 달성 ${metrics.helpfulRateLabel} (목표 ${_OpsDashboardPageState._helpfulRateTarget.toStringAsFixed(0)}%)';
    } else {
      backgroundColor = Colors.orange.withValues(alpha: 0.16);
      foregroundColor = Colors.orange.shade900;
      label =
          '개선 필요 ${metrics.helpfulRateLabel} (목표 ${_OpsDashboardPageState._helpfulRateTarget.toStringAsFixed(0)}%)';
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: backgroundColor,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: foregroundColor,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}
