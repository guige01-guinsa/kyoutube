import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';

import '../../../core/config/env.dart';
import '../../../core/widgets/centered_state_view.dart';
import '../data/local_recipe_backup_service.dart';
import '../data/local_sync_beta_service.dart';
import '../application/recipe_providers.dart';
import '../domain/recipe.dart';

class SubscriberRecipesPage extends ConsumerWidget {
  const SubscriberRecipesPage({super.key});

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

  String _importSuccessMessage(LocalRecipeImportResult result) {
    if (result.mode == LocalRecipeImportMode.append) {
      final addedRecipeCount =
          (result.importedRecipeCount - result.skippedRecipeCount).clamp(0, 1 << 30);
      return '가져오기 완료(추가 병합): 신규 레시피 $addedRecipeCount개, '
          '중복 스킵 ${result.skippedRecipeCount}개, '
          '북마크 입력 ${result.importedBookmarkCount}개, '
          '최종 레시피 ${result.recipeCount}개, 북마크 ${result.bookmarkCount}개';
    }

    return '가져오기 완료(덮어쓰기): 레시피 ${result.importedRecipeCount}개, '
        '북마크 ${result.importedBookmarkCount}개로 교체, '
        '최종 레시피 ${result.recipeCount}개, 북마크 ${result.bookmarkCount}개';
  }

  String _importErrorMessage(Object error) {
    if (error is LocalRecipeImportException) {
      switch (error.code) {
        case LocalRecipeImportErrorCode.payloadTooLarge:
          return '[size_exceeded] ${error.message}';
        case LocalRecipeImportErrorCode.invalidRoot:
        case LocalRecipeImportErrorCode.invalidRecipesField:
        case LocalRecipeImportErrorCode.invalidBookmarksField:
        case LocalRecipeImportErrorCode.invalidRecipeItem:
        case LocalRecipeImportErrorCode.missingRequiredField:
        case LocalRecipeImportErrorCode.invalidIngredientOrStep:
        case LocalRecipeImportErrorCode.invalidBookmarkItem:
          return '[invalid_format] ${error.message}';
        case LocalRecipeImportErrorCode.tooManyRecipes:
        case LocalRecipeImportErrorCode.tooManyBookmarks:
          return '[too_many_items] ${error.message}';
        case LocalRecipeImportErrorCode.unknown:
          return '[unknown] ${error.message}';
      }
    }

    return '[unknown] $error';
  }

