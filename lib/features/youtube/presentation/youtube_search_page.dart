import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:youtube_recipe_search/youtube_recipe_search.dart';

import '../../../core/config/env.dart';
import '../data/supabase_youtube_search_transport.dart';
import '../data/youtube_recipe_creation_service.dart';

class YoutubeSearchPage extends StatefulWidget {
  const YoutubeSearchPage({
    super.key,
    this.transport,
    this.creationService,
    this.enabled = Env.youtubeSearchEnabled,
    this.initialQuery,
  });

  final YoutubeSearchTransport? transport;
  final YoutubeRecipeCreationService? creationService;
  final bool enabled;
  final String? initialQuery;

  @override
  State<YoutubeSearchPage> createState() => _YoutubeSearchPageState();
}

class _YoutubeSearchPageState extends State<YoutubeSearchPage> {
  late final YoutubeSearchController _controller;
  late final YoutubeRecipeCreationService _creationService;

  @override
  void initState() {
    super.initState();

    final transport = widget.transport ?? SupabaseYoutubeSearchTransport();

    _controller = YoutubeSearchController(
      YoutubeSearchClient(transport),
    );

    _creationService = widget.creationService ?? YoutubeRecipeCreationService();
  }

  bool _isAuthenticated() {
    try {
      return Supabase.instance.client.auth.currentUser != null;
    } catch (_) {
      return false;
    }
  }

  Future<void> _openYoutubeUrl(String rawUrl) async {
    if (!widget.enabled) {
      return;
    }

    final uri = Uri.tryParse(rawUrl);

    if (uri == null || !_isAllowedYoutubeUri(uri)) {
      _showMessage('이 YouTube 링크를 열 수 없습니다.');
      return;
    }

    try {
      final opened = await launchUrl(
        uri,
        mode: LaunchMode.externalApplication,
      );

      if (!opened && mounted) {
        _showMessage('YouTube를 열 수 없습니다.');
      }
    } catch (_) {
      if (mounted) {
        _showMessage('YouTube를 열 수 없습니다.');
      }
    }
  }

  Future<void> _createRecipeFromYoutube({
    required String title,
    required String channelTitle,
    required String youtubeUrl,
  }) async {
    if (!widget.enabled) {
      return;
    }

    try {
      final result = await _creationService.createDraftFromYoutube(
        YoutubeRecipeDraftInput(
          title: title,
          channelTitle: channelTitle,
          youtubeUrl: youtubeUrl,
        ),
      );

      if (!mounted) {
        return;
      }

      _showMessage('내 레시피에 저장했습니다.');

      context.go('/creator/${Uri.encodeComponent(result.recipeId)}');
    } on YoutubeRecipeCreationException catch (error) {
      if (!mounted) {
        return;
      }

      _showMessage(error.message);
    } catch (_) {
      if (!mounted) {
        return;
      }

      _showMessage('레시피 생성 중 오류가 발생했습니다.');
    }
  }

  bool _isAllowedYoutubeUri(Uri uri) {
    if (uri.scheme != 'https') {
      return false;
    }

    final host = uri.host.toLowerCase();

    return host == 'youtube.com' ||
        host.endsWith('.youtube.com') ||
        host == 'youtu.be' ||
        host.endsWith('.youtu.be');
  }

  void _showMessage(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message)),
    );
  }

  Widget _buildLoginRequiredScreen(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('YouTube'),
      ),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 420),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: <Widget>[
                const Icon(
                  Icons.lock_outline,
                  size: 52,
                ),
                const SizedBox(height: 16),
                const Text(
                  'YouTube 레시피 검색은 로그인 후 사용할 수 있습니다.',
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 20),
                FilledButton(
                  onPressed: () => context.go('/login'),
                  child: const Text('로그인하기'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.enabled) {
      return Scaffold(
        appBar: AppBar(
          title: const Text('YouTube'),
        ),
        body: const Center(
          child: Padding(
            padding: EdgeInsets.all(24),
            child: Text(
              'YouTube 검색 기능은 현재 사용할 수 없습니다.',
              textAlign: TextAlign.center,
            ),
          ),
        ),
      );
    }

    if (!_isAuthenticated()) {
      return _buildLoginRequiredScreen(context);
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('YouTube'),
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: YoutubeRecipeSearchView(
            controller: _controller,
            enabled: widget.enabled,
            initialQuery: widget.initialQuery,
            autoSearchInitialQuery:
                (widget.initialQuery ?? '').trim().length >= 2,
            onOpenUrl: _openYoutubeUrl,
            onCreateRecipe: (item) => _createRecipeFromYoutube(
              title: item.title,
              channelTitle: item.channelTitle,
              youtubeUrl: item.youtubeUrl,
            ),
          ),
        ),
      ),
    );
  }
}
