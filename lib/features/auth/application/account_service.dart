import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/firebase/firebase_messaging_service.dart';

final accountServiceProvider = Provider<AccountService>(
  (ref) => AccountService(Supabase.instance.client),
);

class AccountService {
  AccountService(this._client);

  final SupabaseClient _client;

  Future<void> signOutCurrentAccount() async {
    await FirebaseMessagingService.deleteDeviceToken();
    await _client.auth.signOut();
  }

  Future<void> deleteCurrentAccount() async {
    final user = _client.auth.currentUser;

    if (user == null) {
      throw StateError('로그인이 필요합니다.');
    }

    final response = await _client.functions.invoke(
      'delete-account',
      body: <String, dynamic>{},
    );

    if (response.status < 200 || response.status >= 300) {
      throw Exception('회원탈퇴 요청에 실패했습니다.');
    }

    // Token 삭제 실패는 회원탈퇴 완료 상태를 되돌리지 않는다.
    await FirebaseMessagingService.deleteDeviceToken();

    await _client.auth.signOut();
  }
}