  Future<LocalRecipeImportMode?> _selectImportMode(BuildContext context) async {
    return showDialog<LocalRecipeImportMode>(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: const Text('가져오기 방식 선택'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.sync_alt),
                title: const Text('덮어쓰기'),
                subtitle: const Text('현재 로컬 데이터를 백업 데이터로 교체'),
                onTap: () => Navigator.of(context).pop(LocalRecipeImportMode.overwrite),
              ),
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.add_link),
                title: const Text('추가 병합'),
                subtitle: const Text('기존 데이터 유지 + 새 데이터만 추가'),
                onTap: () => Navigator.of(context).pop(LocalRecipeImportMode.append),
              ),
            ],
          ),
          actions: <Widget>[
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('취소'),
            ),
          ],
        );
      },
    );
  }

  Future<void> _runSyncBetaPreview(BuildContext context, WidgetRef ref) async {
    try {
      final service = ref.read(localSyncBetaServiceProvider);
      final status = await service.prepareBootstrapPreview();
      ref.invalidate(localSyncBetaStatusProvider);

      if (!context.mounted) {
        return;
      }

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            '동기화 베타 프리뷰 완료: 레시피 ${status.recipeCount}개, 북마크 ${status.bookmarkCount}개',
          ),
        ),
      );
    } catch (error) {
      if (!context.mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('동기화 베타 프리뷰 실패\n$error')),
      );
    }
  }

  Future<void> _showSyncBetaStatus(BuildContext context, WidgetRef ref) async {
    final service = ref.read(localSyncBetaServiceProvider);
    final status = await service.getStatus();
    if (!context.mounted) {
      return;
    }

    final preparedAt = status.lastPreparedAt?.toLocal().toString() ?? '없음';

    await showDialog<void>(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: const Text('동기화 베타 상태'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Text('마지막 준비 시각: $preparedAt'),
              const SizedBox(height: 8),
              Text('레시피 수: ${status.recipeCount}'),
              Text('북마크 수: ${status.bookmarkCount}'),
              if ((status.lastError ?? '').trim().isNotEmpty) ...<Widget>[
                const SizedBox(height: 8),
                Text('최근 오류: ${status.lastError}'),
              ],
            ],
          ),
          actions: <Widget>[
            FilledButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('닫기'),
            ),
          ],
        );
      },
    );
  }

  Future<void> _exportToFile(BuildContext context, WidgetRef ref) async {
    final backupService = ref.read(localRecipeBackupServiceProvider);
    final payload = await backupService.exportAsJsonString();
    final timestamp = DateTime.now().toIso8601String().replaceAll(':', '-');
    final fileName = 'kyoutube-recipes-backup-$timestamp.json';

    try {
      final path = await FilePicker.saveFile(
        dialogTitle: '백업 파일 저장',
        fileName: fileName,
        type: FileType.custom,
        allowedExtensions: const <String>['json'],
      );

      if (path == null) {
        return;
      }

      final file = File(path);
      await file.writeAsString(payload, flush: true);

      if (!context.mounted) {
        return;
      }

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('백업 파일을 저장했습니다.\n$path')),
      );
    } catch (_) {
      if (!context.mounted) {
        return;
      }

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('파일 저장에 실패했습니다. JSON 복사 방식을 사용해 주세요.'),
        ),
      );
    }
  }

  Future<void> _importFromFile(BuildContext context, WidgetRef ref) async {
    try {
      final picked = await FilePicker.pickFiles(
        type: FileType.custom,
        allowedExtensions: const <String>['json', 'txt'],
        withData: true,
      );

      if (picked == null || picked.files.isEmpty) {
        return;
      }

      final file = picked.files.first;
      String? raw;

      if (file.bytes != null) {
        raw = String.fromCharCodes(file.bytes!);
      } else if (file.path != null) {
        raw = await File(file.path!).readAsString();
      }

      if (raw == null || raw.trim().isEmpty) {
        throw const FormatException('파일 내용이 비어 있습니다.');
      }

      final backupService = ref.read(localRecipeBackupServiceProvider);
      if (!context.mounted) {
        return;
      }
      final mode = await _selectImportMode(context);
      if (mode == null) {
        return;
      }

      final result = await backupService.importFromJsonString(
        raw.trim(),
        mode: mode,
      );

      ref.invalidate(subscriberRecipesProvider);
      if (Env.localSyncBetaEnabled) {
        ref.invalidate(localSyncBetaStatusProvider);
      }
      ref.invalidate(bookmarkedRecipesProvider);

      if (!context.mounted) {
        return;
      }

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(_importSuccessMessage(result)),
        ),
      );
    } catch (error) {
      if (!context.mounted) {
        return;
      }

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('파일 가져오기에 실패했습니다.\n${_importErrorMessage(error)}')),
      );
    }
  }

  Future<void> _showExportDialog(BuildContext context, WidgetRef ref) async {
    final backupService = ref.read(localRecipeBackupServiceProvider);
    final payload = await backupService.exportAsJsonString();
    if (!context.mounted) {
      return;
    }

    await showDialog<void>(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: const Text('로컬 데이터 내보내기'),
          content: SizedBox(
            width: 520,
            child: SingleChildScrollView(
              child: SelectableText(payload),
            ),
          ),
          actions: <Widget>[
            TextButton(
              onPressed: () async {
                await Clipboard.setData(ClipboardData(text: payload));
                if (!context.mounted) {
                  return;
                }
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('백업 JSON을 클립보드에 복사했습니다.')),
                );
              },
              child: const Text('복사'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('닫기'),
            ),
          ],
        );
      },
    );
  }

  Future<void> _showImportDialog(BuildContext context, WidgetRef ref) async {
    final controller = TextEditingController();

    final submitted = await showDialog<String>(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: const Text('로컬 데이터 가져오기'),
          content: SizedBox(
            width: 520,
            child: TextField(
              controller: controller,
              maxLines: 14,
              decoration: const InputDecoration(
                border: OutlineInputBorder(),
                hintText: '내보낸 JSON을 여기에 붙여 넣어 주세요.',
              ),
            ),
          ),
          actions: <Widget>[
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('취소'),
            ),
            FilledButton(
              onPressed: () {
                Navigator.of(context).pop(controller.text);
              },
              child: const Text('가져오기'),
            ),
          ],
        );
      },
    );

    if (submitted == null || submitted.trim().isEmpty) {
      return;
    }

    try {
      final backupService = ref.read(localRecipeBackupServiceProvider);
      if (!context.mounted) {
        return;
      }
      final mode = await _selectImportMode(context);
      if (mode == null) {
        return;
      }

      final result = await backupService.importFromJsonString(
        submitted.trim(),
        mode: mode,
      );

      ref.invalidate(subscriberRecipesProvider);
      if (Env.localSyncBetaEnabled) {
        ref.invalidate(localSyncBetaStatusProvider);
      }
      ref.invalidate(bookmarkedRecipesProvider);

      if (!context.mounted) {
        return;
      }

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(_importSuccessMessage(result)),
        ),
      );
    } catch (error) {
      if (!context.mounted) {
        return;
      }

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('가져오기에 실패했습니다.\n${_importErrorMessage(error)}')),
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

  Future<void> _showCreateDialog(BuildContext context, WidgetRef ref) async {
    final titleController = TextEditingController();
    final summaryController = TextEditingController();
    final ingredientsController = TextEditingController();
    final stepsController = TextEditingController();
    final notesController = TextEditingController();
    final imageUrlController = TextEditingController();
    final youtubeUrlController = TextEditingController();
    final formKey = GlobalKey<FormState>();
    var isSubmitting = false;
    String? submitError;

    final created = await showDialog<Recipe>(
      context: context,
      builder: (BuildContext context) {
        return StatefulBuilder(
          builder: (BuildContext context, StateSetter setDialogState) {
            return AlertDialog(
              title: const Text('개인 레시피 만들기'),
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
                        controller: summaryController,
                        maxLines: 3,
                        decoration: const InputDecoration(
                          labelText: '요약(선택)',
                          border: OutlineInputBorder(),
                        ),
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
                          labelText: '내 메모(선택)',
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
                        decoration: const InputDecoration(
                          labelText: 'YouTube URL(선택)',
                          border: OutlineInputBorder(),
                        ),
                      ),
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
                          Navigator.of(context).pop();
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
                            final recipe = await repository.createSubscriberRecipe(
                              title: titleController.text.trim(),
                              summary: summaryController.text,
                              ingredients: _splitLines(ingredientsController.text),
                              steps: _splitLines(stepsController.text),
                              notes: notesController.text,
                              imageUrl: imageUrlController.text,
                              youtubeUrl: youtubeUrlController.text,
                            );
                            if (!context.mounted) {
                              return;
                            }
                            Navigator.of(context).pop(recipe);
                          } catch (err) {
                            setDialogState(() {
                              isSubmitting = false;
                              submitError = '저장에 실패했습니다. $err';
                            });
                          }
                        },
                  child: Text(isSubmitting ? '저장 중...' : '만들기'),
                ),
              ],
            );
          },
        );
      },
    );

    if (created == null) {
      return;
    }

    ref.invalidate(subscriberRecipesProvider);
    if (Env.localSyncBetaEnabled) {
      ref.invalidate(localSyncBetaStatusProvider);
    }
    if (!context.mounted) {
      return;
    }

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('개인 레시피를 만들었습니다.')),
    );
    context.push('/my-recipes/${created.id}');
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final recipesAsync = ref.watch(subscriberRecipesProvider);
    final syncStatusAsync =
        Env.localSyncBetaEnabled ? ref.watch(localSyncBetaStatusProvider) : null;

    return Scaffold(
      appBar: AppBar(
        title: const Text('내 요리 노트'),
        actions: <Widget>[
          PopupMenuButton<String>(
            onSelected: (String value) async {
              if (value == 'sync_beta_preview') {
                await _runSyncBetaPreview(context, ref);
                return;
              }
              if (value == 'sync_beta_status') {
                await _showSyncBetaStatus(context, ref);
                return;
              }
              if (value == 'export_file') {
                await _exportToFile(context, ref);
                return;
              }
              if (value == 'import_file') {
                await _importFromFile(context, ref);
                return;
              }
              if (value == 'export') {
                await _showExportDialog(context, ref);
                return;
              }
              if (value == 'import') {
                await _showImportDialog(context, ref);
              }
            },
            itemBuilder: (BuildContext context) {
              final items = <PopupMenuEntry<String>>[
                const PopupMenuItem<String>(
                  value: 'export_file',
                  child: Text('파일로 내보내기'),
                ),
                const PopupMenuItem<String>(
                  value: 'import_file',
                  child: Text('파일에서 가져오기'),
                ),
                const PopupMenuDivider(),
                const PopupMenuItem<String>(
                  value: 'export',
                  child: Text('백업 내보내기'),
                ),
                const PopupMenuItem<String>(
                  value: 'import',
                  child: Text('백업 가져오기'),
                ),
              ];

              if (Env.localSyncBetaEnabled) {
                items.add(const PopupMenuDivider());
                items.add(
                  const PopupMenuItem<String>(
                    value: 'sync_beta_preview',
                    child: Text('동기화 베타 프리뷰 실행'),
                  ),
                );
                items.add(
                  const PopupMenuItem<String>(
                    value: 'sync_beta_status',
                    child: Text('동기화 베타 상태 보기'),
                  ),
                );
              }

              return items;
            },
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _showCreateDialog(context, ref),
        icon: const Icon(Icons.add),
        label: const Text('직접 만들기'),
      ),
      body: Column(
        children: <Widget>[
          if (Env.localSyncBetaEnabled && syncStatusAsync != null)
            _SyncBetaStatusCard(
              syncStatusAsync: syncStatusAsync,
              onRefresh: () => ref.invalidate(localSyncBetaStatusProvider),
              onRunPreview: () => _runSyncBetaPreview(context, ref),
            ),
          Expanded(
            child: recipesAsync.when(
              data: (List<Recipe> recipes) {
                if (recipes.isEmpty) {
                  return CenteredStateView(
                    icon: Icons.menu_book_outlined,
                    title: '아직 저장한 개인 레시피가 없습니다',
                    message: '직접 만들거나 공개 레시피를 복사해 시작할 수 있습니다.',
                    actionLabel: '직접 만들기',
                    onAction: () => _showCreateDialog(context, ref),
                  );
                }

                return RefreshIndicator(
                  onRefresh: () async {
                    ref.invalidate(subscriberRecipesProvider);
                    if (Env.localSyncBetaEnabled) {
                      ref.invalidate(localSyncBetaStatusProvider);
                    }
                  },
                  child: ListView.separated(
                    physics: const AlwaysScrollableScrollPhysics(),
                    itemCount: recipes.length,
                    separatorBuilder: (_, __) => const Divider(height: 1),
                    itemBuilder: (BuildContext context, int index) {
                      final recipe = recipes[index];
                      final sourceLabel = _sourceLabel(recipe);
                      return ListTile(
                        title: Text(recipe.title),
                        subtitle: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: <Widget>[
                            if (sourceLabel != null)
                              Padding(
                                padding: const EdgeInsets.only(bottom: 4),
                                child: Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 8,
                                    vertical: 2,
                                  ),
                                  decoration: BoxDecoration(
                                    color: Theme.of(context)
                                        .colorScheme
                                        .secondaryContainer,
                                    borderRadius: BorderRadius.circular(999),
                                  ),
                                  child: Text(
                                    sourceLabel,
                                    style: Theme.of(context)
                                        .textTheme
                                        .labelSmall,
                                  ),
                                ),
                              ),
                            Text(
                              (recipe.notes ?? '').trim().isEmpty
                                  ? '메모 없음'
                                  : recipe.notes!,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ],
                        ),
                        trailing: Text('${recipe.steps.length}단계'),
                        onTap: () => context.push('/my-recipes/${recipe.id}'),
                      );
                    },
                  ),
                );
              },
              error: (Object err, StackTrace stack) => CenteredStateView(
                icon: Icons.cloud_off_outlined,
                title: '개인 레시피를 불러오지 못했습니다',
                message: '잠시 후 다시 시도해 주세요.',
                actionLabel: '다시 시도',
                onAction: () => ref.invalidate(subscriberRecipesProvider),
              ),
              loading: () => const Center(child: CircularProgressIndicator()),
            ),
          ),
        ],
      ),
    );
  }
}

