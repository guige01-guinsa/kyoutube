import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../features/auth/presentation/login_page.dart';
import '../../features/home/presentation/home_page.dart';
import '../../features/recipes/presentation/create_creator_recipe_page.dart';
import '../../features/recipes/presentation/creator_recipe_detail_page.dart';
import '../../features/recipes/presentation/creator_recipes_page.dart';
import '../../features/recipes/presentation/recipe_detail_page.dart';

class AppRouter {
  static final GoRouter router = GoRouter(
    initialLocation: '/',
    routes: <RouteBase>[
      GoRoute(
        path: '/',
        builder: (BuildContext context, GoRouterState state) =>
            const HomePage(),
      ),
      GoRoute(
        path: '/login',
        builder: (BuildContext context, GoRouterState state) =>
            const LoginPage(),
      ),
      GoRoute(
        path: '/recipes/:id',
        builder: (BuildContext context, GoRouterState state) {
          final id = state.pathParameters['id'] ?? '';
          return RecipeDetailPage(recipeId: id);
        },
      ),
      GoRoute(
        path: '/creator',
        builder: (BuildContext context, GoRouterState state) =>
            const CreatorRecipesPage(),
      ),
      GoRoute(
        path: '/creator/new',
        builder: (BuildContext context, GoRouterState state) =>
            const CreateCreatorRecipePage(),
      ),
      GoRoute(
        path: '/creator/:id',
        builder: (BuildContext context, GoRouterState state) {
          final id = state.pathParameters['id'] ?? '';
          return CreatorRecipeDetailPage(recipeId: id);
        },
      ),
    ],
  );
}
