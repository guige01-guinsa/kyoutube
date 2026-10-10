import 'package:flutter_test/flutter_test.dart';
import 'package:k_youtube/features/operations/domain/operations_overview.dart';

Map<String, dynamic> fixture(
        {Map<String, dynamic>? costs, int attempts = 0, int successes = 0}) =>
    {
      'generated_at': '2026-09-12T12:00:00Z',
      'days': 7,
      'requests': {'ai_attempts': attempts, 'ai_successes': successes},
      'usage': {},
      'costs': costs,
      'failures': [],
    };
void main() {
  test(
      'no observations and missing cost never imply 100 percent success or free use',
      () {
    final data = OperationsOverview.fromJson(fixture());
    expect(data.aiSuccessRate, isNull);
    expect(data.totalCost, isNull);
    expect(data.budgetRatio, isNull);
    expect(data.alerts, contains('costUnknown'));
    final partial = OperationsOverview.fromJson(fixture(
        costs: {'openai_usd': 12, 'other_usd': null, 'budget_usd': 700}));
    expect(partial.totalCost, isNull);
  });
  test(
      'real zero costs remain zero and failures use observed eligible attempts',
      () {
    final data = OperationsOverview.fromJson(fixture(
        attempts: 10,
        successes: 8,
        costs: {'openai_usd': 0, 'other_usd': 0, 'budget_usd': 700}));
    expect(data.totalCost, 0);
    expect(data.aiSuccessRate, 80);
    expect(data.alerts, contains('aiAlert'));
    expect(data.alerts, isNot(contains('costUnknown')));
  });
  test('low sample failure rate does not trigger alert, stale high cost does',
      () {
    final data =
        OperationsOverview.fromJson(fixture(attempts: 1, successes: 0, costs: {
      'openai_usd': 670,
      'other_usd': 0,
      'budget_usd': 700,
      'updated_at': '2026-09-01T00:00:00Z'
    }));
    expect(data.alerts, isNot(contains('aiAlert')));
    expect(data.alerts, containsAll(['budgetCritical', 'costStale']));
  });
}
