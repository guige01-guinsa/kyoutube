class OperationsAlert {
  OperationsAlert(Map<String, dynamic> value)
      : id = (value['id'] as num).toInt(),
        code = value['code'] as String,
        severity = value['severity'] as String,
        isRead = value['is_read'] == true,
        createdAt = DateTime.parse(value['created_at'] as String),
        detail = Map<String, dynamic>.from(value['detail'] as Map? ?? {});
  final int id;
  final String code;
  final String severity;
  final bool isRead;
  final DateTime createdAt;
  final Map<String, dynamic> detail;

  String title(bool en) {
    final pair = titles[code];
    return pair == null
        ? (en ? 'Operations check' : '운영 확인')
        : (en ? pair.$2 : pair.$1);
  }

  String action(bool en) {
    final pair = actions[code];
    return pair == null
        ? (en ? 'Open the operations dashboard.' : '운영 현황을 확인해 주세요.')
        : (en ? pair.$2 : pair.$1);
  }

  String measurement(bool en) {
    String number(String key) =>
        (detail[key] as num?)?.toStringAsFixed(1) ?? '—';
    switch (code) {
      case 'ai_success':
        return '${number('success_percent')}% · ${detail['attempts'] ?? 0} ${en ? 'attempts / hour' : '건 / 1시간'}';
      case 'server_errors':
        return '${number('failure_percent')}% · ${detail['requests'] ?? 0} ${en ? 'requests / hour' : '건 / 1시간'}';
      case 'ai_latency':
        return 'P95 ${number('p95_seconds')} ${en ? 'seconds' : '초'}';
      case 'database_budget':
        return '${number('percent')}% (${en ? 'configured DB budget' : '설정한 DB 용량 기준'})';
      case 'database_connections':
        return '${number('percent')}% · ${detail['connections'] ?? 0} ${en ? 'DB connections' : 'DB 연결'}';
      case 'monthly_cost':
        return '\$${number('total_usd')} / \$${number('budget_usd')}';
      default:
        return '';
    }
  }

  static const titles = <String, (String, String)>{
    'ai_success': ('AI 생성 성공률', 'AI generation success'),
    'server_errors': ('서버 오류율', 'Server error rate'),
    'ai_latency': ('AI 응답 지연', 'AI response latency'),
    'telemetry_missing': ('서버 관측 자료 없음', 'Server telemetry missing'),
    'database_budget': ('DB 용량 확장 검토', 'Review database capacity'),
    'database_connections': ('DB 연결 여유 확인', 'Review database connections'),
    'monthly_cost': ('월 운영 예산 확인', 'Review monthly budget'),
    'cost_data': ('비용 자료 갱신 필요', 'Cost update required'),
  };
  static const actions = <String, (String, String)>{
    'ai_success': (
      '실패 원인과 입력 자료를 확인하세요. 서버 확장만으로 해결되지 않을 수 있습니다.',
      'Review failures and source evidence. More server capacity may not resolve this.'
    ),
    'server_errors': (
      '오류 분류와 최근 배포를 확인하세요.',
      'Review error categories and recent deployments.'
    ),
    'ai_latency': (
      'AI 공급자 지연·재시도·요청 집중을 확인하세요.',
      'Review provider latency, retries and request bursts.'
    ),
    'telemetry_missing': (
      '관측 DB·함수 배포와 이벤트 수집을 확인하세요.',
      'Check telemetry deployment and event collection.'
    ),
    'database_budget': (
      '오래된 로그·저장량 추세를 확인한 뒤 용량 변경을 검토하세요. 실제 디스크 잔량 측정은 아닙니다.',
      'Review retention and growth before increasing capacity. This is not actual free disk space.'
    ),
    'database_connections': (
      '연결 풀·느린 쿼리를 확인한 뒤 컴퓨트 확장을 검토하세요.',
      'Review pooling and slow queries before increasing compute.'
    ),
    'monthly_cost': (
      '실제 청구와 사용량을 확인하고 예산을 검토하세요.',
      'Review actual bills, usage and budget.'
    ),
    'cost_data': (
      '운영 현황에서 당월 누적 비용을 갱신하세요. 자동 청구 연동은 아직 없습니다.',
      'Update month-to-date costs in Operations. Billing is not synchronized automatically.'
    ),
  };
}
