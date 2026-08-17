import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../kitchen/application/kitchen_providers.dart';
import '../../recipes/application/recipe_providers.dart';

class CookingCompletionFeedbackCard extends ConsumerStatefulWidget {
  const CookingCompletionFeedbackCard({
    super.key,
    required this.recipeType,
    required this.recipeId,
    required this.recipeTitle,
  });

  final String recipeType;
  final String recipeId;
  final String recipeTitle;

  @override
  ConsumerState<CookingCompletionFeedbackCard> createState() =>
      _CookingCompletionFeedbackCardState();
}

class _CookingCompletionFeedbackCardState
    extends ConsumerState<CookingCompletionFeedbackCard> {
  final TextEditingController _noteController = TextEditingController();

  int? _rating;
  bool? _liked;
  bool _isSubmitting = false;

  @override
  void dispose() {
    _noteController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_isSubmitting) {
      return;
    }

    setState(() {
      _isSubmitting = true;
    });

    try {
      await ref.read(kitchenApiProvider).completeCook(
            recipeType: widget.recipeType,
            recipeId: widget.recipeId,
            recipeTitle: widget.recipeTitle,
            rating: _rating,
            liked: _liked,
            note: _noteController.text,
          );

      ref.invalidate(kitchenSummaryProvider);
      ref.invalidate(kitchenCookSessionsProvider);

      if (!mounted) {
        return;
      }

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('조리 완료 기록을 저장했습니다.'),
          duration: Duration(seconds: 3),
        ),
      );

      setState(() {
        _rating = null;
        _liked = null;
        _noteController.clear();
      });
    } catch (_) {
      if (!mounted) {
        return;
      }

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('조리 완료 기록을 저장하지 못했습니다. 다시 시도해 주세요.'),
        ),
      );
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
    return Card(
      elevation: 0,
      color: Theme.of(context).colorScheme.surfaceContainerHighest,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Text(
              '조리 완료 피드백',
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: <Widget>[
                ChoiceChip(
                  label: const Text('좋아요'),
                  selected: _liked == true,
                  onSelected: _isSubmitting
                      ? null
                      : (selected) {
                          setState(() {
                            _liked = selected ? true : null;
                          });
                        },
                ),
                ChoiceChip(
                  label: const Text('아쉬워요'),
                  selected: _liked == false,
                  onSelected: _isSubmitting
                      ? null
                      : (selected) {
                          setState(() {
                            _liked = selected ? false : null;
                          });
                        },
                ),
              ],
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<int>(
              initialValue: _rating,
              decoration: const InputDecoration(
                border: OutlineInputBorder(),
                labelText: '평점 (선택)',
              ),
              hint: const Text('평점을 선택하세요'),
              items: const <DropdownMenuItem<int>>[
                DropdownMenuItem(value: 1, child: Text('1점')),
                DropdownMenuItem(value: 2, child: Text('2점')),
                DropdownMenuItem(value: 3, child: Text('3점')),
                DropdownMenuItem(value: 4, child: Text('4점')),
                DropdownMenuItem(value: 5, child: Text('5점')),
              ],
              onChanged: _isSubmitting
                  ? null
                  : (value) {
                      setState(() {
                        _rating = value;
                      });
                    },
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _noteController,
              enabled: !_isSubmitting,
              minLines: 1,
              maxLines: 3,
              decoration: const InputDecoration(
                border: OutlineInputBorder(),
                labelText: '한 줄 메모 (선택)',
                hintText: '다음 요리를 위한 메모를 남겨 보세요.',
              ),
            ),
            const SizedBox(height: 12),
            Align(
              alignment: Alignment.centerRight,
              child: FilledButton.icon(
                onPressed: _isSubmitting ? null : _submit,
                icon: _isSubmitting
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.task_alt),
                label: Text(_isSubmitting ? '기록 중...' : '조리 완료 기록'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
