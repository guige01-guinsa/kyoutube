import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart';
import '../data/standard_studio_repository.dart';

/// Existing studio entry point also exposes completed standard projects.
class StandardStudioSummary extends ConsumerWidget {
  const StandardStudioSummary({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) => Card(
      child: Padding(
          padding: const EdgeInsets.all(16),
          child:
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Text('레시피 영상 · 원고와 완성본',
                style: TextStyle(fontWeight: FontWeight.bold)),
            const Text('유튜브 원본의 재료와 순서로 제작하고, 완성 영상을 여기에서 확인하세요.'),
            FilledButton.icon(
                onPressed: () => context.go('/marketing/standard'),
                icon: const Icon(Icons.movie_creation_outlined),
                label: const Text('원고 편집·영상 제작 열기')),
            ref.watch(standardStudioProvider).when(
                loading: () => const LinearProgressIndicator(),
                error: (_, __) => const Text('제작소를 열어 관리자 인증과 연결 상태를 확인해 주세요.'),
                data: (data) => Column(children: [
                      for (final row in standardRows(data, 'projects'))
                        ListTile(
                          title: Text(
                              '${row['food']} · ${standardStatus(row['status'] as String)}'),
                          trailing: row['preview'] is Map
                              ? OutlinedButton(
                                  child: const Text('영상 미리보기'),
                                  onPressed: () async {
                                    try {
                                      final path = (row['preview']
                                          as Map)['path'] as String;
                                      final url = await ref
                                          .read(
                                              standardStudioRepositoryProvider)
                                          .preview(path, sample: false);
                                      if (!await launchUrl(Uri.parse(url),
                                          mode:
                                              LaunchMode.externalApplication)) {
                                        throw StateError('open');
                                      }
                                    } catch (_) {
                                      if (context.mounted) {
                                        ScaffoldMessenger.of(context)
                                            .showSnackBar(const SnackBar(
                                                content: Text(
                                                    '미리보기를 열지 못했습니다. 제작소에서 다시 확인해 주세요.')));
                                      }
                                    }
                                  })
                              : null,
                        )
                    ])),
          ])));
}
