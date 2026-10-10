import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../domain/guide_curriculum.dart';

/// Learning state only. No account, recipe, request or supplier records are stored.
class GuideProgress extends ChangeNotifier {
  GuideProgress({this.initialAudience, this.initialLesson});
  final GuideAudience? initialAudience;
  final String? initialLesson;
  final Set<String> _values = {};
  final Map<GuideAudience, String> _last = {};
  SharedPreferences? _preferences;
  Future<void> _pendingWrite = Future<void>.value();
  bool ready = false, saveFailed = false, _disposed = false;
  GuideAudience audience = GuideAudience.professional;
  GuideTrack track = GuideTrack.purchasing;
  static const storageKey = 'guide_curriculum_v3';
  static const audienceKey = 'guide_audience_v3';
  static const trackKey = 'guide_track_v3';
  Future<void> load() async {
    try {
      _preferences = await SharedPreferences.getInstance();
      final stored = _preferences!.getStringList(storageKey);
      // Retain unchanged lessons. The former bundled purchase lesson cannot
      // complete any of the new six lessons. Keep old keys for rollback.
      final source =
          stored ?? _preferences!.getStringList('guide_curriculum_v2') ?? [];
      final ids = guideLessons.map((l) => l.id).toSet();
      _values.addAll(source.where((v) => ids.contains(v.split('.').first)));
      final name = _preferences!.getString(audienceKey) ??
          _preferences!.getString('guide_audience_v2');
      audience = initialAudience ??
          GuideAudience.values.where((a) => a.name == name).firstOrNull ??
          GuideAudience.professional;
      track = GuideTrack.values
              .where((t) => t.name == _preferences!.getString(trackKey))
              .firstOrNull ??
          GuideTrack.purchasing;
      for (final a in GuideAudience.values) {
        final id = _preferences!.getString('guide_last_v3_${a.name}');
        if (guideLessonById(id)?.audience == a) _last[a] = id!;
      }
    } catch (_) {
      audience = initialAudience ?? GuideAudience.professional;
      saveFailed = true;
    }
    final requested = guideLessonById(initialLesson);
    if (requested != null) {
      audience = requested.audience;
      if (requested.audience == GuideAudience.professional) {
        track = guideTrackFor(requested);
      }
      _last[audience] = requested.id;
    }
    ready = true;
    if (!_disposed) notifyListeners();
  }

  void selectAudience(GuideAudience value) {
    audience = value;
    _save();
  }

  void selectTrack(GuideTrack value) {
    track = value;
    _save();
  }

  void visit(GuideLesson lesson) {
    audience = lesson.audience;
    if (lesson.audience == GuideAudience.professional) {
      track = guideTrackFor(lesson);
    }
    _last[audience] = lesson.id;
    _save();
  }

  String? get lastLesson => _last[audience];
  bool checked(String id, int step) => _values.contains('$id.step.$step');
  bool completed(String id) => _values.contains('$id.done');
  bool passed(String id) => _values.contains('$id.quiz');
  bool practiced(String id) => _values.contains('$id.practice');
  bool skipped(String id) => _values.contains('$id.skipped');
  int completedCount(GuideAudience course) =>
      guideLessonsFor(course).where((l) => completed(l.id)).length;
  void toggle(String id, int step) {
    final key = '$id.step.$step';
    if (!_values.remove(key)) _values.add(key);
    _save();
  }

  void answer(String id, bool correct) {
    if (correct) {
      _values.add('$id.quiz');
    } else {
      _values.remove('$id.quiz');
    }
    _save();
  }

  void recordPractice(String id) {
    _values.add('$id.practice');
    _save();
  }

  bool canComplete(GuideLesson lesson) =>
      practiced(lesson.id) ||
      List.generate(lesson.steps.length, (i) => checked(lesson.id, i))
          .every((v) => v);
  void complete(GuideLesson lesson) {
    if (!canComplete(lesson)) return;
    _values.add('${lesson.id}.done');
    _values.remove('${lesson.id}.skipped');
    _save();
  }

  void skip(GuideLesson lesson) {
    _values.add('${lesson.id}.skipped');
    _save();
  }

  void restart(GuideLesson lesson) {
    _values.removeWhere((v) => v.startsWith('${lesson.id}.'));
    visit(lesson);
  }

  List<GuideLesson> recommended(List<GuideLesson> lessons) {
    final last = lessons
        .where((l) => l.id == lastLesson && !completed(l.id) && !skipped(l.id));
    final rest = lessons
        .where((l) => !completed(l.id) && !skipped(l.id) && !last.contains(l));
    final review = lessons.where((l) => completed(l.id) || skipped(l.id));
    return [...last, ...rest, ...review].take(3).toList();
  }

  Future<void> flush() => _pendingWrite;
  void _save() {
    if (!_disposed) notifyListeners();
    final snapshot = _values.toList(),
        selected = audience.name,
        selectedTrack = track.name,
        last = Map.of(_last);
    _pendingWrite = _pendingWrite.then((_) async {
      try {
        final prefs = _preferences;
        var ok = prefs != null;
        if (prefs != null) {
          ok = await prefs.setStringList(storageKey, snapshot) && ok;
          ok = await prefs.setString(audienceKey, selected) && ok;
          ok = await prefs.setString(trackKey, selectedTrack) && ok;
          for (final e in last.entries) {
            ok =
                await prefs.setString('guide_last_v3_${e.key.name}', e.value) &&
                    ok;
          }
        }
        saveFailed = !ok;
      } catch (_) {
        saveFailed = true;
      }
      if (!_disposed) notifyListeners();
    });
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}
