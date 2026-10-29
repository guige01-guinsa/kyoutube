import 'package:flutter/material.dart';

String? canonicalRecipeVideoUrl(String value) {
  final uri = Uri.tryParse(value.trim());
  if (uri == null || uri.scheme != 'https' || uri.userInfo.isNotEmpty) {
    return null;
  }
  String? id;
  if (uri.host == 'youtu.be' && uri.pathSegments.length == 1) {
    id = uri.pathSegments.first;
  } else if (['www.youtube.com', 'youtube.com', 'm.youtube.com']
      .contains(uri.host)) {
    if (uri.path == '/watch') id = uri.queryParameters['v'];
  }
  return id != null && RegExp(r'^[A-Za-z0-9_-]{11}$').hasMatch(id)
      ? 'https://www.youtube.com/watch?v=$id'
      : null;
}

Future<Map<String, dynamic>?> showRecipeSourceStart(
    BuildContext context) async {
  final form = GlobalKey<FormState>();
  var food = '', url = '';
  return showDialog<Map<String, dynamic>>(
      context: context,
      builder: (dialog) => AlertDialog(
            title: const Text('영상 주소로 원고 자동 준비'),
            content: SizedBox(
                width: 560,
                child: Form(
                    key: form,
                    child: Column(mainAxisSize: MainAxisSize.min, children: [
                      const Text(
                          '음식 이름과 기준 유튜브 주소만 입력하세요. 원문 정보가 부족하면 같은 음식의 한국어 영상 최대 5개를 확인하고, 레시피가 공개된 한 영상으로 기준을 변경합니다. 적합한 영상이 없으면 멈춥니다.'),
                      TextFormField(
                          maxLength: 30,
                          decoration: const InputDecoration(labelText: '음식 이름'),
                          onChanged: (v) => food = v.trim(),
                          validator: (v) => v == null || v.trim().isEmpty
                              ? '음식 이름을 입력하세요.'
                              : null),
                      TextFormField(
                          decoration:
                              const InputDecoration(labelText: '원본 유튜브 주소'),
                          onChanged: (v) => url = v,
                          validator: (v) =>
                              canonicalRecipeVideoUrl(v ?? '') == null
                                  ? '유튜브 영상 주소를 확인해 주세요.'
                                  : null),
                      const Text(
                          '다음 화면에서 원고 준비 비용을 확인합니다. 영상 제작과 업로드는 아직 시작하지 않습니다.'),
                    ]))),
            actions: [
              TextButton(
                  onPressed: () => Navigator.pop(dialog),
                  child: const Text('취소')),
              FilledButton(
                  onPressed: () {
                    if (!form.currentState!.validate()) return;
                    Navigator.pop(dialog, <String, dynamic>{
                      'food': food,
                      'source_url': canonicalRecipeVideoUrl(url),
                      'presenter':
                          '따뜻하고 또렷한 한국어 여성 진행자. 원본의 계량과 조리 순서를 바꾸지 않는다.'
                    });
                  },
                  child: const Text('원고 자동 준비'))
            ],
          ));
}

