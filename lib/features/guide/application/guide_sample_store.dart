import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import '../domain/guide_sample_data.dart';

/// Local-only store, deliberately independent of all production repositories.
/// Korean and English practice records can be reset independently.
class GuideSampleStore {
  GuideSampleStore(this.english);
  final bool english;
  String get key => 'guide_sample_records_v1_${english ? 'en' : 'ko'}';
  bool recovered = false;
  Future<GuideSampleData> load() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(key);
    if (raw != null) {
      try {
        final data =
            GuideSampleData.fromJson(jsonDecode(raw) as Map<String, dynamic>);
        if (data.english != english) {
          throw const FormatException('Language mismatch');
        }
        return data;
      } catch (_) {
        recovered = true;
      }
    }
    final data = GuideSampleData.seed(english: english);
    await save(data);
    return data;
  }

  Future<void> save(GuideSampleData data) async {
    // Validate a detached snapshot before committing; failure leaves the old copy.
    final raw = jsonEncode(data.toJson());
    GuideSampleData.fromJson(jsonDecode(raw) as Map<String, dynamic>);
    if (data.english != english || raw.length > 1500000) {
      throw const FormatException('Invalid practice data');
    }
    final prefs = await SharedPreferences.getInstance();
    if (!await prefs.setString(key, raw)) {
      throw StateError('Sample save failed');
    }
  }

  Future<GuideSampleData> reset() async {
    final seed = GuideSampleData.seed(english: english);
    await save(seed);
    recovered = false;
    return seed;
  }
}
