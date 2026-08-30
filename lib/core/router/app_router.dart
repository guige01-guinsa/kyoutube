import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../features/auth/presentation/login_page.dart';
import '../../features/auth/presentation/account_page.dart';
import '../../features/auth/presentation/reset_password_page.dart';
import '../../features/ingredient_search/presentation/ingredient_search_page.dart';
import '../../features/ingredient_search/presentation/ingredient_search_results_page.dart';
import '../../features/home/presentation/home_page.dart';
import '../../features/kitchen/presentation/kitchen_page.dart';
import '../../features/kitchen/presentation/shopping_review_page.dart';
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
  static const String resetPassword = '/reset-password';
  static const String account = '/account';
  static const String youtube = '/youtube';
  static const String ingredientSearch = '/ingredient-search';
  static const String ingredientSearchResults = '/ingredient-search/results';
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

  static String myRecipesWithTab(String tab) =>
      '$myRecipes?tab=${Uri.encodeQueryComponent(tab)}';

  static String shoppingReviewWithSource(String source) =>
      '$shoppingReview?source=${Uri.encodeQueryComponent(source)}';
}

class AppRouter {
  const AppRouter._();

  static final GoRouter router = GoRouter(
    initialLocation: AppRoutes.home,
    errorBuilder: (BuildContext context, GoRouterState state) {
      return _RouteErrorPage(
        message: state.error?.toString() ?? '?섏씠吏瑜?李얠쓣 ???놁뒿?덈떎.',
      );
    },
    routes: <RouteBase>[
      GoRoute(
        path: AppRoutes.ingredientSearch,
        builder: (BuildContext context, GoRouterState state) =>
            const IngredientSearchPage(),
      ),
      GoRoute(
        path: AppRoutes.ingredientSearchResults,
        builder: (BuildContext context, GoRouterState state) {
          final rawIngredients = state.uri.queryParameters['ingredients'] ?? '';

          final ingredients = rawIngredients
              .split(',')
              .map((item) => item.trim())
              .where((item) => item.isNotEmpty)
              .take(5)
              .toList(growable: false);

          if (ingredients.isEmpty) {
            return const _RouteErrorPage(
              message: '?좏깮???щ즺媛 ?놁뒿?덈떎.',
            );
          }

          return IngredientSearchResultsPage(
            ingredients: ingredients,
          );
        },
      ),
      GoRoute(
        path: AppRoutes.home,
        builder: (BuildContext context, GoRouterState state) =>
            const HomePage(),
      ),

      // YouTube recipe search.
      GoRoute(
        path: AppRoutes.youtube,
        builder: (BuildContext context, GoRouterState state) =>
            YoutubeSearchPage(
          initialQuery: state.uri.queryParameters['q'],
        ),
      ),

      // Auth.
      GoRoute(
        path: AppRoutes.login,
        builder: (BuildContext context, GoRouterState state) =>
            const LoginPage(),
      ),
      GoRoute(
        path: AppRoutes.account,
        builder: (BuildContext context, GoRouterState state) =>
            const AccountPage(),
      ),
      GoRoute(
        path: AppRoutes.resetPassword,
        builder: (BuildContext context, GoRouterState state) =>
            const ResetPasswordPage(),
      ),

      // Public/bookmarked recipes.
      GoRoute(
        path: AppRoutes.bookmarks,
        redirect: (BuildContext context, GoRouterState state) =>
            AppRoutes.myRecipesWithTab('saved'),
      ),
      GoRoute(
        path: '/recipes/:id',
        builder: (BuildContext context, GoRouterState state) {
          final String id = state.pathParameters['id'] ?? '';
          if (id.isEmpty) {
            return const _RouteErrorPage(message: '?덉떆??ID媛 ?놁뒿?덈떎.');
          }

          return RecipeDetailPage(recipeId: id);
        },
      ),

      // Legacy creator list URL.
      // ?덉떆???앹꽦 諛⑹떇怨?愿怨꾩뾾??紐⑸줉 異쒕젰? ???덉떆??愿由щ줈 ?듭씪?쒕떎.
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
            return const _RouteErrorPage(message: '?щ━?먯씠???덉떆??ID媛 ?놁뒿?덈떎.');
          }

          return CreatorRecipeDetailPage(recipeId: id);
        },
      ),

      // My recipes.
      GoRoute(
        path: AppRoutes.myRecipes,
        builder: (BuildContext context, GoRouterState state) => MyRecipesPage(
          initialTab: state.uri.queryParameters['tab'] == 'saved' ? 1 : 0,
        ),
      ),
      GoRoute(
        path: '/my-recipes/:id',
        builder: (BuildContext context, GoRouterState state) {
          final String id = state.pathParameters['id'] ?? '';
          if (id.isEmpty) {
            return const _RouteErrorPage(message: '???덉떆??ID媛 ?놁뒿?덈떎.');
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
        title: const Text('?대룞 ?ㅻ쪟'),
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
