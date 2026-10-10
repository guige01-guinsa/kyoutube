import '../../../core/localization/localized_text.dart';
import '../../../core/auth/auth_return.dart';
import 'package:k_youtube/core/widgets/scout_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class MfaPage extends StatefulWidget {
  const MfaPage({super.key, this.returnTo});
  final String? returnTo;
  @override
  State<MfaPage> createState() => _MfaPageState();
}

class _MfaPageState extends State<MfaPage> {
  final code = TextEditingController();
  String? factorId, setupKey, error;
  bool busy = true, verified = false;
  bool get en => Localizations.localeOf(context).languageCode != 'ko';
  final auth = Supabase.instance.client.auth;
  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    code.dispose();
    setupKey = null;
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final factors = await auth.mfa.listFactors();
      final available =
          factors.totp.where((f) => f.status == FactorStatus.verified);
      if (!mounted) return;
      setState(() {
        factorId = available.isEmpty ? null : available.first.id;
        verified = auth.mfa.getAuthenticatorAssuranceLevel().currentLevel ==
            AuthenticatorAssuranceLevels.aal2;
      });
    } catch (_) {
      if (mounted) setState(() => error = 'load');
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> _enroll() async {
    setState(() {
      busy = true;
      error = null;
    });
    try {
      final result = await auth.mfa.enroll(
          factorType: FactorType.totp,
          friendlyName:
              'Recipe Scout ${DateTime.now().millisecondsSinceEpoch}');
      if (mounted) {
        setState(() {
          factorId = result.id;
          setupKey = result.totp?.secret;
        });
      }
    } catch (_) {
      if (mounted) setState(() => error = 'enroll');
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> _verify() async {
    if (factorId == null || !RegExp(r'^\d{6}$').hasMatch(code.text)) return;
    setState(() {
      busy = true;
      error = null;
    });
    try {
      await auth.mfa.challengeAndVerify(factorId: factorId!, code: code.text);
      code.clear();
      if (!mounted) return;
      setState(() {
        verified = true;
        setupKey = null;
      });
      final next = safeAuthReturn(widget.returnTo);
      if (context.canPop()) {
        context.pop(true);
      } else if (next != null) {
        context.go(next);
      }
    } catch (_) {
      if (mounted) setState(() => error = 'verify');
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
      appBar: AppBar(title: LocalizedText(en ? 'Two-step verification' : '2단계 인증')),
      body: ScoutPageBody(
          maxWidth: 640,
          child: ListView(padding: const EdgeInsets.all(24), children: [
            const Icon(Icons.security, size: 48),
            const SizedBox(height: 20),
            LocalizedText(
                en
                    ? 'Protect administrator access with an authenticator app.'
                    : '인증 앱으로 관리자 접근을 보호합니다.',
                style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 12),
            LocalizedText(en
                ? 'Keep your authenticator on your own phone. Never share setup keys or verification codes. If the phone is lost, contact the project owner through the verified account recovery process.'
                : '인증 앱은 본인 휴대폰에서 관리하세요. 설정 키와 인증 코드를 공유하지 마세요. 휴대폰을 분실하면 본인 확인을 거쳐 프로젝트 운영자에게 인증 초기화를 요청하세요.'),
            if (busy) const LinearProgressIndicator(),
            if (error != null)
              LocalizedText(en
                  ? 'Unable to complete verification. Check the code and connection, then retry.'
                  : '인증을 완료하지 못했습니다. 코드와 연결을 확인한 뒤 다시 시도하세요.'),
            if (verified)
              LocalizedText(en
                  ? 'Two-step verification is active for this session.'
                  : '현재 세션의 2단계 인증이 완료되었습니다.'),
            if (!busy && !verified && factorId == null)
              FilledButton(
                  onPressed: _enroll,
                  child: LocalizedText(en ? 'Set up authenticator' : '인증 앱 등록')),
            if (setupKey != null) ...[
              const SizedBox(height: 20),
              LocalizedText(en
                  ? 'In your authenticator, choose manual setup, time-based code, and enter this key:'
                  : '인증 앱에서 수동 등록 → 시간 기반 코드를 선택하고 아래 키를 입력하세요.'),
              SelectableText(setupKey!,
                  style: const TextStyle(fontFamily: 'monospace')),
            ],
            if (factorId != null && !verified) ...[
              const SizedBox(height: 20),
              TextField(
                  controller: code,
                  keyboardType: TextInputType.number,
                  maxLength: 6,
                  inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                  decoration: InputDecoration(
                      labelText: en ? '6-digit code' : '6자리 인증 코드')),
              FilledButton(
                  onPressed: busy ? null : _verify,
                  child: LocalizedText(en ? 'Verify' : '인증')),
            ],
          ])));
}
