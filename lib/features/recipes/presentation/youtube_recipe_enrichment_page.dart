import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../application/recipe_enrichment_service.dart';
import '../domain/recipe.dart';
import '../domain/recipe_enrichment_suggestion.dart';
import 'create_creator_recipe_page.dart';

class YoutubeRecipeEnrichmentPage extends ConsumerStatefulWidget {
  const YoutubeRecipeEnrichmentPage({
    super.key,
    required this.recipe,
  });

  final Recipe recipe;

  @override
  ConsumerState<YoutubeRecipeEnrichmentPage> createState() =>
      _YoutubeRecipeEnrichmentPageState();
}

class _YoutubeRecipeEnrichmentPageState
    extends ConsumerState<YoutubeRecipeEnrichmentPage> {
  bool _isGenerating = true;
  String? _error;
  RecipeEnrichmentSuggestion? _suggestion;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _generate());
  }

  Future<void> _generate() async {
    setState(() {
      _isGenerating = true;
      _error = null;
    });

    try {
      final suggestion = await RecipeEnrichmentService()
          .createSuggestionFromSelectedYoutubeVideo(
        recipe: widget.recipe,
      );

      if (!mounted) return;

      setState(() {
        _suggestion = suggestion;
      });

      await _openEditor(suggestion);
    } on RecipeEnrichmentException catch (error) {
      if (mounted) setState(() => _error = error.message);
    } catch (_) {
      if (mounted) {
        setState(() => _error = '영상 기반 AI 레시피 보강 중 오류가 발생했습니다.');
      }
    } finally {
      if (mounted) setState(() => _isGenerating = false);
    }
  }

  Future<void> _openEditor(RecipeEnrichmentSuggestion suggestion) async {
    final result = await Navigator.of(context).push<Object?>(
      MaterialPageRoute<Object?>(
        builder: (_) => CreateCreatorRecipePage(
          initialRecipe: suggestion.toDraftRecipe(sourceRecipe: widget.recipe),
          returnCreatedRecipeId: true,
        ),
      ),
    );

    if (result is String && result.trim().isNotEmpty && mounted) {
      Navigator.of(context).pop(result);
    }
  }

  @override
  Widget build(BuildContext context) {
    final youtubeUrl = widget.recipe.youtubeUrl?.trim() ?? '';
    final suggestion = _suggestion;

    return Scaffold(
      appBar: AppBar(
        title: const Text('AI 레시피 초안 만들기'),
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: <Widget>[
            Text(
              widget.recipe.title,
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 12),
            const Text(
              '선택한 3분 이내 YouTube 영상만 분석해 편집 가능한 초안을 '
              '만듭니다. 공공 레시피나 다른 영상은 검색하지 않습니다.',
            ),
            const SizedBox(height: 16),
            if (youtubeUrl.isNotEmpty)
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: SelectableText(youtubeUrl),
                ),
              ),
            const SizedBox(height: 20),
            if (suggestion == null) ...<Widget>[
              if (_isGenerating) ...<Widget>[
                const Center(child: CircularProgressIndicator()),
                const SizedBox(height: 12),
                const Text(
                  '영상에서 제목·재료·조리 순서·팁을 정리하고 있습니다...',
                  textAlign: TextAlign.center,
                ),
              ],
              if (_error != null)
                Text(
                  _error!,
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
              if (_error != null) ...<Widget>[
                const SizedBox(height: 12),
                FilledButton.icon(
                  onPressed: _isGenerating ? null : _generate,
                  icon: const Icon(Icons.refresh),
                  label: const Text('다시 시도'),
                ),
              ],
            ] else ...<Widget>[
              Text(
                suggestion.title,
                style: Theme.of(context).textTheme.titleLarge,
              ),
              const SizedBox(height: 8),
              Text(suggestion.summary),
              const SizedBox(height: 16),
              Text('재료', style: Theme.of(context).textTheme.titleMedium),
              ...suggestion.ingredients.map((item) => Text('• $item')),
              const SizedBox(height: 16),
              Text('조리 순서', style: Theme.of(context).textTheme.titleMedium),
              ...suggestion.steps
                  .asMap()
                  .entries
                  .map((entry) => Text('${entry.key + 1}. ${entry.value}')),
              if ((suggestion.tips ?? '').trim().isNotEmpty) ...<Widget>[
                const SizedBox(height: 16),
                Text('팁', style: Theme.of(context).textTheme.titleMedium),
                Text(suggestion.tips!),
              ],
              if (suggestion.warnings.isNotEmpty) ...<Widget>[
                const SizedBox(height: 16),
                Text(
                  '사용자 확인사항',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                ...suggestion.warnings.map((item) => Text('• $item')),
              ],
              const SizedBox(height: 20),
              FilledButton.icon(
                onPressed: () => _openEditor(suggestion),
                icon: const Icon(Icons.edit_outlined),
                label: const Text('초안 수정 후 저장'),
              ),
              OutlinedButton(
                onPressed: () => _openEditor(suggestion),
                child: const Text('편집 화면 다시 열기'),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
