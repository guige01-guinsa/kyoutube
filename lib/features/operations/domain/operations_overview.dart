class OperationsOverview {
  OperationsOverview.fromJson(Map<String, dynamic> json)
      : generatedAt = DateTime.parse(json['generated_at'] as String),
        days = (json['days'] as num).toInt(),
        requests = Map<String, dynamic>.from(json['requests'] as Map),
        usage = Map<String, dynamic>.from(json['usage'] as Map),
        costs = json['costs'] == null
            ? null
            : Map<String, dynamic>.from(json['costs'] as Map),
        failures = (json['failures'] as List)
            .map((e) => Map<String, dynamic>.from(e as Map))
            .toList();
  final DateTime generatedAt;
  final int days;
  final Map<String, dynamic> requests, usage;
  final Map<String, dynamic>? costs;
  final List<Map<String, dynamic>> failures;
  int count(String key) => (requests[key] as num?)?.toInt() ?? 0;
  int usageCount(String key) => (usage[key] as num?)?.toInt() ?? 0;
  double? get aiSuccessRate => count('ai_attempts') == 0
      ? null
      : 100 * count('ai_successes') / count('ai_attempts');
  double? get aiP95Seconds =>
      (requests['ai_p95_ms'] as num?)?.toDouble() == null
          ? null
          : (requests['ai_p95_ms'] as num) / 1000;
  double? get totalCost {
    final ai = costs?['openai_usd'] as num?;
    final other = costs?['other_usd'] as num?;
    return ai == null || other == null ? null : (ai + other).toDouble();
  }

  double? get budgetRatio {
    final budget = costs?['budget_usd'] as num?;
    return totalCost == null || budget == null || budget <= 0
        ? null
        : totalCost! / budget;
  }

  List<String> get alerts => [
        if (count('fatal_errors') > 0) 'fatalAlert',
        if (count('ai_attempts') >= 10 && aiSuccessRate! < 90) 'aiAlert',
        if ((aiP95Seconds ?? 0) >= 60) 'latencyAlert',
        if (usageCount('stale_reservations') > 0) 'usageAlert',
        if (budgetRatio != null && budgetRatio! >= 0.95)
          'budgetCritical'
        else if (budgetRatio != null && budgetRatio! >= 0.7)
          'budgetAlert',
        if (costs == null || totalCost == null) 'costUnknown',
        if (costs?['updated_at'] is String &&
            generatedAt.difference(
                    DateTime.parse(costs!['updated_at'] as String)) >
                const Duration(days: 7))
          'costStale',
      ];
}

