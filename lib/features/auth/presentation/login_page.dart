import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../application/auth_providers.dart';

class LoginPage extends ConsumerStatefulWidget {
  const LoginPage({super.key});

  @override
  ConsumerState<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends ConsumerState<LoginPage> {
  static const String _oauthRedirectTo =
      'io.supabase.kyoutube://login-callback';

  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _formKey = GlobalKey<FormState>();

  bool _isSignUp = false;
  bool _isSubmitting = false;
  String? _message;

  String _friendlyAuthMessage(AuthException error) {
    final message = error.message.toLowerCase();

    if (message.contains('invalid login credentials') ||
        message.contains('invalid credentials')) {
      return '이메일 또는 비밀번호가 올바르지 않습니다.';
    }

    if (message.contains('user already registered') ||
        message.contains('already registered')) {
      return '이미 가입된 이메일입니다. 로그인해 주세요.';
    }

    if (message.contains('email not confirmed')) {
      return '이메일 확인이 필요합니다. 이메일 인증을 완료해 주세요.';
    }

    if (message.contains('signup is disabled')) {
      return '현재 회원가입을 사용할 수 없습니다.';
    }

    if (message.contains('rate limit')) {
      return '요청이 너무 많습니다. 잠시 후 다시 시도해 주세요.';
    }

    return error.message;
  }

  void _goHomeAfterAuthentication() {
    if (mounted) {
      context.go('/');
    }
  }

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _signInWithGoogle() async {
    setState(() {
      _isSubmitting = true;
      _message = null;
    });

    final auth = ref.read(authClientProvider);

    try {
      final launched = await auth.signInWithOAuth(
        OAuthProvider.google,
        redirectTo: _oauthRedirectTo,
      );

      if (!mounted) {
        return;
      }

      setState(() {
        _message = launched
            ? 'Google 로그인 창을 열었습니다. 인증 후 앱으로 돌아오세요.'
            : 'Google 로그인 창을 열지 못했습니다. 잠시 후 다시 시도해 주세요.';
      });
    } on AuthException catch (error) {
      if (!mounted) {
        return;
      }

      setState(() {
        _message = _friendlyAuthMessage(error);
      });
    } catch (error) {
      if (!mounted) {
        return;
      }

      setState(() {
        _message = error.toString();
      });
    } finally {
      if (mounted) {
        setState(() {
          _isSubmitting = false;
        });
      }
    }
  }

  Future<void> _sendPasswordResetEmail() async {
    final email = _emailController.text.trim();

    if (email.isEmpty || !email.contains('@')) {
      setState(() {
        _message = '비밀번호를 재설정할 이메일을 입력해 주세요.';
      });
      return;
    }

    setState(() {
      _isSubmitting = true;
      _message = null;
    });

    try {
      final auth = ref.read(authClientProvider);

      await auth.resetPasswordForEmail(
        email,
        redirectTo: _oauthRedirectTo,
      );

      if (!mounted) {
        return;
      }

      setState(() {
        _message = '비밀번호 재설정 이메일을 보냈습니다. 이메일의 링크를 열어 새 비밀번호를 설정해 주세요.';
      });
    } on AuthException catch (error) {
      if (!mounted) {
        return;
      }

      setState(() {
        _message = _friendlyAuthMessage(error);
      });
    } catch (_) {
      if (!mounted) {
        return;
      }

      setState(() {
        _message = '비밀번호 재설정 이메일을 보내지 못했습니다. 잠시 후 다시 시도해 주세요.';
      });
    } finally {
      if (mounted) {
        setState(() {
          _isSubmitting = false;
        });
      }
    }
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) {
      return;
    }

    setState(() {
      _isSubmitting = true;
      _message = null;
    });

    final auth = ref.read(authClientProvider);

    try {
      if (_isSignUp) {
        final response = await auth.signUp(
          email: _emailController.text.trim(),
          password: _passwordController.text,
        );

        if (!mounted) return;

        if (response.session != null) {
          _goHomeAfterAuthentication();
          return;
        }

        setState(() {
          _message = '회원가입이 완료되었습니다. 이메일 확인 후 로그인해 주세요.';
        });
      } else {
        final response = await auth.signInWithPassword(
          email: _emailController.text.trim(),
          password: _passwordController.text,
        );

        if (!mounted) return;

        if (response.session != null) {
          _goHomeAfterAuthentication();
          return;
        }

        setState(() {
          _message = '로그인 정보를 확인해 주세요.';
        });
      }
    } on AuthException catch (error) {
      setState(() {
        _message = _friendlyAuthMessage(error);
      });
    } catch (error) {
      setState(() {
        _message = error.toString();
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
    ref.listen(authUserProvider, (_, next) {
      final user = next.valueOrNull;

      if (user != null && mounted) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) {
            _goHomeAfterAuthentication();
          }
        });
      }
    });

    return Scaffold(
      appBar: AppBar(
        title: Text(_isSignUp ? '회원가입' : '로그인'),
      ),
      body: SafeArea(
        child: LayoutBuilder(
          builder: (BuildContext context, BoxConstraints constraints) {
            return SingleChildScrollView(
              padding: EdgeInsets.fromLTRB(
                20,
                20,
                20,
                20 + MediaQuery.of(context).viewInsets.bottom,
              ),
              child: ConstrainedBox(
                constraints:
                    BoxConstraints(minHeight: constraints.maxHeight - 40),
                child: Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 420),
                    child: Form(
                      key: _formKey,
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: <Widget>[
                          TextFormField(
                            controller: _emailController,
                            keyboardType: TextInputType.emailAddress,
                            decoration: const InputDecoration(labelText: '이메일'),
                            validator: (String? value) {
                              final email = value?.trim() ?? '';
                              if (email.isEmpty || !email.contains('@')) {
                                return '유효한 이메일을 입력해 주세요.';
                              }
                              return null;
                            },
                          ),
                          const SizedBox(height: 12),
                          TextFormField(
                            controller: _passwordController,
                            obscureText: true,
                            decoration:
                                const InputDecoration(labelText: '비밀번호'),
                            validator: (String? value) {
                              if ((value ?? '').length < 8) {
                                return '비밀번호는 8자 이상이어야 합니다.';
                              }
                              return null;
                            },
                          ),
                          const SizedBox(height: 20),
                          FilledButton(
                            onPressed: _isSubmitting ? null : _submit,
                            child: Text(_isSubmitting
                                ? '처리 중...'
                                : (_isSignUp ? '회원가입' : '로그인')),
                          ),
                          if (!_isSignUp) ...<Widget>[
                            const SizedBox(height: 12),
                            OutlinedButton.icon(
                              onPressed:
                                  _isSubmitting ? null : _signInWithGoogle,
                              icon: const Icon(Icons.login),
                              label: const Text('Google로 로그인'),
                            ),
                            TextButton(
                              onPressed: _isSubmitting
                                  ? null
                                  : _sendPasswordResetEmail,
                              child: const Text('비밀번호를 잊으셨나요?'),
                            ),
                          ],
                          TextButton(
                            onPressed: _isSubmitting
                                ? null
                                : () {
                                    setState(() {
                                      _isSignUp = !_isSignUp;
                                      _message = null;
                                    });
                                  },
                            child: Text(
                              _isSignUp ? '이미 계정이 있습니다. 로그인' : '계정이 없습니다. 회원가입',
                            ),
                          ),
                          if (_message != null) ...<Widget>[
                            const SizedBox(height: 12),
                            Text(
                              _message!,
                              textAlign: TextAlign.center,
                            ),
                          ],
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}
