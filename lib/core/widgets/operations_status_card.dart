import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../ops/ops_monitor_service.dart';
import 'centered_state_view.dart';

class OperationsStatusCard extends StatelessWidget {
  const OperationsStatusCard({super.key});

  String _formatTimestamp(DateTime timestamp) {
    final local = timestamp.toLocal();
    final hour = local.hour.toString().padLeft(2, '0');
    final minute = local.minute.toString().padLeft(2, '0');
    final second = local.second.toString().padLeft(2, '0');
    return '$hour:$minute:$second';
  }

  String _buildReport(OpsMonitorState state) {
    final buffer = StringBuffer()
      ..writeln('env=${state.appEnv}')
      ..writeln('phase=${state.phase}')
      ..writeln('ready=${state.isReady}')
      ..writeln('startupError=${state.startupError == null ? '-' : OpsMonitorService.redact(state.startupError!)}')
      ..writeln('recentErrors=${state.recentErrors.length}');

    for (final error in state.recentErrors) {
      buffer
        ..writeln('---')
        ..writeln('${error.timestamp.toIso8601String()} | ${error.source} | ${OpsMonitorService.redact(error.message)}')
        ..writeln('fatal=${error.isFatal}')
        ..writeln(error.stackTrace == null ? '-' : OpsMonitorService.redact(error.stackTrace!));
    }

    return buffer.toString();
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<OpsMonitorState>(
      valueListenable: OpsMonitorService.state,
      builder: (BuildContext context, OpsMonitorState state, _) {
        final colorScheme = Theme.of(context).colorScheme;
        return Card(
          margin: const EdgeInsets.fromLTRB(16, 16, 16, 8),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Row(
                  children: <Widget>[
                    Icon(Icons.monitor_heart_outlined, color: colorScheme.primary),
                    const SizedBox(width: 8),
                    Text(
                      '운영 상태',
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    const Spacer(),
                    Chip(
                      label: Text(state.isReady ? '준비 완료' : '점검 필요'),
                      side: BorderSide(color: colorScheme.outlineVariant),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Text('환경: ${state.appEnv}'),
                const SizedBox(height: 4),
                Text('현재 단계: ${state.phase}'),
                const SizedBox(height: 4),
                Text('최근 오류: ${state.recentErrors.length}건'),
                if (state.startupError != null) ...<Widget>[
                  const SizedBox(height: 8),
                  CenteredStateView(
                    icon: Icons.error_outline,
                    title: '시작 오류가 남아 있습니다',
                    message: state.startupError!,
                  ),
                ],
                if (state.recentErrors.isNotEmpty) ...<Widget>[
                  const SizedBox(height: 8),
                  Text(
                    '최근 이벤트',
                    style: Theme.of(context).textTheme.labelLarge,
                  ),
                  const SizedBox(height: 8),
                  ...state.recentErrors.take(3).map(
                    (OpsErrorEvent event) {
                      return Padding(
                        padding: const EdgeInsets.only(bottom: 8),
                        child: DecoratedBox(
                          decoration: BoxDecoration(
                            color: colorScheme.surfaceContainerHighest,
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Padding(
                            padding: const EdgeInsets.all(12),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: <Widget>[
                                Text(
                                  '[${_formatTimestamp(event.timestamp)}] ${event.source}',
                                  style: Theme.of(context).textTheme.labelMedium,
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  event.message,
                                  maxLines: 3,
                                  overflow: TextOverflow.ellipsis,
                                ),
                                if (event.stackTrace != null) ...<Widget>[
                                  const SizedBox(height: 4),
                                  Text(
                                    'stack trace saved',
                                    style: Theme.of(context).textTheme.labelSmall,
                                  ),
                                ],
                              ],
                            ),
                          ),
                        ),
                      );
                    },
                  ),
                ],
                const SizedBox(height: 12),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: <Widget>[
                    OutlinedButton(
                      onPressed: () async {
                        await Clipboard.setData(
                          ClipboardData(text: _buildReport(state)),
                        );
                        if (context.mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(content: Text('운영 리포트를 복사했습니다.')),
                          );
                        }
                      },
                      child: const Text('리포트 복사'),
                    ),
                    OutlinedButton(
                      onPressed: state.recentErrors.isEmpty
                          ? null
                          : () async {
                              await OpsMonitorService.clearRecentErrors();
                              if (context.mounted) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(content: Text('최근 오류를 지웠습니다.')),
                                );
                              }
                            },
                      child: const Text('최근 오류 지우기'),
                    ),
                  ],
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}
