import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/config/env.dart';
import 'create_creator_recipe_page.dart';
import 'recipe_thumbnail.dart';
import '../../../core/widgets/centered_state_view.dart';
import '../application/recipe_providers.dart';
import '../domain/recipe.dart';

enum _AccountMenuAction { login, logout }
enum _CreatorRecipeMenuAction { edit, delete }

class CreatorRecipesPage extends ConsumerStatefulWidget {
  const CreatorRecipesPage({super.key});

  @override
  ConsumerState<CreatorRecipesPage> createState() =>
      _CreatorRecipesPageState();
}

class _CreatorRecipesPageState extends ConsumerState<CreatorRecipesPage> {
  String _searchQuery = '';
  AuthChangeEvent? _lastAuthEvent;
  StreamSubscription<AuthState>? _authStateSub;
  bool _scheduledAuthRefresh = false;
  bool _isSigningOut = false;

  @override
  void initState() {
    super.initState();

    _authStateSub = Supabase.instance.client.auth.onAuthStateChange.listen((AuthState state) {
      if (!mounted) {
        return;
      }

      if (state.event == _lastAuthEvent) {
        return;
      }

      _lastAuthEvent = state.event;
      ref.invalidate(creatorRecipesProvider(_searchQuery));
    });
  }

  @override
  void dispose() {
    _authStateSub?.cancel();
    super.dispose();
  }

