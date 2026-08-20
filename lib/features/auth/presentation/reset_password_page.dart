import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../application/auth_providers.dart';

class ResetPasswordPage extends ConsumerStatefulWidget {
  const ResetPasswordPage({super.key});

  @override
  ConsumerState<ResetPasswordPage> createState() => _ResetPasswordPageState();
}

class _ResetPasswordPageState extends ConsumerState<ResetPasswordPage> {
  final _formKey = GlobalKey<FormState>();
  final _passwordController = TextEditingController();
  final _confirmPasswordController = TextEditingController();

  bool _isSubmitting = false;
  String? _message;

  @override
  void dispose() {
    _passwordController.dispose();
    _confirmPasswordController.dispose();
    super.dispose();
  }

  String _friendlyAuthMessage(AuthException error) {
    final message = error.message.toLowerCase();

    if (message.contains('same password')) {
      return '새 비밀번호는 기존 비밀번호와 다르게 입력해 주세요.';
    }

    if (message.contains('password')) {
      return '비밀번호 변경에 실패했습니다. 비밀번호 조건을 확인해 주세요.';
    }

    return error.message;
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) {
      return;
    }

    setState(() {
      _isSubmitting = true;
      _message = null;
    });

    try {
      final auth = ref.read(authClientProvider);

      await auth.updateUser(
        UserAttributes(
          password: _passwordController.text,
        ),
      );

      if (!mounted) {
        return;
      }

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('비밀번호가 변경되었습니다.'),
          duration: Duration(seconds: 3),
        ),
      );

      context.go('/');
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
        _message = '비밀번호를 변경하지 못했습니다. 재설정 링크를 다시 요청해 주세요.';
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
    return Scaffold(
      appBar: AppBar(
        title: const Text('비밀번호 재설정'),
      ),
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) {
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
                          const Icon(
                            Icons.lock_reset_outlined,
                            size: 56,
                          ),
                          const SizedBox(height: 20),
                          Text(
                            '새 비밀번호를 입력해 주세요.',
                            textAlign: TextAlign.center,
                            style: Theme.of(context).textTheme.titleMedium,
                          ),
                          const SizedBox(height: 24),
                          TextFormField(
                            controller: _passwordController,
                            obscureText: true,
                            decoration: const InputDecoration(
                              labelText: '새 비밀번호',
                            ),
                            validator: (value) {
                              if ((value ?? '').length < 8) {
                                return '비밀번호는 8자 이상이어야 합니다.';
                              }
                              return null;
                            },
                          ),
                          const SizedBox(height: 12),
                          TextFormField(
                            controller: _confirmPasswordController,
                            obscureText: true,
                            decoration: const InputDecoration(
                              labelText: '새 비밀번호 확인',
                            ),
                            validator: (value) {
                              if (value != _passwordController.text) {
                                return '비밀번호가 일치하지 않습니다.';
                              }
                              return null;
                            },
                          ),
                          const SizedBox(height: 20),
                          FilledButton(
                            onPressed: _isSubmitting ? null : _submit,
                            child: Text(
                              _isSubmitting ? '변경 중...' : '비밀번호 변경',
                            ),
                          ),
                          if (_message != null) ...<Widget>[
                            const SizedBox(height: 16),
                            Text(
                              _message!,
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                color: Theme.of(context).colorScheme.error,
                              ),
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
