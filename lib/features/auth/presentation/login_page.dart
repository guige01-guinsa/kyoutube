import 'dart:async';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/config/env.dart';

class LoginPage extends StatefulWidget {
  const LoginPage({
    super.key,
    this.returnTo = '/',
  });

  final String returnTo;

  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> with WidgetsBindingObserver {
  StreamSubscription<AuthState>? _authStateSub;
  bool _isSubmitting = false;
  bool _awaitingOAuthCallback = false;
  bool _sawBackgroundDuringOAuth = false;
  bool _didHandleLoginSuccess = false;
  String? _error;

  String get _targetRoute {
    if (!widget.returnTo.startsWith('/')) {
      return '/';
    }
    return widget.returnTo;
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _authStateSub = Supabase.instance.client.auth.onAuthStateChange.listen(
      (AuthState state) {
        if (!mounted) {
          return;
        }

        if (state.session != null) {
          _handleLoginSuccess();
        }
      },
    );

    final currentSession = Supabase.instance.client.auth.currentSession;
    if (currentSession != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) {
          return;
        }
        _handleLoginSuccess();
      });
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (!_awaitingOAuthCallback) {
      return;
    }

    if (state == AppLifecycleState.inactive ||
        state == AppLifecycleState.paused) {
      _sawBackgroundDuringOAuth = true;
      return;
    }

    if (state == AppLifecycleState.resumed && _sawBackgroundDuringOAuth) {
      _sawBackgroundDuringOAuth = false;
      Future<void>.delayed(const Duration(milliseconds: 900), () {
        if (!mounted || !_awaitingOAuthCallback) {
          return;
        }

        final hasSession = Supabase.instance.client.auth.currentSession != null;
        if (hasSession) {
          return;
        }

        setState(() {
          _awaitingOAuthCallback = false;
          _isSubmitting = false;
          _error =
              'Google 로그인 완료를 확인하지 못했습니다. 로컬 환경에서는 OAuth 설정 또는 adb reverse 상태를 다시 확인해 주세요.';
        });
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Google 로그인 확인 실패: 익명 로그인(테스트)로 먼저 진행할 수 있습니다.'),
          ),
        );
      });
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _authStateSub?.cancel();
    super.dispose();
  }

  void _handleLoginSuccess() {
    if (!mounted || _didHandleLoginSuccess) {
      return;
    }

    _didHandleLoginSuccess = true;
    _awaitingOAuthCallback = false;
    _isSubmitting = false;

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('로그인에 성공했습니다.')),
    );
    context.go(_targetRoute);
  }

  Future<void> _signInWithOAuth(OAuthProvider provider) async {
    if (_isSubmitting) {
      return;
    }

    if (Env.appEnv == 'local' && !Env.googleOAuthConfigured) {
      setState(() {
        _error =
            '로컬 Google OAuth 설정이 불완전합니다. SUPABASE_AUTH_GOOGLE_CLIENT_ID_LOCAL / SUPABASE_AUTH_GOOGLE_SECRET_LOCAL 값을 확인해 주세요.';
      });
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Google 로그인 설정이 완전하지 않습니다. 익명 로그인(테스트)을 사용해 주세요.'),
        ),
      );
      return;
    }

    setState(() {
      _isSubmitting = true;
      _awaitingOAuthCallback = true;
      _sawBackgroundDuringOAuth = false;
      _error = null;
    });

    try {
      await Supabase.instance.client.auth.signInWithOAuth(
        provider,
        redirectTo: Env.oauthRedirectTo,
      );
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('브라우저에서 로그인 완료 후 앱으로 돌아와 주세요.')),
      );
    } catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _awaitingOAuthCallback = false;
        _error = '로그인에 실패했습니다: $error';
      });
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('로그인 요청을 시작하지 못했습니다.')),
      );
    } finally {
      if (mounted) {
        setState(() {
          if (!_awaitingOAuthCallback) {
            _isSubmitting = false;
          }
        });
      }
    }
  }

  Future<void> _signInAnonymously() async {
    if (_isSubmitting) {
      return;
    }

    setState(() {
      _isSubmitting = true;
      _error = null;
    });

    try {
      await Supabase.instance.client.auth.signInAnonymously();
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('익명 로그인에 성공했습니다.')),
      );
      context.go(_targetRoute);
    } catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _error = '익명 로그인에 실패했습니다: $error';
      });
    } finally {
      if (mounted) {
        setState(() {
          _isSubmitting = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    const canUseGoogleOAuth =
        Env.googleOAuthEnabled &&
            (Env.appEnv != 'local' || Env.googleOAuthConfigured);

    return Scaffold(
      appBar: AppBar(title: const Text('로그인')),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(20),
          children: <Widget>[
            const Text(
              '크리에이터 서버 저장과 목록 조회에는 로그인이 필요합니다.',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 8),
            const Text(
              '로그인하면 작성한 레시피를 서버에 저장하고 수정/삭제할 수 있습니다.',
            ),
            const SizedBox(height: 20),
            if (Env.googleOAuthEnabled)
              FilledButton.icon(
                onPressed: (!canUseGoogleOAuth || _isSubmitting)
                    ? null
                    : () => _signInWithOAuth(OAuthProvider.google),
                icon: const Icon(Icons.login),
                label: const Text('Google로 로그인'),
              ),
            if (Env.appEnv == 'local' && Env.googleOAuthEnabled) ...<Widget>[
              const SizedBox(height: 8),
              const Text(
                canUseGoogleOAuth
                    ? '로컬 환경에서도 Google 로그인은 가능하지만, 브라우저에서 계정 선택과 허용을 완료하고 앱으로 복귀해야 세션이 생성됩니다.'
                    : '로컬 Google OAuth 설정이 불완전합니다.\n'
                        '.env.local에 SUPABASE_AUTH_GOOGLE_CLIENT_ID_LOCAL / SUPABASE_AUTH_GOOGLE_SECRET_LOCAL 값을 설정한 뒤 Supabase를 재시작해 주세요.',
              ),
            ],
            if (!Env.googleOAuthEnabled) ...<Widget>[
              const SizedBox(height: 4),
              const Text(
                '현재 실행 설정에서 Google OAuth 버튼이 비활성화되어 있습니다.\n'
                'run-local 실행 시 GOOGLE_OAUTH_ENABLED 값을 확인해 주세요.',
              ),
            ],
            const SizedBox(height: 10),
            OutlinedButton.icon(
              onPressed: _isSubmitting ? null : _signInAnonymously,
              icon: const Icon(Icons.person_outline),
              label: const Text('익명 로그인(테스트)'),
            ),
            const SizedBox(height: 12),
            TextButton(
              onPressed: _isSubmitting ? null : () => context.go('/creator/new'),
              child: const Text('로그인 없이 로컬 초안 작성하기'),
            ),
            if (_error != null) ...<Widget>[
              const SizedBox(height: 12),
              Text(
                _error!,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