  Future<void> _signOut() async {
    if (_isSigningOut) {
      return;
    }

    setState(() {
      _isSigningOut = true;
    });

    try {
      await Supabase.instance.client.auth.signOut();
      if (!mounted) {
        return;
      }
      ref.invalidate(creatorRecipesProvider(_searchQuery));
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('로그아웃되었습니다.')),
      );
    } catch (error) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('로그아웃에 실패했습니다: $error')),
      );
    } finally {
      if (mounted) {
        setState(() {
          _isSigningOut = false;
        });
      }
    }
  }

  Future<void> _signInForLocalIfPossible() async {
    if (_isSigningOut) {
      return;
    }

    setState(() {
      _isSigningOut = true;
    });

    try {
      await Supabase.instance.client.auth.signInAnonymously();
      if (!mounted) {
        return;
      }
      ref.invalidate(creatorRecipesProvider(_searchQuery));
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('개발용 익명 로그인에 성공했습니다.')),
      );
    } catch (error) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('로그인에 실패했습니다: $error')),
      );
      context.push('/login?returnTo=%2Fcreator');
    } finally {
      if (mounted) {
        setState(() {
          _isSigningOut = false;
        });
      }
    }
  }

  Future<void> _editCreatorRecipe(Recipe recipe) async {
    final updated = await Navigator.of(context).push<bool>(
      MaterialPageRoute<bool>(
        builder: (_) => CreateCreatorRecipePage(initialRecipe: recipe),
      ),
    );

    if (updated == true && mounted) {
      ref.invalidate(creatorRecipesProvider(_searchQuery));
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('레시피 수정 내용을 저장했습니다.')),
      );
    }
  }

  Future<void> _deleteCreatorRecipe(Recipe recipe) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: const Text('레시피 삭제'),
          content: Text('"${recipe.title}" 레시피를 삭제하시겠습니까?'),
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
      final repository = ref.read(recipeRepositoryProvider);
      final imageService = ref.read(recipeImageServiceProvider);
      await repository.deleteCreatorRecipe(recipe.id);

      final imageUrl = recipe.imageUrl;
      if ((imageUrl ?? '').isNotEmpty) {
        try {
          await imageService.deleteCreatorRecipeImageByUrl(imageUrl!);
        } catch (_) {
          // Keep deletion successful even if image cleanup fails.
        }
      }

      if (!mounted) {
        return;
      }
      ref.invalidate(creatorRecipesProvider(_searchQuery));
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('레시피를 삭제했습니다.')),
      );
    } catch (error) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('삭제에 실패했습니다: $error')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final recipesAsync = ref.watch(creatorRecipesProvider(_searchQuery));
    final session = Supabase.instance.client.auth.currentSession;
    final isLoggedIn = session != null;
    final isAnonymous = session?.user.isAnonymous ?? false;
    final isKeyboardVisible = MediaQuery.of(context).viewInsets.bottom > 0;
    final authStatusText = isLoggedIn
        ? (isAnonymous ? '상태: 익명 로그인' : '상태: 로그인됨')
        : '상태: 비로그인';

    return Scaffold(
      resizeToAvoidBottomInset: false,
      appBar: AppBar(
        title: const Text(kDebugMode ? '크리에이터 DEV' : '크리에이터'),
        actions: <Widget>[
          PopupMenuButton<_AccountMenuAction>(
            enabled: !_isSigningOut,
            tooltip: '계정',
            icon: Icon(
              isLoggedIn ? Icons.verified_user_outlined : Icons.account_circle_outlined,
            ),
            onSelected: (_AccountMenuAction action) {
              if (action == _AccountMenuAction.logout) {
                _signOut();
                return;
              }
              context.push('/login?returnTo=%2Fcreator');
            },
            itemBuilder: (BuildContext context) =>
                <PopupMenuEntry<_AccountMenuAction>>[
                  PopupMenuItem<_AccountMenuAction>(
                    enabled: false,
                    child: Text(authStatusText),
                  ),
                  const PopupMenuDivider(height: 1),
                  PopupMenuItem<_AccountMenuAction>(
                    enabled: !_isSigningOut,
                    value: isLoggedIn
                        ? _AccountMenuAction.logout
                        : _AccountMenuAction.login,
                    child: Text(isLoggedIn ? '로그아웃' : '로그인'),
                  ),
                ],
          ),
          IconButton(
            onPressed: () => context.go('/'),
            icon: const Icon(Icons.home_outlined),
            tooltip: '홈으로 이동',
          ),
        ],
      ),
      body: Column(
        children: <Widget>[
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
            child: TextField(
              decoration: InputDecoration(
                labelText: '크리에이터 레시피 검색',
                prefixIcon: const Icon(Icons.search),
                suffixIcon: _searchQuery.isEmpty
                    ? null
                    : IconButton(
                        onPressed: () {
                          setState(() {
                            _searchQuery = '';
                          });
                        },
                        icon: const Icon(Icons.clear),
                      ),
                border: const OutlineInputBorder(),
              ),
              onChanged: (String value) {
                setState(() {
                  _searchQuery = value;
                });
              },
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
            child: Row(
              children: <Widget>[
                Expanded(
                  child: Text(
                    authStatusText,
                    style: Theme.of(context).textTheme.bodyMedium,
                  ),
                ),
                TextButton.icon(
                  onPressed: _isSigningOut
                      ? null
                      : () {
                          if (isLoggedIn) {
                            _signOut();
                            return;
                          }
                          if (Env.appEnv == 'local') {
                            _signInForLocalIfPossible();
                            return;
                          }
                          context.push('/login?returnTo=%2Fcreator');
                        },
                  icon: Icon(
                    isLoggedIn
                        ? Icons.logout_outlined
                        : Icons.login_outlined,
                  ),
                  label: Text(isLoggedIn ? '로그아웃' : '로그인'),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Row(
                  children: <Widget>[
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: () => context.go('/?source=public'),
                        icon: const Icon(Icons.search_outlined),
                        label: const Text('공공레시피 검색'),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: () => context.go('/?source=youtube'),
                        icon: const Icon(Icons.play_circle_outline),
                        label: const Text('YouTube 검색'),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Row(
                  children: <Widget>[
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: () => context.push('/my-recipes'),
                        icon: const Icon(Icons.menu_book_outlined),
                        label: const Text('내 요리 노트'),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: () => context.push('/creator/new'),
                        icon: const Icon(Icons.add),
                        label: Text(
                          isLoggedIn ? '새 레시피 작성' : '로그인 후 작성',
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          Expanded(
            child: recipesAsync.when(
              data: (List<Recipe> recipes) {
                if (recipes.isEmpty) {
                  if (isKeyboardVisible) {
                    return const Padding(
                      padding: EdgeInsets.fromLTRB(20, 24, 20, 8),
                      child: Align(
                        alignment: Alignment.topCenter,
                        child: Text('검색어를 입력하거나 키보드를 닫아 목록을 확인하세요.'),
                      ),
                    );
                  }

                  return const CenteredStateView(
                    icon: Icons.menu_book_outlined,
                    title: '크리에이터 레시피가 없습니다',
                    message: '새 레시피를 작성하거나 검색어를 바꿔보세요.',
                  );
                }

                return RefreshIndicator(
                  onRefresh: () async {
                    ref.invalidate(creatorRecipesProvider(_searchQuery));
                  },
                  child: ListView.separated(
                    physics: const AlwaysScrollableScrollPhysics(),
                    itemCount: recipes.length,
                    separatorBuilder: (_, __) => const Divider(height: 1),
                    itemBuilder: (BuildContext context, int index) {
                      final recipe = recipes[index];
                      return ListTile(
                        leading: SizedBox(
                          width: 56,
                          height: 56,
                          child: RecipeThumbnail(imageUrl: recipe.imageUrl),
                        ),
                        title: Text(recipe.title),
                        subtitle: Text(
                          recipe.summary?.trim().isEmpty ?? true
                              ? '요약 없음'
                              : recipe.summary!,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        trailing: PopupMenuButton<_CreatorRecipeMenuAction>(
                          onSelected: (_CreatorRecipeMenuAction action) async {
                            if (action == _CreatorRecipeMenuAction.edit) {
                              await _editCreatorRecipe(recipe);
                              return;
                            }
                            await _deleteCreatorRecipe(recipe);
                          },
                          itemBuilder: (BuildContext context) =>
                              const <PopupMenuEntry<_CreatorRecipeMenuAction>>[
                            PopupMenuItem<_CreatorRecipeMenuAction>(
                              value: _CreatorRecipeMenuAction.edit,
                              child: Text('수정'),
                            ),
                            PopupMenuItem<_CreatorRecipeMenuAction>(
                              value: _CreatorRecipeMenuAction.delete,
                              child: Text('삭제'),
                            ),
                          ],
                        ),
                        onTap: () => context.push('/creator/${recipe.id}'),
                      );
                    },
                  ),
                );
              },
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (Object err, StackTrace stack) {
                final message = err.toString();
                final needsSession =
                    message.contains('세션이 필요합니다') ||
                    message.contains('로그인이 필요합니다') ||
                    message.toLowerCase().contains('unauthorized');
                final hasSession =
                    Supabase.instance.client.auth.currentSession != null;

                if (needsSession && hasSession) {
                  if (!_scheduledAuthRefresh) {
                    _scheduledAuthRefresh = true;
                    WidgetsBinding.instance.addPostFrameCallback((_) {
                      if (!mounted) {
                        return;
                      }
                      _scheduledAuthRefresh = false;
                      ref.invalidate(creatorRecipesProvider(_searchQuery));
                    });
                  }

                  return const Center(
                    child: Padding(
                      padding: EdgeInsets.all(24),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: <Widget>[
                          CircularProgressIndicator(),
                          SizedBox(height: 12),
                          Text('로그인 상태 반영 중입니다...'),
                        ],
                      ),
                    ),
                  );
                }

                return CenteredStateView(
                  icon: Icons.error_outline,
                  title: needsSession
                      ? '로그인 후 크리에이터 목록을 볼 수 있습니다'
                      : '크리에이터 레시피를 불러오지 못했습니다',
                  message: needsSession
                      ? '현재 정책: 목록 조회/서버 저장은 로그인 필요, 로컬 초안 작성은 로그인 없이 가능합니다.'
                      : message,
                  actionLabel: needsSession ? '로그인' : '다시 시도',
                  onAction: () =>
                      needsSession
                        ? (Env.appEnv == 'local'
                          ? _signInForLocalIfPossible()
                          : context.push('/login?returnTo=%2Fcreator'))
                          : ref.invalidate(creatorRecipesProvider(_searchQuery)),
                );
              },
            ),
          ),
        ],
      ),
      floatingActionButton: null,
    );
  }
}
