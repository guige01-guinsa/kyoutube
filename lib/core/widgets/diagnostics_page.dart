import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:k_youtube/core/localization/localized_text.dart';
import '../firebase/firebase_messaging_service.dart';
import 'operations_status_card.dart';

class DiagnosticsPage extends StatelessWidget {
  const DiagnosticsPage({super.key});
  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: const LocalizedText('개발 진단')),
        body: ListView(
            children: const <Widget>[OperationsStatusCard(), _FcmDebugPanel()]),
      );
}

class _FcmDebugPanel extends StatelessWidget {
  const _FcmDebugPanel();

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<FirebaseMessagingDebugState>(
      valueListenable: FirebaseMessagingService.debugState,
      builder: (BuildContext context, FirebaseMessagingDebugState state, _) {
        return Card(
          margin: const EdgeInsets.fromLTRB(16, 16, 16, 8),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                LocalizedText(
                  'FCM 디버그',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const SizedBox(height: 8),
                LocalizedText(
                  state.isSupportedPlatform
                      ? '권한 상태: ${state.permissionStatus}'
                      : '현재 플랫폼은 FCM 디버그 대상이 아닙니다. Android 또는 iOS에서 확인하세요.',
                ),
                const SizedBox(height: 8),
                LocalizedText(
                  '토큰: ${state.tokenPreview ?? '아직 없음'}',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
                if (state.lastMessageTitle != null ||
                    state.lastMessageBody != null) ...<Widget>[
                  const SizedBox(height: 8),
                  LocalizedText('마지막 알림 제목: ${state.lastMessageTitle ?? '-'}'),
                  const SizedBox(height: 4),
                  LocalizedText('마지막 알림 본문: ${state.lastMessageBody ?? '-'}'),
                ],
                if (state.errorMessage != null) ...<Widget>[
                  const SizedBox(height: 8),
                  LocalizedText(
                    '오류: ${state.errorMessage}',
                    style:
                        TextStyle(color: Theme.of(context).colorScheme.error),
                  ),
                ],
                const SizedBox(height: 12),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: <Widget>[
                    OutlinedButton(
                      onPressed: state.isSupportedPlatform && !kReleaseMode
                          ? () => FirebaseMessagingService.requestPermission()
                          : null,
                      child: const LocalizedText('권한 요청'),
                    ),
                    OutlinedButton(
                      onPressed: state.isSupportedPlatform
                          ? () => FirebaseMessagingService.refreshToken()
                          : null,
                      child: const LocalizedText('토큰 새로고침'),
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
