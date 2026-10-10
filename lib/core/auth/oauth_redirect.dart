import 'package:flutter/foundation.dart';

/// Must match the Android intent filter and Supabase redirect allow-list.
const String mobileOAuthRedirectUri = 'io.supabase.kyoutube://login-callback/';

/// Return only to this deployment's origin/path, never a query-supplied URL.
String webOAuthRedirectUri(Uri page) => Uri(
        scheme: page.scheme,
        host: page.host,
        port: page.hasPort ? page.port : null,
        path: page.path)
    .toString();

String get oauthRedirectUri =>
    kIsWeb ? webOAuthRedirectUri(Uri.base) : mobileOAuthRedirectUri;