class _SyncBetaStatusCard extends StatefulWidget {
  const _SyncBetaStatusCard({
    required this.syncStatusAsync,
    required this.onRefresh,
    required this.onRunPreview,
  });

  final AsyncValue<LocalSyncBetaStatus> syncStatusAsync;
  final VoidCallback onRefresh;
  final Future<void> Function() onRunPreview;

  @override
  State<_SyncBetaStatusCard> createState() => _SyncBetaStatusCardState();
}

class _SyncBetaStatusCardState extends State<_SyncBetaStatusCard> {
  var _isPreviewRunning = false;

  Future<void> _handleRunPreview() async {
    if (_isPreviewRunning) {
      return;
    }

    setState(() {
      _isPreviewRunning = true;
    });

    try {
      await widget.onRunPreview();
    } finally {
      if (mounted) {
        setState(() {
          _isPreviewRunning = false;
        });
      }
    }
  }

  String _relativeTime(DateTime? time) {
    if (time == null) {
      return '아직 실행 없음';
    }
    final diff = DateTime.now().difference(time.toLocal());
    if (diff.inSeconds < 10) {
      return '방금 전';
    }
    if (diff.inMinutes < 1) {
      return '${diff.inSeconds}초 전';
    }
    if (diff.inHours < 1) {
      return '${diff.inMinutes}분 전';
    }
    if (diff.inDays < 1) {
      return '${diff.inHours}시간 전';
    }
    return '${diff.inDays}일 전';
  }

