import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

final authClientProvider = Provider<GoTrueClient>(
  (ref) => Supabase.instance.client.auth,
);

final authUserProvider = StreamProvider<User?>((ref) {
  final auth = ref.watch(authClientProvider);
  final controller = StreamController<User?>();

  controller.add(auth.currentUser);

  final subscription = auth.onAuthStateChange.listen((AuthState data) {
    controller.add(data.session?.user);
  });

  ref.onDispose(() {
    subscription.cancel();
    controller.close();
  });

  return controller.stream;
});