typedef OpsText = ({String ko, String en});
const opsCopy = <String, OpsText>{
  'days': (ko: '일', en: 'd'),
  'title': (ko: '서비스 운영 현황', en: 'Service operations'),
  'intro': (
    ko: '서버 요청·앱 오류와 이번 달 비용을 확인합니다.',
    en: 'Review server requests, reported app errors and monthly costs.'
  ),
  'unavailable': (
    ko: '운영 현황을 불러오지 못했습니다. 관리자 권한과 서버 적용 상태를 확인해 주세요.',
    en: 'Operations data is unavailable. Check administrator access and server deployment.'
  ),
  'retry': (ko: '다시 불러오기', en: 'Reload'),
  'requests': (ko: '서버 요청', en: 'Server requests'),
  'failures': (ko: '서버 실패', en: 'Server failures'),
  'rejected': (ko: '인증·한도 등 거절', en: 'Rejected requests'),
  'client': (ko: '앱 오류 보고', en: 'App error reports'),
  'success': (ko: 'AI 성공률', en: 'AI success rate'),
  'latency': (ko: 'AI 응답 P95', en: 'AI response P95'),
  'latencyNote': (
    ko: 'P95는 관측 요청 95%가 이 시간 안에 응답했다는 뜻입니다. AI 성공률에서 인증·사용 한도 거절은 제외합니다.',
    en: 'P95 means 95% of observed requests responded within this time. AI success rate excludes authentication and quota rejections.'
  ),
  'empty': (
    ko: '선택 기간에 수집된 서버 요청이 없습니다. 정상 상태를 의미하지는 않습니다.',
    en: 'No server requests were collected in this period. This does not establish that the service is healthy.'
  ),
  'coverage': (
    ko: '앱 오류는 로그인 이후 보고된 항목이며, 수집 실패·오프라인·시작 전 장애는 누락될 수 있습니다.',
    en: 'App errors are reports from signed-in sessions. Offline, startup and collection failures may be missing.'
  ),
  'alerts': (ko: '확인할 항목', en: 'Needs attention'),
  'fatalAlert': (
    ko: '치명적 앱 오류 보고가 있습니다.',
    en: 'Fatal app errors were reported.'
  ),
  'aiAlert': (
    ko: 'AI 성공률이 90% 미만입니다. 실패 분류를 확인해 주세요.',
    en: 'AI success rate is below 90%. Review failure categories.'
  ),
  'latencyAlert': (
    ko: 'AI 응답 P95가 60초 이상입니다.',
    en: 'AI response P95 is at least 60 seconds.'
  ),
  'usageAlert': (
    ko: '15분 이상 완료되지 않은 AI 사용 예약이 있습니다.',
    en: 'AI usage reservations have remained open for over 15 minutes.'
  ),
  'budgetCritical': (
    ko: '기록된 비용이 월 예산의 95% 이상입니다.',
    en: 'Recorded costs have reached at least 95% of the monthly budget.'
  ),
  'budgetAlert': (
    ko: '기록된 비용이 월 예산의 70% 이상입니다.',
    en: 'Recorded costs have reached at least 70% of the monthly budget.'
  ),
  'costUnknown': (
    ko: '비용이 미입력 또는 일부만 입력되어 예산 잔액을 판단할 수 없습니다.',
    en: 'Costs are missing or partial; remaining budget cannot be determined.'
  ),
  'costStale': (
    ko: '비용 기록이 7일 이상 갱신되지 않았습니다.',
    en: 'Cost records have not been updated for over seven days.'
  ),
  'breakdown': (ko: '실패 분류', en: 'Failure categories'),
  'noFailures': (
    ko: '수집된 실패 기록이 없습니다.',
    en: 'No failure records were collected.'
  ),
  'usage': (ko: '이번 달 AI 사용 기록 · UTC', en: 'AI usage this month · UTC'),
  'input': (ko: '입력 토큰', en: 'Input tokens'),
  'output': (ko: '출력 토큰', en: 'Output tokens'),
  'unknownUsage': (ko: '토큰 확인 불가 요청', en: 'Requests with unknown token usage'),
  'usageNote': (
    ko: '성공·실패 요청에 기록된 토큰 합계입니다. 시간 초과 등으로 사용량을 받지 못한 요청은 무료로 간주하지 않습니다. 요금 청구서와 대조해 주세요.',
    en: 'Totals include recorded tokens for successful and failed attempts. Missing usage, including timeouts, does not mean a free request. Reconcile with billing statements.'
  ),
  'costs': (ko: '이번 달 실제 비용 기록 · USD', en: 'Recorded monthly costs · USD'),
  'costNote': (
    ko: '공급자 청구 화면에서 확인한 누적액을 입력합니다. 자동 청구 연동이나 지출 차단 기능은 아닙니다. 미입력 항목은 비워 두세요.',
    en: 'Enter month-to-date amounts from provider billing. Billing is not automatically synced and spending is not automatically blocked. Leave unknown amounts blank.'
  ),
  'aiCost': (ko: 'OpenAI 누적 비용 (USD)', en: 'OpenAI cost to date (USD)'),
  'otherCost': (
    ko: '기타 운영 누적 비용 (USD)',
    en: 'Other operating costs to date (USD)'
  ),
  'budget': (ko: '월 예산 (USD)', en: 'Monthly budget (USD)'),
  'total': (ko: '총 기록 비용', en: 'Total recorded cost'),
  'remaining': (ko: '예산 잔액', en: 'Remaining budget'),
  'save': (ko: '비용 기록 저장', en: 'Save cost record'),
  'saved': (ko: '비용 기록을 저장했습니다.', en: 'Cost record saved.'),
  'saveFailed': (
    ko: '저장하지 못했습니다. 입력값은 유지됩니다.',
    en: 'Could not save. Your entries are retained.'
  ),
  'invalid': (
    ko: '0 이상의 금액을 입력해 주세요. 예산은 0보다 커야 합니다. 소수점은 마침표(.)로 입력하세요.',
    en: 'Enter non-negative amounts and a positive budget. Use a dot (.) as the decimal separator.'
  ),
  'unknown': (ko: '확인 불가', en: 'Unknown'),
  'asOf': (ko: '기록 갱신', en: 'Record updated'),
};
