import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../features/auth/presentation/login_page.dart';
import '../../features/home/presentation/home_page.dart';
import '../../features/kitchen/presentation/kitchen_page.dart';
import '../../features/kitchen/presentation/shopping_review_page.dart';
import '../../features/recipes/presentation/bookmarked_recipes_page.dart';
import '../../features/recipes/presentation/create_creator_recipe_page.dart';
import '../../features/recipes/presentation/creator_recipe_detail_page.dart';
import '../../features/recipes/presentation/my_recipes_page.dart';
import '../../features/recipes/presentation/recipe_detail_page.dart';
import '../../features/recipes/presentation/subscriber_recipe_detail_page.dart';
import '../../features/youtube/presentation/youtube_search_page.dart';

class AppRoutes {
  const AppRoutes._();

  static const String home = '/';
  static const String login = '/login';
  static const String youtube = '/youtube';
  static const String bookmarks = '/bookmarks';
  static const String creator = '/creator';
  static const String creatorNew = '/creator/new';
  static const String myRecipes = '/my-recipes';
  static const String kitchen = '/kitchen';
  static const String shoppingReview = '/shopping-review';

  static String recipeDetail(String id) =>
      '/recipes/${Uri.encodeComponent(id)}';

  static String creatorDetail(String id) =>
      '/creator/${Uri.encodeComponent(id)}';

  static String myRecipeDetail(String id) =>
      '/my-recipes/${Uri.encodeComponent(id)}';

  static String kitchenWithTab(String tab) =>
      '$kitchen?tab=${Uri.encodeQueryComponent(tab)}';

  static String shoppingReviewWithSource(String source) =>
      '$shoppingReview?source=${Uri.encodeQueryComponent(source)}';
}

class AppRouter {
  const AppRouter._();

  static final GoRouter router = GoRouter(
    initialLocation: AppRoutes.home,
    errorBuilder: (BuildContext context, GoRouterState state) {
      return _RouteErrorPage(
        message: state.error?.toString() ?? '페이지를 찾을 수 없습니다.',
      );
    },
    routes: <RouteBase>[
      GoRoute(
        path: AppRoutes.home,
        builder: (BuildContext context, GoRouterState state) =>
            const HomePage(),
      ),

      // YouTube recipe search.
      GoRoute(
        path: AppRoutes.youtube,
        builder: (BuildContext context, GoRouterState state) =>
            const YoutubeSearchPage(),
      ),

      // Auth.
      GoRoute(
        path: AppRoutes.login,
        builder: (BuildContext context, GoRouterState state) =>
            const LoginPage(),
      ),

      // Public/bookmarked recipes.
      GoRoute(
        path: AppRoutes.bookmarks,
        builder: (BuildContext context, GoRouterState state) =>
            const BookmarkedRecipesPage(),
      ),
      GoRoute(
        path: '/recipes/:id',
        builder: (BuildContext context, GoRouterState state) {
          final String id = state.pathParameters['id'] ?? '';
          if (id.isEmpty) {
            return const _RouteErrorPage(message: '레시피 ID가 없습니다.');
          }

          return RecipeDetailPage(recipeId: id);
        },
      ),

      // Legacy creator list URL.
      // 레시피 생성 방식과 관계없이 목록 출력은 내 레시피 관리로 통일한다.
      GoRoute(
        path: AppRoutes.creator,
        redirect: (BuildContext context, GoRouterState state) =>
            AppRoutes.myRecipes,
      ),
      GoRoute(
        path: AppRoutes.creatorNew,
        builder: (BuildContext context, GoRouterState state) =>
            const CreateCreatorRecipePage(),
      ),
      GoRoute(
        path: '/creator/:id',
        builder: (BuildContext context, GoRouterState state) {
          final String id = state.pathParameters['id'] ?? '';
          if (id.isEmpty) {
            return const _RouteErrorPage(message: '크리에이터 레시피 ID가 없습니다.');
          }

          return CreatorRecipeDetailPage(recipeId: id);
        },
      ),

      // My recipes.
      GoRoute(
        path: AppRoutes.myRecipes,
        builder: (BuildContext context, GoRouterState state) =>
            const MyRecipesPage(),
      ),
      GoRoute(
        path: '/my-recipes/:id',
        builder: (BuildContext context, GoRouterState state) {
          final String id = state.pathParameters['id'] ?? '';
          if (id.isEmpty) {
            return const _RouteErrorPage(message: '내 레시피 ID가 없습니다.');
          }

          return SubscriberRecipeDetailPage(recipeId: id);
        },
      ),

      // Kitchen.
      GoRoute(
        path: AppRoutes.kitchen,
        builder: (BuildContext context, GoRouterState state) {
          final String tab = state.uri.queryParameters['tab'] ?? 'ingredients';

          return KitchenPage(initialTab: tab);
        },
      ),
      GoRoute(
        path: AppRoutes.shoppingReview,
        builder: (BuildContext context, GoRouterState state) {
          final String source = state.uri.queryParameters['source'] ?? '';

          return ShoppingReviewPage(sourceRecipeReference: source);
        },
      ),
    ],
  );
}

class _RouteErrorPage extends StatelessWidget {
  const _RouteErrorPage({
    required this.message,
  });

  final String message;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('이동 오류'),
      ),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text(
            message,
            textAlign: TextAlign.center,
          ),
        ),
      ),
    );
  }
}
