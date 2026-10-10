class GrowthOverview {
  GrowthOverview.fromJson(Map<String, dynamic> json) : values = json {
    if (json['schema_version'] != 1 ||
        json['intake_enabled'] is! bool ||
        json['delivery_enabled'] is! bool) {
      throw const FormatException('Invalid growth overview');
    }
    for (final key in [
      'pending',
      'confirmed',
      'withdrawn',
      'confirmed_7d',
      'queued',
      'failed',
      'sent',
      'attempts_today',
      'daily_limit',
      'monthly_limit',
    ]) {
      if (json[key] is! int || (json[key] as int) < 0) {
        throw const FormatException('Invalid growth count');
      }
    }
    for (final key in ['channels', 'roles']) {
      if (json[key] is! List) {
        throw const FormatException('Invalid growth rows');
      }
      for (final row in json[key] as List) {
        if (row is! Map ||
            row['confirmed'] is! int ||
            row['confirmed'] < 0 ||
            (key == 'channels' &&
                (row['source'] is! String ||
                    row['applications'] is! int ||
                    row['applications'] < 0)) ||
            (key == 'roles' && row['role_code'] is! String)) {
          throw const FormatException('Invalid growth row');
        }
      }
    }
  }
  final Map<String, dynamic> values;
  int count(String key) => values[key] as int;
  bool get intakeEnabled => values['intake_enabled'] as bool;
  bool get deliveryEnabled => values['delivery_enabled'] as bool;
  List<Map<String, dynamic>> get channels => (values['channels'] as List)
      .map((row) => Map<String, dynamic>.from(row as Map))
      .toList();
}
