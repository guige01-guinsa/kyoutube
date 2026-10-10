import 'dart:async';
import '../../../core/auth/auth_return.dart';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:k_youtube/core/localization/localized_text.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/auth/oauth_redirect.dart';

import '../application/auth_providers.dart';
import '../../workspace/domain/workspace_profile.dart';
import '../../workspace/presentation/workspace_menu.dart';
import '../application/password_policy.dart';
import 'widgets/password_strength_panel.dart';

class LoginPage extends ConsumerStatefulWidget {
  const LoginPage({super.key, this.returnTo});
  final String? returnTo;

  @override
  ConsumerState<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends ConsumerState<LoginPage> {
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _confirmPasswordController = TextEditingController();
  final _formKey = GlobalKey<FormState>();

  bool _isSignUp = false;
  WorkspaceMode? _signupPurpose;
  bool _isSubmitting = false;
  bool _isPasswordVisible = false;
  bool _isConfirmPasswordVisible = false;
  String? _message;
  bool _verificationNeeded = false;
  DateTime? _resendAfter;
  Timer? _resendTimer;

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
      _verificationNeeded = true;
      return '이메일 확인이 필요합니다. 받은 이메일의 인증을 완료해 주세요.';
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
    // The app auth listener performs one navigation after successful sign-in.
  }

  @override
  void dispose() {
    _resendTimer?.cancel();
    _emailController.dispose();
    _passwordController.dispose();
    _confirmPasswordController.dispose();
    super.dispose();
  }

  Future<void> _signInWithGoogle() async {
    setState(() {
      _isSubmitting = true;
      _message = null;
    });

    try {
      await AuthReturnStore.remember(widget.returnTo);
      final auth = ref.read(authClientProvider);

      final launched = await auth.signInWithOAuth(
        OAuthProvider.google,
        redirectTo: oauthRedirectUri,
        // Google OAuth must stay in a secure browser context. A Custom Tab
        // keeps the authentication navigation out of the default browser's
        // standalone task while still avoiding an unsupported embedded WebView.
        authScreenLaunchMode:
            kIsWeb ? LaunchMode.platformDefault : LaunchMode.inAppBrowserView,
      );

      if (!mounted) {
        return;
      }

      setState(() {
        _message = launched
            ? 'Google 로그인 창을 안전한 로그인 탭으로 열었습니다. 인증 후 앱으로 돌아와 주세요.'
            : 'Google 로그인 창을 열지 못했습니다. 잠시 후 다시 시도해 주세요.';
      });
    } on AuthException catch (error) {
      if (mounted) {
        setState(() {
          _message = _friendlyAuthMessage(error);
        });
      }
    } catch (error) {
      if (mounted) {
        setState(() {
          _message = error.toString();
        });
      }
    } finally {
      if (mounted) {
        setState(() {
          _isSubmitting = false;
        });
      }
    }
  }

  Future<void> _signInWithKakao() async {
    setState(() {
      _isSubmitting = true;
      _message = null;
    });

    try {
      await AuthReturnStore.remember(widget.returnTo);
      final auth = ref.read(authClientProvider);

      final launched = await auth.signInWithOAuth(
        OAuthProvider.kakao,
        redirectTo: oauthRedirectUri,
        authScreenLaunchMode: LaunchMode.externalApplication,
      );

      if (!mounted) {
        return;
      }

      setState(() {
        _message = launched
            ? '카카오 로그인 창을 열었습니다. 인증 후 앱으로 돌아와 주세요.'
            : '카카오 로그인 창을 열지 못했습니다. 잠시 후 다시 시도해 주세요.';
      });
    } on AuthException catch (error) {
      if (mounted) {
        setState(() {
          _message = _friendlyAuthMessage(error);
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _message = '카카오 로그인을 시작하지 못했습니다. 잠시 후 다시 시도해 주세요.';
        });
      }
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

      await auth.resetPasswordForEmail(email, redirectTo: oauthRedirectUri);

      if (!mounted) {
        return;
      }

      setState(() {
        _message = '비밀번호 재설정 이메일을 보냈습니다. 이메일의 링크를 열어 새 비밀번호를 설정해 주세요.';
      });
    } on AuthException catch (error) {
      if (mounted) {
        setState(() {
          _message = _friendlyAuthMessage(error);
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _message = '비밀번호 재설정 이메일을 보내지 못했습니다. 잠시 후 다시 시도해 주세요.';
        });
      }
    } finally {
      if (mounted) {
        setState(() {
          _isSubmitting = false;
        });
      }
    }
  }

