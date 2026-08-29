import 'dart:async';

import 'package:flutter/material.dart';

import '../application/youtube_search_controller.dart';
import '../domain/youtube_search_exception.dart';
import '../domain/youtube_search_result.dart';

typedef YoutubeUrlOpener = Future<void> Function(String url);

typedef YoutubeRecipeCreator = Future<void> Function(
  YoutubeSearchResult result,
);

class YoutubeRecipeSearchView extends StatefulWidget {
  const YoutubeRecipeSearchView({
    super.key,
    required this.controller,
    required this.onOpenUrl,
    this.onCreateRecipe,
    this.enabled = true,
    this.initialQuery,
    this.autoSearchInitialQuery = false,
    this.debounce = const Duration(milliseconds: 700),
  });

  final YoutubeSearchController controller;
  final YoutubeUrlOpener onOpenUrl;
  final YoutubeRecipeCreator? onCreateRecipe;
  final bool enabled;
  final String? initialQuery;
  final bool autoSearchInitialQuery;
  final Duration debounce;

  @override
  State<YoutubeRecipeSearchView> createState() =>
      _YoutubeRecipeSearchViewState();
}

class _YoutubeRecipeSearchViewState extends State<YoutubeRecipeSearchView> {
  final TextEditingController _text = TextEditingController();

  Timer? _timer;
  List<YoutubeSearchResult>? _items;
  String? _error;
  String? _creatingRecipeVideoId;
  bool _loading = false;

  @override
  void initState() {
    super.initState();

    final initial = widget.initialQuery?.trim() ?? '';

    if (initial.isNotEmpty) {
      _text.text = initial;
    }

    if (widget.autoSearchInitialQuery && initial.length >= 2) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          _search();
        }
      });
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    _text.dispose();
    super.dispose();
  }

  void _schedule() {
    _timer?.cancel();
    _timer = Timer(widget.debounce, _search);
  }

  Future<void> _search() async {
    _timer?.cancel();

    if (!widget.enabled || _loading) {
      return;
    }

    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final page = await widget.controller.search(_text.text);

      if (!mounted) {
        return;
      }

      if (page != null) {
        setState(() {
          _items = page.items;
        });
      }
    } on YoutubeSearchException catch (error) {
      if (!mounted) {
        return;
      }

      setState(() {
        _error = error.code;
      });
    } catch (error) {
      if (!mounted) {
        return;
      }

      setState(() {
        _error = error.toString();
      });
    } finally {
      if (mounted) {
        setState(() {
          _loading = false;
        });
      }
    }
  }

  Future<void> _createRecipe(YoutubeSearchResult item) async {
    final creator = widget.onCreateRecipe;

    if (creator == null || !widget.enabled) {
      return;
    }

    setState(() {
      _creatingRecipeVideoId = item.videoId;
      _error = null;
    });

    try {
      await creator(item);
    } catch (error) {
      if (!mounted) {
        return;
      }

      setState(() {
        _error = error.toString();
      });
    } finally {
      if (mounted) {
        setState(() {
          _creatingRecipeVideoId = null;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final items = _items;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        TextField(
          key: const Key('youtube-search-input'),
          controller: _text,
          enabled: widget.enabled,
          onChanged: (_) => _schedule(),
          onSubmitted: (_) => _search(),
          decoration: InputDecoration(
            labelText: 'YouTube \uB808\uC2DC\uD53C \uAC80\uC0C9',
            suffixIcon: IconButton(
              key: const Key('youtube-search-submit'),
              onPressed: widget.enabled ? _search : null,
              icon: const Icon(Icons.search),
            ),
          ),
        ),
        const Padding(
          padding: EdgeInsets.only(top: 8),
          child: Text('검색 결과에는 재생시간 3분 이내 영상만 표시됩니다.'),
        ),
        if (!widget.enabled)
          const Padding(
            padding: EdgeInsets.only(top: 8),
            child: Text(
              'YouTube \uAC80\uC0C9\uC744 \uC0AC\uC6A9\uD560 \uC218 \uC5C6\uC2B5\uB2C8\uB2E4.',
            ),
          ),
        if (_loading)
          const Padding(
            padding: EdgeInsets.all(16),
            child: Center(
              child: CircularProgressIndicator(),
            ),
          ),
        if (_error != null)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Text(
              '\uAC80\uC0C9\uC5D0 \uC2E4\uD328\uD588\uC2B5\uB2C8\uB2E4. ($_error)',
              key: const Key('youtube-search-error'),
            ),
          ),
        if (!_loading && items != null && items.isEmpty)
          const Padding(
            padding: EdgeInsets.all(16),
            child: Text(
              '\uAC80\uC0C9 \uACB0\uACFC\uAC00 \uC5C6\uC2B5\uB2C8\uB2E4.',
              key: Key('youtube-search-empty'),
            ),
          ),
        if (items != null)
          Expanded(
            child: ListView.builder(
              padding: const EdgeInsets.only(top: 8, bottom: 24),
              itemCount: items.length,
              itemBuilder: (BuildContext context, int index) {
                final item = items[index];

                return _YoutubeSearchResultCard(
                  item: item,
                  canCreateRecipe:
                      widget.enabled && widget.onCreateRecipe != null,
                  isCreatingRecipe: _creatingRecipeVideoId == item.videoId,
                  onOpenUrl: () => widget.onOpenUrl(item.youtubeUrl),
                  onCreateRecipe: () => _createRecipe(item),
                );
              },
            ),
          ),
      ],
    );
  }
}

class _YoutubeSearchResultCard extends StatelessWidget {
  const _YoutubeSearchResultCard({
    required this.item,
    required this.canCreateRecipe,
    required this.isCreatingRecipe,
    required this.onOpenUrl,
    required this.onCreateRecipe,
  });

  final YoutubeSearchResult item;
  final bool canCreateRecipe;
  final bool isCreatingRecipe;
  final VoidCallback onOpenUrl;
  final VoidCallback onCreateRecipe;

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.symmetric(vertical: 6),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            ListTile(
              contentPadding: EdgeInsets.zero,
              title: Text(item.title),
              subtitle: Text(
                item.durationSec == null
                    ? item.channelTitle
                    : '${item.channelTitle} · ${_durationLabel(item.durationSec!)}',
              ),
              trailing: IconButton(
                tooltip: 'YouTube \uC5F4\uAE30',
                onPressed: onOpenUrl,
                icon: const Icon(Icons.open_in_new),
              ),
              onTap: onOpenUrl,
            ),
            if (canCreateRecipe)
              FilledButton.icon(
                key: Key('youtube-create-recipe-${item.videoId}'),
                onPressed: isCreatingRecipe ? null : onCreateRecipe,
                icon: isCreatingRecipe
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.restaurant_menu),
                label: Text(
                  isCreatingRecipe
                      ? '\uB808\uC2DC\uD53C \uC800\uC7A5 \uC911...'
                      : '\uC774 \uC601\uC0C1\uC73C\uB85C \uB808\uC2DC\uD53C \uB9CC\uB4E4\uAE30',
                ),
              ),
          ],
        ),
      ),
    );
  }

  String _durationLabel(int seconds) {
    final minutes = seconds ~/ 60;
    final remainder = seconds % 60;
    return '$minutes:${remainder.toString().padLeft(2, '0')}';
  }
}
