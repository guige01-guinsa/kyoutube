import 'package:flutter/material.dart';

import 'core/router/app_router.dart';
import 'core/theme/app_theme.dart';

class KYoutubeApp extends StatelessWidget {
  const KYoutubeApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp.router(
      title: 'AI Cooking Platform',
      theme: AppTheme.light,
      routerConfig: AppRouter.router,
    );
  }
}
