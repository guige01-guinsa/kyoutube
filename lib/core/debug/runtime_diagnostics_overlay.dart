import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../config/env.dart';
import '../ops/ops_monitor_service.dart';

class RuntimeDiagnosticsConfig {
  const RuntimeDiagnosticsConfig._();

  // Temporary runtime diagnostics for device testing.
  // Disable with: --dart-define=ENABLE_RUNTIME_DIAGNOSTICS=false
  static const bool enabled = !kReleaseMode &&
      bool.fromEnvironment('ENABLE_RUNTIME_DIAGNOSTICS', defaultValue: true);
}

class RuntimeDiagnosticsOverlay extends StatelessWidget {
  const RuntimeDiagnosticsOverlay({
    super.key,
    required this.child,
  });

  final Widget child;

  @override
  Widget build(BuildContext context) {
    if (!RuntimeDiagnosticsConfig.enabled) {
      return child;
    }

    return Stack(
      children: <Widget>[
        child,
        const Positioned(
          left: 12,
          right: 12,
          bottom: 12,
          child: _RuntimeDiagnosticsPanel(),
        ),
      ],
    );
  }
}

class _RuntimeDiagnosticsPanel extends StatelessWidget {
  const _RuntimeDiagnosticsPanel();

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<OpsMonitorState>(
      valueListenable: OpsMonitorService.state,
      builder: (BuildContext context, OpsMonitorState state, _) {
        final ColorScheme colors = Theme.of(context).colorScheme;
        final String latestError =
            state.recentErrors.isEmpty ? '-' : state.recentErrors.first.message;

        return Card(
          color: colors.surface.withValues(alpha: 0.95),
          elevation: 3,
          child: Padding(
            padding: const EdgeInsets.all(10),
            child: DefaultTextStyle(
              style: TextStyle(
                color: colors.onSurface,
                fontSize: 11,
                height: 1.35,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  const Text(
                    'RUNTIME DIAGNOSTICS',
                    style: TextStyle(fontWeight: FontWeight.w700),
                  ),
                  const SizedBox(height: 4),
                  const Text(
                    'mode: ${kReleaseMode ? 'release' : 'debug/profile'}',
                  ),
                  Text('env: ${Env.appEnv}'),
                  Text('phase: ${state.phase}'),
                  Text('ready: ${state.isReady}'),
                  Text('url-set: ${Env.supabaseUrl.isNotEmpty}'),
                  Text('anon-set: ${Env.supabaseAnonKey.isNotEmpty}'),
                  Text('startup-error: ${state.startupError ?? '-'}'),
                  Text('latest-error: $latestError'),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}