/// Source strings are copied verbatim, not recalculated or expanded by AI.
Future<Map<String, dynamic>?> showSourceRecipeDialog(BuildContext context,
    {Map<String, dynamic>? initial}) async {
  final recipe = initial?['recipe'] as Map?;
  final scenes = initial?['scenes'] as List?;
  final values = <String, String>{
    'food': initial?['food'] as String? ?? '',
    'url': recipe?['url'] as String? ?? '',
    'title': recipe?['title'] as String? ?? '',
    'channel': recipe?['channel'] as String? ?? '',
    'servings': recipe?['servings'] as String? ?? '',
    'ingredients': (recipe?['ingredients'] as List? ?? []).join('\n'),
    'steps': (recipe?['steps'] as List? ?? []).join('\n'),
    'intro': scenes?.first['spoken'] as String? ??
        '안녕하세요. 오늘은 원본 영상의 분량과 순서대로 함께 요리해 볼게요.',
    'outro': scenes?.last['spoken'] as String? ??
        '재료표와 원본 영상을 함께 확인하며 한 단계씩 따라 해 보세요.',
  };
  const labels = <String, String>{
    'food': '음식 이름',
    'url': '원본 유튜브 주소',
    'title': '원본 영상 제목',
    'channel': '채널 이름',
    'servings': '원본의 인분 표시',
    'ingredients': '재료와 원본 분량 · 한 줄에 하나씩',
    'steps': '원본 조리 순서 · 한 줄에 한 단계씩',
    'intro': '인사말',
    'outro': '마무리 말',
  };
  final form = GlobalKey<FormState>();
  var verified = false;
  return showDialog<Map<String, dynamic>>(
      context: context,
      builder: (dialog) => StatefulBuilder(
          builder: (context, setState) => AlertDialog(
                title: const Text('유튜브 원본으로 3분 이내 기획'),
                content: SizedBox(
                    width: 650,
                    child: SingleChildScrollView(
                        child: Form(
                            key: form,
                            child: Column(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  const Text(
                                      '재료의 양·단위·선택 사항과 조리 순서를 원본 그대로 옮겨 주세요. 약간은 약간으로 유지합니다. 저장은 무료이며 음성·영상 제작 전에 비용을 확인합니다.'),
                                  for (final entry in labels.entries)
                                    TextFormField(
                                        initialValue: values[entry.key],
                                        maxLines: ['ingredients', 'steps']
                                                .contains(entry.key)
                                            ? 6
                                            : 2,
                                        maxLength: entry.key == 'intro'
                                            ? 50
                                            : entry.key == 'outro'
                                                ? 80
                                                : null,
                                        decoration: InputDecoration(
                                            labelText: entry.value),
                                        onChanged: (v) {
                                          values[entry.key] = v.trim();
                                          setState(() => verified = false);
                                        },
                                        validator: (v) {
                                          if (v == null || v.trim().isEmpty) {
                                            return '원본 내용을 입력하세요.';
                                          }
                                          if (entry.key == 'url' &&
                                              !RegExp(r'^https://www\.youtube\.com/watch\?v=[A-Za-z0-9_-]{11}$')
                                                  .hasMatch(v.trim())) {
                                            return 'https://www.youtube.com/watch?v=영상ID 형식으로 입력하세요.';
                                          }
                                          if (['ingredients', 'steps']
                                              .contains(entry.key)) {
                                            final lines = v
                                                .trim()
                                                .split('\n')
                                                .where(
                                                    (s) => s.trim().isNotEmpty)
                                                .toList();
                                            final ingredients =
                                                entry.key == 'ingredients';
                                            if (lines.length <
                                                    (ingredients ? 2 : 1) ||
                                                lines.length >
                                                    (ingredients ? 24 : 12) ||
                                                lines.any((s) =>
                                                    s.trim().runes.length >
                                                    (ingredients
                                                        ? 100
                                                        : 160))) {
                                              return ingredients
                                                  ? '재료는 2~24줄, 한 줄 100자 이내로 입력하세요.'
                                                  : '조리 순서는 1~12줄, 한 줄 160자 이내로 입력하세요.';
                                            }
                                          }
                                          return null;
                                        }),
                                  CheckboxListTile(
                                      value: verified,
                                      onChanged: (v) =>
                                          setState(() => verified = v == true),
                                      title: const Text(
                                          '원본 영상과 재료·분량·단위·선택 사항·조리 순서가 같은지 대조했습니다.')),
                                  const Text(
                                      '새 그림 생성 없이 재료표·조리 안내 중심으로 제작합니다. 원고 확인 후 처리 목표 5분이며, 외부 서비스와 대기 시간에 따라 더 걸릴 수 있습니다.'),
                                ])))),
                actions: [
                  TextButton(
                      onPressed: () => Navigator.pop(dialog),
                      child: const Text('취소')),
                  FilledButton(
                      onPressed: !verified
                          ? null
                          : () {
                              if (!form.currentState!.validate()) return;
                              Navigator.pop(dialog, <String, dynamic>{
                                'food': values['food'],
                                'presenter': initial?['presenter'] ??
                                    '따뜻하고 또렷한 한국어 여성 진행자. 원본의 계량과 조리 순서를 바꾸지 않는다.',
                                'intro': values['intro'],
                                'outro': values['outro'],
                                'source_verified': true,
                                'recipe': {
                                  for (final k in [
                                    'url',
                                    'title',
                                    'channel',
                                    'servings'
                                  ])
                                    k: values[k],
                                  for (final k in ['ingredients', 'steps'])
                                    k: values[k]!
                                        .split('\n')
                                        .map((s) => s.trim())
                                        .where((s) => s.isNotEmpty)
                                        .toList()
                                },
                              });
                            },
                      child: const Text('원고 저장'))
                ],
              )));
}
