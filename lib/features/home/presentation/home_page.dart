import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../core/config/env.dart';
import '../../../core/firebase/firebase_messaging_service.dart';
import '../../../core/widgets/operations_status_card.dart';
import '../../auth/application/auth_providers.dart';
import '../../recipes/application/recipe_providers.dart';
import '../../recipes/domain/recipe.dart';
import '../../recipes/presentation/recipe_thumbnail.dart';

class HomePage extends ConsumerStatefulWidget {
  const HomePage({super.key});

  @override
  ConsumerState<HomePage> createState() => _HomePageState();
}

class _HomePageState extends ConsumerState<HomePage> {
  String _searchQuery = '';
  bool _useAiSearch = false;

  @override
  Widget build(BuildContext context) {
    final publicQuery = PublicRecipeQuery(
      search: _searchQuery,
      useAiSearch: _useAiSearch,
    );
    final recipesAsync = ref.watch(publicRecipesProvider(publicQuery));
    final authUserAsync = ref.watch(authUserProvider);
    final currentUser = authUserAsync.valueOrNull;

    const showFcmDebugPanel = !kReleaseMode;

    return Scaffold(
      appBar: AppBar(
        title: const Text('playscout'),
        actions: <Widget>[
          if (Env.youtubeSearchEnabled)
            IconButton(
              onPressed: () {
                context.push('/youtube');
              },
              icon: const Icon(Icons.ondemand_video_outlined),
              tooltip: 'YouTube',
            ),
          IconButton(
            onPressed: () {
              if (currentUser == null) {
                context.push('/login');
                return;
              }
              context.push('/kitchen?tab=shopping');
            },
            icon: const Icon(Icons.shopping_cart_outlined),
            tooltip: '장보기',
          ),
          IconButton(
            onPressed: () {
              if (currentUser == null) {
                context.push('/login');
                return;
              }
              context.push('/bookmarks');
            },
            icon: const Icon(Icons.bookmark_outline),
            tooltip: '북마크',
          ),
          IconButton(
            onPressed: () {
              if (currentUser == null) {
                context.push('/login');
                return;
              }
              context.push('/my-recipes');
            },
            icon: const Icon(Icons.menu_book_outlined),
            tooltip: '내 레시피',
          ),
          if (currentUser != null)
            IconButton(
              onPressed: () {
                context.push('/account');
              },
              icon: const Icon(Icons.account_circle_outlined),
              tooltip: '계정 관리',
            ),
          IconButton(
            onPressed: () async {
              if (currentUser == null) {
                context.push('/login');
                return;
              }
              await Supabase.instance.client.auth.signOut();
            },
            icon: Icon(currentUser == null ? Icons.login : Icons.logout),
            tooltip: currentUser == null ? '로그인' : '로그아웃',
          ),
        ],
      ),
      body: Column(
        children: <Widget>[
          _PublicRecipeSearchBar(
            initialQuery: _searchQuery,
            useAiSearch: _useAiSearch,
            onQueryChanged: (String value) {
              if (!mounted) {
                return;
              }
              setState(() {
                _searchQuery = value;
              });
            },
            onAiSearchChanged: (bool enabled) {
              if (!mounted) {
                return;
              }
              setState(() {
                _useAiSearch = enabled;
              });
            },
          ),
          Expanded(
            child: recipesAsync.when(
              data: (List<Recipe> recipes) {
                if (recipes.isEmpty) {
                  return RefreshIndicator(
                    onRefresh: () async {
                      ref.invalidate(publicRecipesProvider(publicQuery));
                    },
                    child: ListView(
                      physics: const AlwaysScrollableScrollPhysics(),
                      children: const <Widget>[
                        SizedBox(height: 96),
                        Center(child: Text('조건에 맞는 공개 레시피가 없습니다.')),
                      ],
                    ),
                  );
                }

                return RefreshIndicator(
                  onRefresh: () async {
                    ref.invalidate(publicRecipesProvider(publicQuery));
                    ref.invalidate(kitchenSummaryProvider);
                  },
                  child: ListView.separated(
                    physics: const AlwaysScrollableScrollPhysics(),
                    padding: const EdgeInsets.only(bottom: 24),
                    itemCount: recipes.length + 2 + (showFcmDebugPanel ? 1 : 0),
                    separatorBuilder: (_, __) => const Divider(height: 1),
                    itemBuilder: (BuildContext context, int index) {
                      if (index < recipes.length) {
                        final recipe = recipes[index];
                        return ListTile(
                          contentPadding: const EdgeInsets.symmetric(
                            horizontal: 16,
                            vertical: 8,
                          ),
                          leading: RecipeThumbnail(imageUrl: recipe.imageUrl),
                          title: Text(recipe.title),
                          subtitle: Text(recipe.summary ?? '요약 없음'),
                          trailing: Text('${recipe.ingredients.length}개 재료'),
                          onTap: () {
                            context.push('/recipes/${recipe.id}');
                          },
                        );
                      }

                      final diagnosticIndex = index - recipes.length;
                      if (diagnosticIndex == 0) {
                        return const _KitchenSummaryCard();
                      }

                      if (showFcmDebugPanel && diagnosticIndex == 1) {
                        return const _FcmDebugPanel();
                      }

                      return const OperationsStatusCard();
                    },
                  ),
                );
              },
              error: (Object err, StackTrace stack) {
                return Center(
                  child: Padding(
                    padding: const EdgeInsets.all(20),
                    child: Text(
                      '레시피를 불러오지 못했습니다.\n$err',
                      textAlign: TextAlign.center,
                    ),
                  ),
                );
              },
              loading: () => const Center(child: CircularProgressIndicator()),
            ),
          ),
        ],
      ),
    );
  }
}

