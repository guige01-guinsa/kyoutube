/// Native mobile OAuth callback used by Supabase Auth.
///
/// This URI must match:
/// - AndroidManifest.xml VIEW intent filter
/// - Supabase Authentication redirect URL allow-list
/// - OAuth redirectTo and emailRedirectTo values
const String oauthRedirectUri = 'io.supabase.kyoutube://login-callback/';

/// Forces Google OAuth to show the account chooser during authentication.
const Map<String, String> googleOAuthQueryParams = <String, String>{
  'prompt': 'select_account',
};
