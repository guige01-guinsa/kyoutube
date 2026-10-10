import 'package:flutter_test/flutter_test.dart';
import 'package:k_youtube/features/operations/domain/growth_overview.dart';

Map<String, dynamic> sample() => {
      'schema_version': 1,
      'intake_enabled': false,
      'delivery_enabled': false,
      'pending': 4,
      'confirmed': 3,
      'withdrawn': 1,
      'confirmed_7d': 2,
      'queued': 1,
      'failed': 0,
      'sent': 8,
      'attempts_today': 2,
      'daily_limit': 90,
      'monthly_limit': 2500,
      'channels': [
        {'source': 'youtube', 'applications': 7, 'confirmed': 3}
      ],
      'roles': [],
    };
void main() {
  test('shows confirmed applicants separately from pending and sending state',
      () {
    final data = GrowthOverview.fromJson(sample());
    expect(data.count('confirmed'), 3);
    expect(data.count('pending'), 4);
    expect(data.intakeEnabled, isFalse);
    expect(data.deliveryEnabled, isFalse);
    expect(data.channels.single['applications'], 7);
  });
  test('malformed or missing server data never becomes healthy zero counts',
      () {
    for (final data in [
      <String, dynamic>{},
      {...sample(), 'confirmed': null},
      {...sample(), 'queued': -1},
      {
        ...sample(),
        'channels': [
          {'source': 'youtube'}
        ]
      }
    ]) {
      expect(() => GrowthOverview.fromJson(data), throwsFormatException);
    }
  });
}
