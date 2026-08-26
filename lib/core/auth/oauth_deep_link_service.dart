import 'dart:async';

import 'package:app_links/app_links.dart';
import 'package:flutter/widgets.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../ops/ops_monitor_service.dart';
import 'oauth_callback_handler.dart';

class OAuthDeepLinkService {
  OAuthDeepLinkService({
    AppLinks? appLinks,
    OAuthCallbackHandler? callbackHandler,
  }) : _appLinks = appLinks ?? AppLinks(),
       _callbackHandler =
           callbackHandler ??
           OAuthCallbackHandler(
             exchangeSessionFromUri: (Uri uri) async {
               final response = await Supabase.instance.client.auth
                   .getSessionFromUrl(uri);

               return response.redirectType;
             },
           );

  final AppLinks _appLinks;
  final OAuthCallbackHandler _callbackHandler;

  StreamSubscription<Uri>? _subscription;
  bool _started = false;

  Future<void> start() async {
    if (_started) {
      return;
    }

    _started = true;

    _subscription = _appLinks.uriLinkStream.listen(
      (Uri uri) {
        unawaited(_handleUri(uri));
      },
      onError: (Object error, StackTrace stackTrace) {
        OpsMonitorService.recordError(
          error,
          source: 'oauth_deep_link_stream',
          stackTrace: stackTrace,
        );
      },
    );

    try {
      final initialUri = await _appLinks.getInitialLink();

      if (initialUri != null) {
        // Wait until KYoutubeApp installs its AuthState listener.
        WidgetsBinding.instance.addPostFrameCallback((_) {
          unawaited(_handleUri(initialUri));
        });
      }
    } catch (error, stackTrace) {
      OpsMonitorService.recordError(
        error,
        source: 'oauth_initial_deep_link',
        stackTrace: stackTrace,
      );
    }
  }

  void dispose() {
    _subscription?.cancel();
    _subscription = null;
    _started = false;
  }

  Future<void> _handleUri(Uri uri) async {
    final result = await _callbackHandler.handle(uri);

    switch (result.outcome) {
      case OAuthCallbackOutcome.ignored:
      case OAuthCallbackOutcome.duplicate:
      case OAuthCallbackOutcome.exchanged:
        return;
      case OAuthCallbackOutcome.missingCode:
        OpsMonitorService.recordError(
          StateError('OAuth callback URI is missing an authorization code.'),
          source: 'oauth_callback_missing_code',
        );
      case OAuthCallbackOutcome.providerError:
        OpsMonitorService.recordError(
          StateError('OAuth provider callback error: ${result.providerError}'),
          source: 'oauth_provider_callback',
        );
      case OAuthCallbackOutcome.exchangeFailed:
        OpsMonitorService.recordError(
          result.error ??
              StateError('OAuth authorization code exchange failed.'),
          source: 'oauth_code_exchange',
        );
    }
  }
}
