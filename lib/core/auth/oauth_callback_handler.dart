typedef OAuthCodeExchange = Future<void> Function(String code);

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
    this.error,
  });

  final OAuthCallbackOutcome outcome;
  final String? providerError;
  final Object? error;
}

class OAuthCallbackHandler {
  OAuthCallbackHandler({
    required OAuthCodeExchange exchangeCode,
  }) : _exchangeCode = exchangeCode;

  final OAuthCodeExchange _exchangeCode;
  final Set<String> _handledCodes = <String>{};

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
    if (code == null || code.trim().isEmpty) {
      return const OAuthCallbackResult(OAuthCallbackOutcome.missingCode);
    }

    if (!_handledCodes.add(code)) {
      return const OAuthCallbackResult(OAuthCallbackOutcome.duplicate);
    }

    try {
      await _exchangeCode(code);
      return const OAuthCallbackResult(OAuthCallbackOutcome.exchanged);
    } catch (error) {
      return OAuthCallbackResult(
        OAuthCallbackOutcome.exchangeFailed,
        error: error,
      );
    }
  }
}
