import 'dart:async';
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'app.dart';
import 'core/config/env.dart';
import 'core/ops/ops_monitor_service.dart';

Future<void> main() async {
  runZonedGuarded(() async {
    WidgetsFlutterBinding.ensureInitialized();

    try {
      await OpsMonitorService.initialize();

      FlutterError.onError = (FlutterErrorDetails details) {
        FlutterError.presentError(details);
        OpsMonitorService.recordError(
          details.exception,
          source: 'flutter',
          stackTrace: details.stack,
        );
      };

      PlatformDispatcher.instance.onError = (Object error, StackTrace stack) {
        OpsMonitorService.recordError(
          error,
          source: 'platform',
          stackTrace: stack,
          isFatal: true,
        );
        return true;
      };

      Env.validate();
      runApp(const ProviderScope(child: KYoutubeBootstrapApp()));
    } catch (error, stack) {
      OpsMonitorService.markStartupFailure(
        error: error,
        stackTrace: stack,
        phase: '환경 검증',
      );
      runApp(
        ProviderScope(
          child: BootstrapFailureApp(
            title: '앱을 시작할 수 없습니다',
            message: error.toString(),
          ),
        ),
      );
    }
  }, (Object error, StackTrace stack) {
    OpsMonitorService.recordError(
      error,
      source: 'zone',
      stackTrace: stack,
      isFatal: true,
    );
  });
}