  Future<void> _resendVerification() async {
    if (_isSubmitting || (_resendAfter?.isAfter(DateTime.now()) ?? false)) {
      return;
    }
    final email = _emailController.text.trim();
    if (email.isEmpty) return;
    setState(() => _isSubmitting = true);
    try {
      await ref.read(authClientProvider).resend(
          type: OtpType.signup,
          email: email,
          emailRedirectTo: oauthRedirectUri);
      if (!mounted) return;
      setState(() {
        _message = '인증 이메일을 다시 보냈습니다. 받은편지함과 스팸함을 확인해 주세요.';
        _resendAfter = DateTime.now().add(const Duration(seconds: 60));
      });
      _resendTimer?.cancel();
      _resendTimer = Timer(const Duration(seconds: 60), () {
        if (mounted) setState(() {});
      });
    } on AuthException catch (e) {
      if (mounted) setState(() => _message = _friendlyAuthMessage(e));
    } catch (_) {
      if (mounted) {
        setState(() => _message = '인증 이메일을 보내지 못했습니다. 연결 상태를 확인하고 다시 시도해 주세요.');
      }
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
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

    await AuthReturnStore.remember(widget.returnTo);
    final auth = ref.read(authClientProvider);
    final email = _emailController.text.trim();
    final password = _passwordController.text;

    try {
      if (_isSignUp) {
        final response = await auth.signUp(
          email: email,
          password: password,
          emailRedirectTo: oauthRedirectUri,
          data: {
            WorkspaceProfile.metadataKey: WorkspaceProfile(
                active: _signupPurpose!, enabled: {_signupPurpose!}).toJson()
          },
        );

        if (!mounted) {
          return;
        }

        if (response.session != null) {
          _goHomeAfterAuthentication();
          return;
        }

        setState(() {
          _verificationNeeded = true;
          _message = '회원가입이 완료되었습니다. 이메일 인증 후 로그인해 주세요.';
        });
      } else {
        final response = await auth.signInWithPassword(
          email: email,
          password: password,
        );

        if (!mounted) {
          return;
        }

        if (response.session != null) {
          _goHomeAfterAuthentication();
          return;
        }

        setState(() {
          _message = '로그인 정보를 확인해 주세요.';
        });
      }
    } on AuthException catch (error) {
      if (mounted) {
        setState(() {
          _message = _friendlyAuthMessage(error);
        });
      }
    } catch (error) {
      if (mounted) {
        setState(() {
          _message = error.toString();
        });
      }
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
    return Scaffold(
      appBar: AppBar(title: LocalizedText(_isSignUp ? '회원가입' : '로그인')),
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
                constraints: BoxConstraints(
                  minHeight: constraints.maxHeight - 40,
                ),
                child: Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 420),
                    child: Form(
                      key: _formKey,
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: <Widget>[
                          if (_isSignUp) ...<Widget>[
                            Card(
                              color: Theme.of(context)
                                  .colorScheme
                                  .primaryContainer
                                  .withValues(alpha: 0.45),
                              child: const Padding(
                                padding: EdgeInsets.all(16),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: <Widget>[
                                    Row(
                                      children: <Widget>[
                                        Icon(Icons.info_outline),
                                        SizedBox(width: 8),
                                        LocalizedText(
                                          '회원가입 안내',
                                          style: TextStyle(
                                            fontWeight: FontWeight.w700,
                                          ),
                                        ),
                                      ],
                                    ),
                                    SizedBox(height: 8),
                                    LocalizedText('이메일 주소가 로그인 아이디로 사용됩니다.'),
                                    SizedBox(height: 4),
                                    LocalizedText('가입 후 이메일 인증이 필요할 수 있습니다.'),
                                  ],
                                ),
                              ),
                            ),
                            const SizedBox(height: 16),
                          ],
                          if (_isSignUp) ...[
                            DropdownButtonFormField<WorkspaceMode>(
                              key: const Key('signup-purpose'),
                              initialValue: _signupPurpose,
                              isExpanded: true,
                              decoration: InputDecoration(
                                  labelText: workspaceText(context, '이용 목적',
                                      'How will you use Recipe Scout?')),
                              items: WorkspaceMode.values
                                  .map((mode) => DropdownMenuItem(
                                      value: mode,
                                      child: Text(modeTitle(context, mode))))
                                  .toList(),
                              onChanged: _isSubmitting
                                  ? null
                                  : (value) =>
                                      setState(() => _signupPurpose = value),
                              validator: (value) => value == null
                                  ? workspaceText(context, '이용 목적을 선택해 주세요.',
                                      'Choose your purpose.')
                                  : null,
                            ),
                            const SizedBox(height: 16),
                          ],
                          TextFormField(
                            controller: _emailController,
                            keyboardType: TextInputType.emailAddress,
                            autocorrect: false,
                            decoration:
                                InputDecoration(labelText: context.tr('이메일')),
                            validator: (String? value) {
                              final email = value?.trim() ?? '';

                              if (email.isEmpty || !email.contains('@')) {
                                return context.tr('유효한 이메일을 입력해 주세요.');
                              }

                              return null;
                            },
                          ),
                          const SizedBox(height: 12),
                          TextFormField(
                            controller: _passwordController,
                            obscureText: !_isPasswordVisible,
                            onChanged: (_) {
                              if (_isSignUp) {
                                setState(() {});
                              }
                            },
                            decoration: InputDecoration(
                              labelText: context.tr('비밀번호'),
                              helperText: _isSignUp
                                  ? context.tr('8자 이상, 영문과 숫자를 포함해 주세요.')
                                  : null,
                              suffixIcon: IconButton(
                                tooltip: context.tr(_isPasswordVisible
                                    ? '비밀번호 숨기기'
                                    : '비밀번호 보기'),
                                onPressed: () {
                                  setState(() {
                                    _isPasswordVisible = !_isPasswordVisible;
                                  });
                                },
                                icon: Icon(
                                  _isPasswordVisible
                                      ? Icons.visibility_off_outlined
                                      : Icons.visibility_outlined,
                                ),
                              ),
                            ),
                            validator: (String? value) {
                              final message = _isSignUp
                                  ? PasswordPolicy.validateForSignUp(value)
                                  : PasswordPolicy.validateForLogin(value);
                              return message == null
                                  ? null
                                  : context.tr(message);
                            },
                          ),
                          if (_isSignUp) ...<Widget>[
                            const SizedBox(height: 12),
                            PasswordStrengthPanel(
                              password: _passwordController.text,
                            ),
                            const SizedBox(height: 12),
                            TextFormField(
                              controller: _confirmPasswordController,
                              obscureText: !_isConfirmPasswordVisible,
                              decoration: InputDecoration(
                                labelText: context.tr('비밀번호 확인'),
                                suffixIcon: IconButton(
                                  tooltip: context.tr(_isConfirmPasswordVisible
                                      ? '비밀번호 숨기기'
                                      : '비밀번호 보기'),
                                  onPressed: () {
                                    setState(() {
                                      _isConfirmPasswordVisible =
                                          !_isConfirmPasswordVisible;
                                    });
                                  },
                                  icon: Icon(
                                    _isConfirmPasswordVisible
                                        ? Icons.visibility_off_outlined
                                        : Icons.visibility_outlined,
                                  ),
                                ),
                              ),
                              validator: (String? value) {
                                if ((value ?? '').isEmpty) {
                                  return context.tr('비밀번호를 한 번 더 입력해 주세요.');
                                }

                                if (value != _passwordController.text) {
                                  return context.tr('비밀번호가 일치하지 않습니다.');
                                }

                                return null;
                              },
                            ),
                          ],
                          const SizedBox(height: 20),
                          FilledButton(
                            onPressed: _isSubmitting ? null : _submit,
                            child: LocalizedText(
                              _isSubmitting
                                  ? '처리 중...'
                                  : (_isSignUp ? '회원가입' : '로그인'),
                            ),
                          ),
                          if (_verificationNeeded)
                            TextButton(
                                onPressed: _isSubmitting ||
                                        (_resendAfter
                                                ?.isAfter(DateTime.now()) ??
                                            false)
                                    ? null
                                    : _resendVerification,
                                child: LocalizedText(Localizations.localeOf(context)
                                            .languageCode ==
                                        'en'
                                    ? 'Resend verification email'
                                    : '인증 이메일 다시 보내기')),
                          if (_message != null) ...<Widget>[
                            const SizedBox(height: 12),
                            Semantics(
                              liveRegion: true,
                              child: Container(
                                padding: const EdgeInsets.all(12),
                                decoration: BoxDecoration(
                                  color: Theme.of(context)
                                      .colorScheme
                                      .surfaceContainerHighest,
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                child: LocalizedText(
                                  _message!,
                                  textAlign: TextAlign.center,
                                ),
                              ),
                            ),
                          ],
                          if (!_isSignUp) ...<Widget>[
                            const SizedBox(height: 12),
                            OutlinedButton.icon(
                              onPressed:
                                  _isSubmitting ? null : _signInWithGoogle,
                              icon: const Icon(Icons.login),
                              label: const LocalizedText('Google로 로그인'),
                            ),
                            const SizedBox(height: 8),
                            FilledButton.icon(
                              onPressed:
                                  _isSubmitting ? null : _signInWithKakao,
                              style: FilledButton.styleFrom(
                                backgroundColor: const Color(0xFFFEE500),
                                foregroundColor: const Color(0xFF191919),
                              ),
                              icon: const Icon(Icons.chat_bubble),
                              label: const LocalizedText('카카오로 로그인'),
                            ),
                            TextButton(
                              onPressed: _isSubmitting
                                  ? null
                                  : _sendPasswordResetEmail,
                              child: const LocalizedText('비밀번호를 잊으셨나요?'),
                            ),
                            TextButton.icon(
                              onPressed: _isSubmitting
                                  ? null
                                  : () {
                                      showDialog<void>(
                                        context: context,
                                        builder: (BuildContext context) {
                                          return AlertDialog(
                                            title: const LocalizedText(
                                                '아이디를 잊으셨나요?'),
                                            content: const LocalizedText(
                                              '가입할 때 사용한 이메일 주소가 로그인 아이디입니다.\n\n'
                                              '이메일 주소가 기억나지 않으면 가입에 사용한 메일함을 확인해 주세요.',
                                            ),
                                            actions: <Widget>[
                                              TextButton(
                                                onPressed: () =>
                                                    Navigator.of(context).pop(),
                                                child:
                                                    const LocalizedText('확인'),
                                              ),
                                            ],
                                          );
                                        },
                                      );
                                    },
                              icon: const Icon(Icons.help_outline),
                              label: const LocalizedText('아이디를 잊으셨나요?'),
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
                            child: LocalizedText(
                              _isSignUp ? '이미 계정이 있으면. 로그인' : '계정이 없으면. 회원가입',
                            ),
                          ),
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