class _KitchenSummaryCard extends ConsumerWidget {
  const _KitchenSummaryCard();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final currentUser = ref.watch(authUserProvider).valueOrNull;
    if (currentUser == null) {
      return const Card(
        margin: EdgeInsets.fromLTRB(16, 8, 16, 8),
        child: Padding(
          padding: EdgeInsets.all(12),
          child: Text('주방 요약은 로그인 후 확인할 수 있습니다.'),
        ),
      );
    }

    final summaryAsync = ref.watch(kitchenSummaryProvider);
    return Card(
      margin: const EdgeInsets.fromLTRB(16, 8, 16, 8),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () {
          context.push('/kitchen');
        },
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: summaryAsync.when(
            data: (Map<String, int> data) {
              final ingredients = data['ingredient_count'] ?? 0;
              final expiring = data['expiring_soon_count'] ?? 0;
              final lists = data['active_shopping_list_count'] ?? 0;
              final openItems = data['open_shopping_item_count'] ?? 0;
              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Row(
                    children: <Widget>[
                      Expanded(
                        child: Text(
                          '주방 요약',
                          style: Theme.of(context).textTheme.titleMedium,
                        ),
                      ),
                      const Icon(Icons.chevron_right),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Text('보유 재료: $ingredients개'),
                  Text('유통기한 임박: $expiring개'),
                  Text('진행 중 장보기: $lists개'),
                  Text('미체크 항목: $openItems개'),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: <Widget>[
                      OutlinedButton.icon(
                        onPressed: () {
                          context.push('/kitchen?tab=ingredients');
                        },
                        icon: const Icon(Icons.kitchen_outlined),
                        label: const Text('재료 관리'),
                      ),
                      OutlinedButton.icon(
                        onPressed: () {
                          context.push('/kitchen?tab=shopping');
                        },
                        icon: const Icon(Icons.shopping_cart_outlined),
                        label: const Text('장보기'),
                      ),
                    ],
                  ),
                ],
              );
            },
            loading: () => const SizedBox(
              height: 48,
              child: Center(child: CircularProgressIndicator()),
            ),
            error: (_, __) => const Text('주방 요약을 불러오지 못했습니다.'),
          ),
        ),
      ),
    );
  }
}

