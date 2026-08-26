typedef OAuthUriSessionExchange = Future<String?> Function(Uri uri);

enum OAuthCallbackOutcome {
  ignored,
  missingCode,
  providerError,
  duplicate,
  exchanged,
  exchangeFailed,
}

class OAuthCallbackResult {
  const OAuthCallbackResult(
    this.outcome, {
    this.providerError,
    this.redirectType,
    this.error,
  });

  final OAuthCallbackOutcome outcome;
  final String? providerError;
  final String? redirectType;
  final Object? error;
}

class OAuthCallbackHandler {
  OAuthCallbackHandler({
    required OAuthUriSessionExchange exchangeSessionFromUri,
  }) : _exchangeSessionFromUri = exchangeSessionFromUri;

  final OAuthUriSessionExchange _exchangeSessionFromUri;
  final Set<String> _handledCallbacks = <String>{};

  Future<OAuthCallbackResult> handle(Uri uri) async {
    if (uri.scheme != 'io.supabase.kyoutube' || uri.host != 'login-callback') {
      return const OAuthCallbackResult(OAuthCallbackOutcome.ignored);
    }

    final providerError = uri.queryParameters['error'];
    if (providerError != null && providerError.trim().isNotEmpty) {
      return OAuthCallbackResult(
        OAuthCallbackOutcome.providerError,
        providerError: providerError,
      );
    }

    final code = uri.queryParameters['code'];
    final hasImplicitToken = uri.fragment.contains('access_token=');

    if ((code == null || code.trim().isEmpty) && !hasImplicitToken) {
      return const OAuthCallbackResult(OAuthCallbackOutcome.missingCode);
    }

    final callbackId = uri.toString();

    if (!_handledCallbacks.add(callbackId)) {
      return const OAuthCallbackResult(OAuthCallbackOutcome.duplicate);
    }

    try {
      final redirectType = await _exchangeSessionFromUri(uri);

      return OAuthCallbackResult(
        OAuthCallbackOutcome.exchanged,
        redirectType: redirectType,
      );
    } catch (error) {
      // Network failures or temporary server failures may be retried with
      // the same callback URI while the authorization code is still valid.
      _handledCallbacks.remove(callbackId);

      return OAuthCallbackResult(
        OAuthCallbackOutcome.exchangeFailed,
        error: error,
      );
    }
  }
}
