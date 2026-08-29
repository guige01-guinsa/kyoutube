import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:youtube_recipe_search/youtube_recipe_search.dart';

import '../../../core/config/env.dart';
import '../../recipes/domain/recipe.dart';
import '../../recipes/presentation/youtube_recipe_enrichment_page.dart';
import '../data/supabase_youtube_search_transport.dart';
import '../domain/youtube_thumbnail_url.dart';

class YoutubeSearchPage extends StatefulWidget {
  const YoutubeSearchPage({
    super.key,
    this.transport,
    this.enabled = Env.youtubeSearchEnabled,
    this.initialQuery,
  });

  final YoutubeSearchTransport? transport;
  final bool enabled;
  final String? initialQuery;

  @override
  State<YoutubeSearchPage> createState() => _YoutubeSearchPageState();
}

class _YoutubeSearchPageState extends State<YoutubeSearchPage> {
  late final YoutubeSearchController _controller;

  @override
  void initState() {
    super.initState();

    final transport = widget.transport ?? SupabaseYoutubeSearchTransport();

    _controller = YoutubeSearchController(
      YoutubeSearchClient(transport),
    );

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

    final normalizedTitle = title.trim();
    final normalizedYoutubeUrl = youtubeUrl.trim();

    if (normalizedTitle.isEmpty || normalizedYoutubeUrl.isEmpty) {
      _showMessage('영상 정보를 확인할 수 없습니다.');
      return;
    }

    final sourceRecipe = Recipe(
      id: '',
      title: normalizedTitle,
      summary: channelTitle.trim().isEmpty
          ? '선택한 YouTube 영상 기반 레시피'
          : '선택한 YouTube 영상 기반 레시피 · ${channelTitle.trim()}',
      ingredients: const <String>[],
      steps: const <String>[],
      imageUrl: youtubeThumbnailUrlFromUrl(normalizedYoutubeUrl),
      youtubeUrl: normalizedYoutubeUrl,
      sourceType: 'youtube_import',
    );

    final createdRecipeId = await Navigator.of(context).push<Object?>(
      MaterialPageRoute<Object?>(
        builder: (_) => YoutubeRecipeEnrichmentPage(recipe: sourceRecipe),
      ),
    );

    if (createdRecipeId is String &&
        createdRecipeId.trim().isNotEmpty &&
        mounted) {
      _showMessage('내 레시피에 저장했습니다.');
      context.go('/creator/${Uri.encodeComponent(createdRecipeId)}');
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