class _PublicRecipeSearchBar extends StatefulWidget {
  const _PublicRecipeSearchBar({
    required this.initialQuery,
    required this.useAiSearch,
    required this.onQueryChanged,
    required this.onAiSearchChanged,
  });

  final String initialQuery;
  final bool useAiSearch;
  final ValueChanged<String> onQueryChanged;
  final ValueChanged<bool> onAiSearchChanged;

  @override
  State<_PublicRecipeSearchBar> createState() => _PublicRecipeSearchBarState();
}

class _PublicRecipeSearchBarState extends State<_PublicRecipeSearchBar> {
  late final TextEditingController _controller;
  late final FocusNode _focusNode;
  Timer? _debounce;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.initialQuery);
    _focusNode = FocusNode();
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _controller.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  void _emitQuery(String value) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 250), () {
      if (!mounted) {
        return;
      }
      widget.onQueryChanged(value);
    });
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          TextField(
            controller: _controller,
            focusNode: _focusNode,
            textInputAction: TextInputAction.search,
            decoration: InputDecoration(
              labelText: '공개 레시피 검색',
              hintText: '제목, 재료, 조리 단어로 검색',
              prefixIcon: const Icon(Icons.search),
              suffixIcon: _controller.text.isEmpty
                  ? null
                  : IconButton(
                      onPressed: () {
                        _debounce?.cancel();
                        _controller.clear();
                        widget.onQueryChanged('');
                        _focusNode.requestFocus();
                        setState(() {});
                      },
                      icon: const Icon(Icons.clear),
                    ),
              border: const OutlineInputBorder(),
            ),
            onChanged: (String value) {
              setState(() {});
              _emitQuery(value);
            },
            onSubmitted: (String value) {
              _debounce?.cancel();
              if (!mounted) {
                return;
              }
              widget.onQueryChanged(value);
            },
          ),
          const SizedBox(height: 8),
          FilterChip(
            selected: widget.useAiSearch,
            onSelected: widget.onAiSearchChanged,
            avatar: const Icon(Icons.auto_awesome, size: 18),
            label: const Text('AI 검색 기준 사용'),
          ),
        ],
      ),
    );
  }
}

class _FcmDebugPanel extends StatelessWidget {
  const _FcmDebugPanel();

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<FirebaseMessagingDebugState>(
      valueListenable: FirebaseMessagingService.debugState,
      builder: (BuildContext context, FirebaseMessagingDebugState state, _) {
        return Card(
          margin: const EdgeInsets.fromLTRB(16, 16, 16, 8),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  'FCM 디버그',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const SizedBox(height: 8),
                Text(
                  state.isSupportedPlatform
                      ? '권한 상태: ${state.permissionStatus}'
                      : '현재 플랫폼은 FCM 디버그 대상이 아닙니다. Android 또는 iOS에서 확인하세요.',
                ),
                const SizedBox(height: 8),
                Text(
                  '토큰: ${state.tokenPreview ?? '아직 없음'}',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
                if (state.lastMessageTitle != null ||
                    state.lastMessageBody != null) ...<Widget>[
                  const SizedBox(height: 8),
                  Text('마지막 알림 제목: ${state.lastMessageTitle ?? '-'}'),
                  const SizedBox(height: 4),
                  Text('마지막 알림 본문: ${state.lastMessageBody ?? '-'}'),
                ],
                if (state.errorMessage != null) ...<Widget>[
                  const SizedBox(height: 8),
                  Text(
                    '오류: ${state.errorMessage}',
                    style:
                        TextStyle(color: Theme.of(context).colorScheme.error),
                  ),
                ],
                const SizedBox(height: 12),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: <Widget>[
                    OutlinedButton(
                      onPressed: state.isSupportedPlatform && !kReleaseMode
                          ? () => FirebaseMessagingService.requestPermission()
                          : null,
                      child: const Text('권한 요청'),
                    ),
                    OutlinedButton(
                      onPressed: state.isSupportedPlatform
                          ? () => FirebaseMessagingService.refreshToken()
                          : null,
                      child: const Text('토큰 새로고침'),
                    ),
                  ],
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}