  String _statusSummary(LocalSyncBetaStatus status) {
    if ((status.lastError ?? '').trim().isNotEmpty) {
      return '최근 실행 결과: 실패';
    }
    if (status.lastPreparedAt == null) {
      return '최근 실행 결과: 아직 실행 없음';
    }
    return '최근 실행 결과: 성공 (레시피 ${status.recipeCount}개, 북마크 ${status.bookmarkCount}개)';
  }

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.fromLTRB(16, 12, 16, 8),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: widget.syncStatusAsync.when(
          data: (LocalSyncBetaStatus status) {
            final preparedAt =
                status.lastPreparedAt?.toLocal().toString() ?? '아직 실행 없음';
            final hasError = (status.lastError ?? '').trim().isNotEmpty;
            final statusLabel = status.lastPreparedAt == null
                ? '대기'
                : hasError
                    ? '실패'
                    : '성공';
            final statusBackground = status.lastPreparedAt == null
                ? Theme.of(context).colorScheme.surfaceContainerHighest
                : hasError
                    ? Theme.of(context).colorScheme.errorContainer
                    : Theme.of(context).colorScheme.tertiaryContainer;
            final statusForeground = status.lastPreparedAt == null
                ? Theme.of(context).colorScheme.onSurfaceVariant
                : hasError
                    ? Theme.of(context).colorScheme.onErrorContainer
                    : Theme.of(context).colorScheme.onTertiaryContainer;
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Row(
                  children: <Widget>[
                    Text(
                      '동기화 베타 상태',
                      style: Theme.of(context).textTheme.titleSmall,
                    ),
                    const SizedBox(width: 8),
                    Chip(
                      visualDensity: VisualDensity.compact,
                      label: Text(statusLabel),
                      backgroundColor: statusBackground,
                      labelStyle: TextStyle(color: statusForeground),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                Text('마지막 준비 시각: $preparedAt'),
                Text('마지막 실행 경과: ${_relativeTime(status.lastPreparedAt)}'),
                Text(_statusSummary(status)),
                Text('레시피 수: ${status.recipeCount}'),
                Text('북마크 수: ${status.bookmarkCount}'),
                if ((status.lastError ?? '').trim().isNotEmpty)
                  Text('최근 오류: ${status.lastError}'),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: <Widget>[
                    OutlinedButton.icon(
                      onPressed: _isPreviewRunning ? null : widget.onRefresh,
                      icon: const Icon(Icons.refresh),
                      label: const Text('상태 새로고침'),
                    ),
                    FilledButton.icon(
                      onPressed: _isPreviewRunning ? null : _handleRunPreview,
                      icon: _isPreviewRunning
                          ? const SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.play_arrow),
                      label: Text(_isPreviewRunning ? '실행 중...' : '프리뷰 실행'),
                    ),
                  ],
                ),
              ],
            );
          },
          error: (_, __) => Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              const Text('동기화 베타 상태를 불러오지 못했습니다.'),
              const SizedBox(height: 8),
              OutlinedButton.icon(
                onPressed: _isPreviewRunning ? null : widget.onRefresh,
                icon: const Icon(Icons.refresh),
                label: const Text('다시 시도'),
              ),
            ],
          ),
          loading: () => const Text('동기화 베타 상태를 불러오는 중...'),
        ),
      ),
    );
  }
}
