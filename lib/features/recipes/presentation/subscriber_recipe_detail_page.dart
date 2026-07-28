import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:http/http.dart' as http;

import '../../ai/application/ai_service.dart';
import '../../kitchen/application/kitchen_providers.dart';
import '../application/recipe_providers.dart';
import '../domain/recipe.dart';
import 'youtube_link_card.dart';

class _PromotionOptions {
  const _PromotionOptions({
    required this.mode,
    required this.includeSummary,
    required this.includeYoutubeUrl,
    required this.includeImageUrl,
    required this.includeNotesAsTips,
  });

  final String mode;
  final bool includeSummary;
  final bool includeYoutubeUrl;
  final bool includeImageUrl;
  final bool includeNotesAsTips;
}

class SubscriberRecipeDetailPage extends ConsumerStatefulWidget {
  const SubscriberRecipeDetailPage({super.key, required this.recipeId});

  final String recipeId;

  @override
  ConsumerState<SubscriberRecipeDetailPage> createState() =>
      _SubscriberRecipeDetailPageState();
}

class _SubscriberRecipeDetailPageState
    extends ConsumerState<SubscriberRecipeDetailPage> {
  final AiService _aiService = AiService();
  bool _isPromoting = false;

  bool _isSessionProblem(Object error) {
    final message = error.toString();
    return message.contains('로그인이 필요') ||
        message.contains('401') ||
        message.toLowerCase().contains('unauthorized') ||
        message.toLowerCase().contains('jwt');
  }

  bool _isNetworkProblem(Object error) {
    final message = error.toString().toLowerCase();
    return message.contains('socketexception') ||
        message.contains('failed host lookup') ||
        message.contains('connection refused') ||
        message.contains('network');
  }

  String _friendlyPromotionError(Object error) {
    final message = error.toString();
    if (_isSessionProblem(error)) {
      return '로그인이 필요합니다. 다시 로그인 후 승격해 주세요.';
    }
    if (_isNetworkProblem(error)) {
      return '네트워크 연결을 확인한 뒤 다시 시도해 주세요.';
    }
    if (message.contains('UnsupportedError') || message.contains('미구현')) {
      return '현재 환경에서는 승격을 처리할 수 없습니다.';
    }
    return '승격에 실패했습니다. 잠시 후 다시 시도해 주세요.';
  }

  String? _sourceLabel(Recipe recipe) {
    final type = (recipe.sourceType ?? '').trim();
    if (type == RecipeSourceType.publicImport) {
      return '공공레시피 복사';
    }
    if (type == RecipeSourceType.youtubeImport) {
      return 'YouTube 가져오기';
    }
    if (type == RecipeSourceType.creatorCopy) {
      return '크리에이터 복사';
    }
    return null;
  }

  Future<void> _deleteRecipe(Recipe recipe) async {
    final repository = ref.read(recipeRepositoryProvider);
    final container = ProviderScope.containerOf(context, listen: false);
    final messenger = ScaffoldMessenger.of(context);

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: const Text('개인 레시피 삭제'),
          content: const Text('이 개인 레시피를 삭제하시겠습니까?'),
          actions: <Widget>[
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('취소'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(context).pop(true),
              child: const Text('삭제'),
            ),
          ],
        );
      },
    );

    if (confirmed != true) {
      return;
    }

    try {
      await repository.deleteSubscriberRecipe(recipe.id);
      ref.invalidate(subscriberRecipesProvider);

      if (!mounted) {
        return;
      }

      messenger.showSnackBar(
        SnackBar(
          content: const Text('개인 레시피를 삭제했습니다.'),
          action: SnackBarAction(
            label: '되돌리기',
            onPressed: () async {
              try {
                await repository.createSubscriberRecipe(
                  title: recipe.title,
                  summary: recipe.summary,
                  ingredients: recipe.ingredients,
                  steps: recipe.steps,
                  notes: recipe.notes,
                  imageUrl: recipe.imageUrl,
                  youtubeUrl: recipe.youtubeUrl,
                  sourceType: recipe.sourceType,
                );
                container.invalidate(subscriberRecipesProvider);
                messenger.showSnackBar(
                  const SnackBar(content: Text('삭제를 되돌렸습니다.')),
                );
              } catch (undoErr) {
                messenger.showSnackBar(
                  SnackBar(
                    content: Text('삭제 되돌리기에 실패했습니다.\n$undoErr'),
                  ),
                );
              }
            },
          ),
          duration: const Duration(seconds: 8),
        ),
      );

      Navigator.of(context).pop(true);
    } catch (err) {
      if (!mounted) {
        return;
      }

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('개인 레시피 삭제에 실패했습니다.\n$err')),
      );
    }
  }

  List<String> _splitLines(String input) {
    return input
        .split(RegExp(r'[\r\n,]+'))
        .map((String value) => value.trim())
        .where((String value) => value.isNotEmpty)
        .toList();
  }

  String _joinLines(List<String> values) {
    return values.join('\n');
  }

  Future<void> _editRecipe(Recipe recipe) async {
    final titleController = TextEditingController(text: recipe.title);
    final summaryController = TextEditingController(text: recipe.summary ?? '');
    final ingredientsController =
        TextEditingController(text: _joinLines(recipe.ingredients));
    final stepsController = TextEditingController(text: _joinLines(recipe.steps));
    final notesController = TextEditingController(text: recipe.notes ?? '');
    final imageUrlController = TextEditingController(text: recipe.imageUrl ?? '');
    final youtubeUrlController =
      TextEditingController(text: recipe.youtubeUrl ?? '');
    final formKey = GlobalKey<FormState>();
    var isSubmitting = false;
    var isAutoFilling = false;
    var isResolvingYoutubeMeta = false;
    String? submitError;
    String? youtubeChannelTitle;
    String? youtubeVideoTitle;
    String? autoFillSummary;

    final updated = await showDialog<bool>(
      context: context,
      builder: (BuildContext context) {
        return StatefulBuilder(
          builder: (BuildContext context, StateSetter setDialogState) {
            Future<void> resolveYoutubeMetadata({
              bool showError = false,
            }) async {
              final youtubeUrl = youtubeUrlController.text.trim();
              if (youtubeUrl.isEmpty) {
                setDialogState(() {
                  youtubeChannelTitle = null;
                  youtubeVideoTitle = null;
                });
                return;
              }

              setDialogState(() {
                isResolvingYoutubeMeta = true;
              });

              try {
                final endpoint =
                    Uri.https('www.youtube.com', '/oembed', <String, String>{
                  'url': youtubeUrl,
                  'format': 'json',
                });
                final response = await http
                    .get(endpoint)
                    .timeout(const Duration(seconds: 6));

                if (response.statusCode < 200 || response.statusCode >= 300) {
                  throw StateError('메타데이터 조회 실패(${response.statusCode})');
                }

                final decoded = jsonDecode(response.body);
                if (decoded is! Map<String, dynamic>) {
                  throw const FormatException('invalid_oembed_payload');
                }

                final channel = (decoded['author_name'] ?? '').toString().trim();
                final videoTitle = (decoded['title'] ?? '').toString().trim();

                setDialogState(() {
                  youtubeChannelTitle = channel.isEmpty ? null : channel;
                  youtubeVideoTitle = videoTitle.isEmpty ? null : videoTitle;
                });
              } catch (error) {
                setDialogState(() {
                  youtubeChannelTitle = null;
                  youtubeVideoTitle = null;
                });

                if (showError && context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text('YouTube 메타데이터 조회에 실패했습니다: $error')),
                  );
                }
              } finally {
                setDialogState(() {
                  isResolvingYoutubeMeta = false;
                });
              }
            }

            Future<void> autoFillFromYoutube() async {
              final title = titleController.text.trim();
              final youtubeUrl = youtubeUrlController.text.trim();

              if (title.isEmpty && youtubeUrl.isEmpty) {
                setDialogState(() {
                  submitError = '제목 또는 YouTube URL을 입력해 주세요.';
                });
                return;
              }

              setDialogState(() {
                isAutoFilling = true;
                submitError = null;
                autoFillSummary = null;
              });

              try {
                await resolveYoutubeMetadata(showError: false);

                final beforeIngredientsCount =
                    _splitLines(ingredientsController.text).length;
                final beforeStepsCount = _splitLines(stepsController.text).length;
                final beforeSummaryLength = summaryController.text.trim().length;

                final draft = await _aiService.generateRecipeDraftFromYoutube(
                  title: title.isNotEmpty
                      ? title
                      : (youtubeVideoTitle ?? '').trim(),
                  summary: summaryController.text.trim(),
                  youtubeUrl: youtubeUrl,
                  channelTitle: (youtubeChannelTitle ?? '').trim(),
                );

                summaryController.text = draft.summary;
                ingredientsController.text = draft.ingredients.join('\n');
                stepsController.text = draft.steps.join('\n');
                if (draft.tips.isNotEmpty) {
                  notesController.text = draft.tips.join('\n');
                }

                final afterIngredientsCount =
                    _splitLines(ingredientsController.text).length;
                final afterStepsCount = _splitLines(stepsController.text).length;
                final afterSummaryLength = summaryController.text.trim().length;

                setDialogState(() {
                  autoFillSummary =
                      '요약 $beforeSummaryLength자 -> $afterSummaryLength자 | '
                      '재료 $beforeIngredientsCount개 -> $afterIngredientsCount개 | '
                      '조리 순서 $beforeStepsCount개 -> $afterStepsCount개';
                });

                if (context.mounted) {
                  final note = draft.degraded ? ' (보조 초안)' : '';
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text('AI 자동 채움이 완료되었습니다$note.')),
                  );
                }
              } catch (error) {
                setDialogState(() {
                  submitError = 'AI 자동 채움에 실패했습니다. $error';
                });
              } finally {
                setDialogState(() {
                  isAutoFilling = false;
                });
              }
            }

            return AlertDialog(
              title: const Text('개인 레시피 편집'),
              content: SingleChildScrollView(
                child: Form(
                  key: formKey,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      TextFormField(
                        controller: titleController,
                        decoration: const InputDecoration(
                          labelText: '제목',
                          border: OutlineInputBorder(),
                        ),
                        validator: (String? value) {
                          if ((value ?? '').trim().isEmpty) {
                            return '제목을 입력해 주세요.';
                          }
                          return null;
                        },
                      ),
                      const SizedBox(height: 12),
                      TextFormField(
                        controller: ingredientsController,
                        maxLines: 5,
                        decoration: const InputDecoration(
                          labelText: '재료',
                          hintText: '한 줄에 하나씩 입력',
                          border: OutlineInputBorder(),
                        ),
                        validator: (String? value) {
                          if (_splitLines(value ?? '').isEmpty) {
                            return '재료를 1개 이상 입력해 주세요.';
                          }
                          return null;
                        },
                      ),
                      const SizedBox(height: 12),
                      TextFormField(
                        controller: summaryController,
                        maxLines: 3,
                        decoration: const InputDecoration(
                          labelText: '요약(선택)',
                          border: OutlineInputBorder(),
                        ),
                      ),
                      const SizedBox(height: 12),
                      TextFormField(
                        controller: stepsController,
                        maxLines: 6,
                        decoration: const InputDecoration(
                          labelText: '조리 순서',
                          hintText: '한 줄에 하나씩 입력',
                          border: OutlineInputBorder(),
                        ),
                        validator: (String? value) {
                          if (_splitLines(value ?? '').isEmpty) {
                            return '조리 순서를 1개 이상 입력해 주세요.';
                          }
                          return null;
                        },
                      ),
                      const SizedBox(height: 12),
                      TextFormField(
                        controller: notesController,
                        maxLines: 4,
                        decoration: const InputDecoration(
                          labelText: '내 메모',
                          border: OutlineInputBorder(),
                        ),
                      ),
                      const SizedBox(height: 12),
                      TextFormField(
                        controller: imageUrlController,
                        decoration: const InputDecoration(
                          labelText: '이미지 URL(선택)',
                          border: OutlineInputBorder(),
                        ),
                      ),
                      const SizedBox(height: 12),
                      TextFormField(
                        controller: youtubeUrlController,
                        decoration: InputDecoration(
                          labelText: 'YouTube URL(선택)',
                          border: const OutlineInputBorder(),
                          suffixIcon: isResolvingYoutubeMeta
                              ? const Padding(
                                  padding: EdgeInsets.all(12),
                                  child: SizedBox(
                                    width: 16,
                                    height: 16,
                                    child: CircularProgressIndicator(strokeWidth: 2),
                                  ),
                                )
                              : IconButton(
                                  onPressed: () => resolveYoutubeMetadata(showError: true),
                                  icon: const Icon(Icons.refresh),
                                  tooltip: '메타데이터 다시 조회',
                                ),
                        ),
                        onEditingComplete: () {
                          FocusScope.of(context).nextFocus();
                          unawaited(resolveYoutubeMetadata());
                        },
                      ),
                      if ((youtubeChannelTitle ?? '').isNotEmpty ||
                          (youtubeVideoTitle ?? '').isNotEmpty) ...<Widget>[
                        const SizedBox(height: 8),
                        Container(
                          width: double.infinity,
                          padding: const EdgeInsets.all(10),
                          decoration: BoxDecoration(
                            color: Theme.of(context)
                                .colorScheme
                                .tertiaryContainer
                                .withValues(alpha: 0.35),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: <Widget>[
                              Text(
                                'YouTube 메타데이터',
                                style: Theme.of(context).textTheme.labelLarge,
                              ),
                              const SizedBox(height: 4),
                              if ((youtubeChannelTitle ?? '').isNotEmpty)
                                Text('채널: ${youtubeChannelTitle!}'),
                              if ((youtubeVideoTitle ?? '').isNotEmpty)
                                Text('영상 제목: ${youtubeVideoTitle!}'),
                            ],
                          ),
                        ),
                      ],
                      const SizedBox(height: 8),
                      OutlinedButton.icon(
                        onPressed: (isSubmitting || isAutoFilling)
                            ? null
                            : autoFillFromYoutube,
                        icon: isAutoFilling
                            ? const SizedBox(
                                width: 16,
                                height: 16,
                                child: CircularProgressIndicator(strokeWidth: 2),
                              )
                            : const Icon(Icons.auto_awesome_outlined),
                        label: Text(
                          isAutoFilling ? 'AI 초안 생성 중...' : 'YouTube 기반 AI 자동 채움',
                        ),
                      ),
                      if ((autoFillSummary ?? '').isNotEmpty) ...<Widget>[
                        const SizedBox(height: 8),
                        Text(
                          autoFillSummary!,
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                      ],
                      if (submitError != null) ...<Widget>[
                        const SizedBox(height: 8),
                        Text(
                          submitError!,
                          style: TextStyle(
                            color: Theme.of(context).colorScheme.error,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
              actions: <Widget>[
                TextButton(
                  onPressed: isSubmitting
                      ? null
                      : () {
                          Navigator.of(context).pop(false);
                        },
                  child: const Text('취소'),
                ),
                FilledButton(
                  onPressed: isSubmitting
                      ? null
                      : () async {
                          if (formKey.currentState?.validate() != true) {
                            return;
                          }

                          setDialogState(() {
                            isSubmitting = true;
                            submitError = null;
                          });

                          try {
                            final repository = ref.read(recipeRepositoryProvider);
                            await repository.updateSubscriberRecipe(
                              id: recipe.id,
                              title: titleController.text.trim(),
                              summary: summaryController.text,
                              ingredients:
                                  _splitLines(ingredientsController.text),
                              steps: _splitLines(stepsController.text),
                              notes: notesController.text,
                              imageUrl: imageUrlController.text,
                              youtubeUrl: youtubeUrlController.text,
                            );
                            if (!context.mounted) {
                              return;
                            }
                            Navigator.of(context).pop(true);
                          } catch (err) {
                            setDialogState(() {
                              isSubmitting = false;
                              submitError = '저장에 실패했습니다. $err';
                            });
                          }
                        },
                  child: Text(isSubmitting ? '저장 중...' : '저장'),
                ),
              ],
            );
          },
        );
      },
    );

    // Intentionally do not manually dispose dialog-local controllers here.
    // On some device timing paths, immediate disposal can race with EditableText
    // detach and trigger framework assertion (_dependents.isEmpty).

    if (updated != true) {
      return;
    }

    ref.invalidate(subscriberRecipeByIdProvider(widget.recipeId));
    ref.invalidate(subscriberRecipesProvider);
    if (!mounted) {
      return;
    }
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('개인 레시피를 저장했습니다.')),
    );
  }

  Future<void> _promoteRecipe(Recipe recipe) async {
    final hasSummary = (recipe.summary ?? '').trim().isNotEmpty;
    final hasYoutubeUrl = (recipe.youtubeUrl ?? '').trim().isNotEmpty;
    final hasImageUrl = (recipe.imageUrl ?? '').trim().isNotEmpty;
    final hasNotes = (recipe.notes ?? '').trim().isNotEmpty;

    final options = await showDialog<_PromotionOptions>(
      context: context,
      builder: (BuildContext context) {
        var mode = 'copy';
        var includeSummary = hasSummary;
        var includeYoutubeUrl = hasYoutubeUrl;
        var includeImageUrl = hasImageUrl;
        var includeNotesAsTips = hasNotes;

        return StatefulBuilder(
          builder: (BuildContext context, StateSetter setDialogState) {
            return AlertDialog(
              title: const Text('내 레시피로 승격'),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Theme.of(context)
                            .colorScheme
                            .surfaceContainerHighest,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: const Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: <Widget>[
                          Text(
                            '승격 방식 안내',
                            style: TextStyle(fontWeight: FontWeight.w700),
                          ),
                          SizedBox(height: 6),
                          Text('복사 승격: 개인 레시피를 남겨두고 크리에이터 레시피를 추가 생성합니다.'),
                          SizedBox(height: 4),
                          Text('이동 승격: 개인 레시피를 크리에이터로 옮기고 개인 레시피를 삭제합니다.'),
                        ],
                      ),
                    ),
                    const SizedBox(height: 12),
                    SegmentedButton<String>(
                      segments: const <ButtonSegment<String>>[
                        ButtonSegment<String>(
                          value: 'copy',
                          label: Text('복사 승격'),
                        ),
                        ButtonSegment<String>(
                          value: 'move',
                          label: Text('이동 승격'),
                        ),
                      ],
                      selected: <String>{mode},
                      onSelectionChanged: (Set<String> selected) {
                        if (selected.isEmpty) {
                          return;
                        }
                        setDialogState(() {
                          mode = selected.first;
                        });
                      },
                    ),
                    const SizedBox(height: 8),
                    Text(
                      mode == 'move'
                          ? '현재 선택: 이동 승격 (승격 후 개인 레시피가 삭제됩니다)'
                          : '현재 선택: 복사 승격 (승격 후 개인 레시피가 유지됩니다)',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                    const SizedBox(height: 12),
                    SwitchListTile(
                      value: includeSummary,
                      onChanged: hasSummary
                          ? (bool value) {
                              setDialogState(() {
                                includeSummary = value;
                              });
                            }
                          : null,
                      title: const Text('요약 포함'),
                      subtitle: Text(hasSummary ? 'summary 사용' : '저장된 요약 없음'),
                      contentPadding: EdgeInsets.zero,
                    ),
                    SwitchListTile(
                      value: includeYoutubeUrl,
                      onChanged: hasYoutubeUrl
                          ? (bool value) {
                              setDialogState(() {
                                includeYoutubeUrl = value;
                              });
                            }
                          : null,
                      title: const Text('YouTube 링크 포함'),
                      subtitle: Text(
                        hasYoutubeUrl ? 'youtube_url 사용' : '저장된 YouTube URL 없음',
                      ),
                      contentPadding: EdgeInsets.zero,
                    ),
                    SwitchListTile(
                      value: includeImageUrl,
                      onChanged: hasImageUrl
                          ? (bool value) {
                              setDialogState(() {
                                includeImageUrl = value;
                              });
                            }
                          : null,
                      title: const Text('이미지 URL 포함'),
                      subtitle: Text(hasImageUrl ? 'image_url 사용' : '저장된 이미지 URL 없음'),
                      contentPadding: EdgeInsets.zero,
                    ),
                    SwitchListTile(
                      value: includeNotesAsTips,
                      onChanged: hasNotes
                          ? (bool value) {
                              setDialogState(() {
                                includeNotesAsTips = value;
                              });
                            }
                          : null,
                      title: const Text('메모를 팁으로 포함'),
                      subtitle: Text(hasNotes ? 'notes -> tips' : '저장된 메모 없음'),
                      contentPadding: EdgeInsets.zero,
                    ),
                  ],
                ),
              ),
              actions: <Widget>[
                TextButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: const Text('취소'),
                ),
                FilledButton(
                  onPressed: () {
                    Navigator.of(context).pop(
                      _PromotionOptions(
                        mode: mode,
                        includeSummary: includeSummary,
                        includeYoutubeUrl: includeYoutubeUrl,
                        includeImageUrl: includeImageUrl,
                        includeNotesAsTips: includeNotesAsTips,
                      ),
                    );
                  },
                  child: const Text('승격 실행'),
                ),
              ],
            );
          },
        );
      },
    );

    if (options == null) {
      return;
    }

    setState(() {
      _isPromoting = true;
    });

    try {
      final repository = ref.read(recipeRepositoryProvider);
      final creatorRecipe = await repository.promoteSubscriberRecipeToCreator(
        id: recipe.id,
        deleteSource: options.mode == 'move',
        includeSummary: options.includeSummary,
        includeYoutubeUrl: options.includeYoutubeUrl,
        includeImageUrl: options.includeImageUrl,
        includeNotesAsTips: options.includeNotesAsTips,
      );

      ref.invalidate(subscriberRecipesProvider);
      ref.invalidate(subscriberRecipeByIdProvider(widget.recipeId));
      ref.invalidate(creatorRecipesProvider(''));
      ref.invalidate(creatorRecipeByIdProvider(creatorRecipe.id));

      if (!mounted) {
        return;
      }

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            options.mode == 'move' ? '내 레시피로 이동했습니다.' : '내 레시피로 복사했습니다.',
          ),
        ),
      );
      context.push('/creator/${creatorRecipe.id}');
    } catch (err) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(_friendlyPromotionError(err))),
      );
    } finally {
      if (mounted) {
        setState(() {
          _isPromoting = false;
        });
      }
    }
  }

  Future<void> _createShoppingListFromRecipe(Recipe recipe) async {
    if (recipe.ingredients.isEmpty) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('재료 정보가 없어 장보기 목록을 만들 수 없습니다.')),
      );
      return;
    }

    try {
      final repository = ref.read(recipeRepositoryProvider);
      final result = await repository.createKitchenShoppingFromRecipe(
        recipeType: 'user',
        recipe: recipe,
      );

      ref.invalidate(kitchenSummaryProvider);
      ref.invalidate(kitchenShoppingListsProvider(kitchenDefaultShoppingListsQuery));

      if (!mounted) {
        return;
      }

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            result.reopenedFromCompleted
                ? '완료된 장보기를 다시 열었습니다. 부족 재료 ${result.missingCount}개'
                : result.resetFromFullyChecked
                    ? '이전 장보기를 다시 시작합니다. 체크를 초기화했습니다.'
                : result.noMissingItems
                  ? '이미 보유 중인 재료라 장보기 항목이 없습니다.'
                  : result.reusedActiveList
                    ? '기존 장보기 리스트를 이어서 사용합니다. 남은 항목 ${result.missingCount}개'
                        : result.missingCount > 0
                            ? '장보기 리스트를 만들었습니다. 부족 재료 ${result.missingCount}개'
                            : '장보기 리스트를 만들었습니다. 현재 부족 재료는 없습니다.',
          ),
          duration: const Duration(seconds: 3),
        ),
      );
      context.push('/kitchen');
    } catch (err) {
      if (!mounted) {
        return;
      }

      if (_isSessionProblem(err)) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('장보기 추가 기능을 사용할 수 없습니다.')),
        );
        return;
      }

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('장보기 목록 생성에 실패했습니다.\n$err')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final recipeAsync = ref.watch(subscriberRecipeByIdProvider(widget.recipeId));

    return Scaffold(
      appBar: AppBar(
        title: const Text('개인 레시피'),
        actions: <Widget>[
          recipeAsync.maybeWhen(
            data: (Recipe? recipe) {
              if (recipe == null) {
                return const SizedBox.shrink();
              }

              return IconButton(
                onPressed: () => _editRecipe(recipe),
                icon: const Icon(Icons.edit_outlined),
                tooltip: '편집',
              );
            },
            orElse: () => const SizedBox.shrink(),
          ),
          recipeAsync.maybeWhen(
            data: (Recipe? recipe) {
              if (recipe == null) {
                return const SizedBox.shrink();
              }

              return IconButton(
                onPressed: () => _deleteRecipe(recipe),
                icon: const Icon(Icons.delete_outline),
                tooltip: '삭제',
              );
            },
            orElse: () => const SizedBox.shrink(),
          ),
        ],
      ),
      body: recipeAsync.when(
        data: (Recipe? recipe) {
          if (recipe == null) {
            return const Center(child: Text('레시피를 찾을 수 없습니다.'));
          }

          return ListView(
            padding: const EdgeInsets.all(16),
            children: <Widget>[
              Text(recipe.title, style: Theme.of(context).textTheme.headlineSmall),
              if (_sourceLabel(recipe) != null) ...<Widget>[
                const SizedBox(height: 8),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: Theme.of(context).colorScheme.secondaryContainer,
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: Text(
                    _sourceLabel(recipe)!,
                    style: Theme.of(context).textTheme.labelMedium,
                  ),
                ),
              ],
              if ((recipe.summary ?? '').trim().isNotEmpty) ...<Widget>[
                const SizedBox(height: 8),
                Text(recipe.summary!),
              ],
              const SizedBox(height: 12),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: <Widget>[
                  FilledButton.icon(
                    onPressed:
                        _isPromoting ? null : () => _promoteRecipe(recipe),
                    icon: const Icon(Icons.upgrade),
                    label: Text(_isPromoting ? '승격 중...' : '내 레시피로 승격'),
                  ),
                  FilledButton.tonalIcon(
                    onPressed: () => _createShoppingListFromRecipe(recipe),
                    icon: const Icon(Icons.shopping_cart_checkout_outlined),
                    label: const Text('장보기 리스트 만들기'),
                  ),
                  OutlinedButton.icon(
                    onPressed: () => _editRecipe(recipe),
                    icon: const Icon(Icons.edit_outlined),
                    label: const Text('편집'),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              Text('재료', style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: 8),
              if ((recipe.imageUrl ?? '').trim().isNotEmpty) ...<Widget>[
                ClipRRect(
                  borderRadius: BorderRadius.circular(12),
                  child: AspectRatio(
                    aspectRatio: 16 / 9,
                    child: Image.network(
                      recipe.imageUrl!,
                      fit: BoxFit.cover,
                      errorBuilder: (_, __, ___) {
                        return const ColoredBox(
                          color: Color(0x11000000),
                          child: Center(child: Text('이미지를 불러오지 못했습니다.')),
                        );
                      },
                    ),
                  ),
                ),
                const SizedBox(height: 12),
              ],
              ...recipe.ingredients.map((String item) => Text('- $item')),
              const SizedBox(height: 20),
              Text('조리 순서', style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: 8),
              ...recipe.steps
                  .asMap()
                  .entries
                  .map((entry) => Text('${entry.key + 1}. ${entry.value}')),
              const SizedBox(height: 20),
              Text('내 메모', style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: 8),
              Text(
                (recipe.notes ?? '').trim().isEmpty
                    ? '메모가 없습니다. 편집에서 추가할 수 있습니다.'
                    : recipe.notes!,
              ),
              if ((recipe.youtubeUrl ?? '').trim().isNotEmpty) ...<Widget>[
                const SizedBox(height: 20),
                YouTubeLinkCard(youtubeUrl: recipe.youtubeUrl!),
              ],
            ],
          );
        },
        error: (Object err, StackTrace stack) => Center(
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Text('개인 레시피를 불러오지 못했습니다.\n$err'),
          ),
        ),
        loading: () => const Center(child: CircularProgressIndicator()),
      ),
    );
  }
}
