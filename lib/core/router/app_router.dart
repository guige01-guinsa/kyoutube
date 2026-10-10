import '../../features/marketing/presentation/marketing_page.dart';
import '../auth/auth_return.dart';
import '../../features/shopping/presentation/purchase_cleanup_page.dart';
import '../../features/shopping/presentation/affiliate_display_page.dart';
import '../../features/business/presentation/business_pages.dart';
import '../../features/business/presentation/business_coupang_page.dart';
import '../../features/business/domain/business_navigation.dart';
import '../../features/auth/application/auth_providers.dart';
import '../../features/guide/presentation/guide_sample_page.dart';
import '../../features/guide/presentation/guide_sample_pdf_page.dart';
import '../../features/workspace/application/workspace_profile_controller.dart';
import '../../features/workspace/domain/workspace_profile.dart';
import '../../features/shopping/application/purchase_workspace.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../features/workspace/presentation/workspace_frame.dart';
import '../../features/workspace/presentation/workspace_page.dart';
import '../../features/workspace/presentation/workspace_preferences_page.dart';
import '../../features/workspace/application/workspace_navigation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../features/auth/presentation/mfa_page.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../widgets/diagnostics_page.dart';
import '../widgets/centered_state_view.dart';
import '../../features/auth/presentation/login_page.dart';
import '../../features/auth/presentation/account_page.dart';
import '../../features/auth/presentation/reset_password_page.dart';
import '../../features/ingredient_search/presentation/ingredient_search_page.dart';
import '../../features/ingredient_search/presentation/ingredient_search_results_page.dart';
import '../../features/home/presentation/home_page.dart';
import '../../features/operations/presentation/operations_page.dart';
import '../../features/operations/presentation/operations_inbox_page.dart';
import '../../features/chef/presentation/chef_workbench_page.dart';
import '../../features/chef/presentation/chef_hub_page.dart';
import '../../features/chef/presentation/chef_sales_page.dart';
import '../../features/home/presentation/classic_recipe_widgets.dart';
import '../../features/home/domain/korean_classics.dart';
import '../../features/guide/presentation/product_guide_page.dart';
import '../../features/guide/domain/guide_curriculum.dart';
import '../../features/kitchen/presentation/kitchen_page.dart';
import '../../features/kitchen/presentation/shopping_review_page.dart';
import '../../features/shopping/presentation/shopping_assistant_page.dart';
import '../../features/shopping/presentation/shopping_preparation_page.dart';
import '../../features/shopping/presentation/shopping_hub_page.dart';
import '../../features/shopping/domain/shopping_navigation.dart';
import '../../features/shopping/presentation/supplier_requests_page.dart';
import '../../features/shopping/presentation/request_ledger_page.dart';
import '../../features/suppliers/presentation/supplier_directory_page.dart';
import '../../features/suppliers/presentation/supplier_business_page.dart';
import '../../features/suppliers/presentation/procurement_plan_page.dart';
import '../../features/membership/presentation/membership_admin_page.dart';
import '../../features/suppliers/presentation/public_supplier_admin_page.dart';
import '../../features/shopping/presentation/shopping_affiliate_admin_page.dart';
import '../../features/membership/presentation/membership_discount_admin_page.dart';
import '../../features/membership/presentation/membership_policy_admin_page.dart';
import '../../features/membership/presentation/membership_page.dart';
import '../../features/recipes/presentation/create_creator_recipe_page.dart';
import '../../features/recipes/presentation/creator_recipe_detail_page.dart';
import '../../features/recipes/presentation/my_recipes_page.dart';
import '../../features/recipes/presentation/recipe_detail_page.dart';
import '../../features/recipes/presentation/subscriber_recipe_detail_page.dart';
import '../../features/search/presentation/recommended_recipe_search_page.dart';
import '../../features/youtube/presentation/youtube_search_page.dart';

class AppRoutes {
  const AppRoutes._();

  static const String home = '/';
  static const String workspace = '/workspace';
  static String classicDetail(String id) =>
      '/classics/${Uri.encodeComponent(id)}';
  static String classicDraft(String id) => '${classicDetail(id)}/draft';
  static const String diagnostics = '/diagnostics';
  static const String login = '/login';
  static const String resetPassword = '/reset-password';
  static const String account = '/account';
  static const String marketing = '/marketing';
  static const String membership = '/membership';
  static const String membershipAdmin = '/membership/admin';
  static const String shoppingAffiliateWorkflow =
      '/membership/admin/affiliate-workflow';
  static const String shoppingAffiliateDisplay =
      '/membership/admin/affiliate-display';
  static const String shoppingAffiliateAdmin =
      '/membership/admin/affiliate-shopping';
  static const String publicSupplierAdmin =
      '/membership/admin/public-suppliers';
  static const String operations = '/membership/admin/operations';
  static const String operationsInbox = '/membership/admin/operations/inbox';
  static const String membershipDiscountAdmin = '/membership/admin/discounts';
  static const String membershipPolicyAdmin = '/membership/admin/policies';
  static const String guide = '/guide';
  static const String youtube = '/youtube';
  static const String recommendedSearch = '/search';
  static const String ingredientSearch = '/ingredient-search';
  static const String ingredientSearchResults = '/ingredient-search/results';
  static const String creator = '/creator';
  static const String creatorNew = '/creator/new';
  static const String chef = '/chef';
  static const String chefSales = '/chef-sales';
  static String chefWorkspace(String id) =>
      Uri(pathSegments: ['', 'chef', id]).toString();
  static const String myRecipes = '/my-recipes';
  static const String kitchen = '/kitchen';
  static const String shoppingReview = '/shopping-review';
  static const String shoppingAssistant = '/shopping-assistant';
  static const String shoppingPreparation = '/shopping-preparation';
  static const String supplierRequests = '/supplier-requests';
  static const String shoppingStores = '/shopping-stores';
  static const String supplierDirectory = '/supplier-directory';
  static const String supplierBusiness = '/supplier-business';
  static const String procurementPlan = '/supplier-plan';

  static String recipeDetail(String id) =>
      '/recipes/${Uri.encodeComponent(id)}';

  static String recommendedSearchFor(String query) =>
      '$recommendedSearch?q=${Uri.encodeQueryComponent(query)}';

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

  static final _rootNavigator = GlobalKey<NavigatorState>();
  static final GoRouter router = GoRouter(
    navigatorKey: _rootNavigator,
    redirect: (context, state) {
      if (state.uri.path == '/business-samples' ||
          state.uri.path.startsWith('/business-workspaces/')) {
        try {
          if (Supabase.instance.client.auth.currentUser == null) {
            return loginFor(state.uri.toString());
          }
        } catch (_) {
          return loginFor(state.uri.toString());
        }
      }
      if (state.uri.path == '/membership/admin' ||
          state.uri.path.startsWith('/membership/admin/')) {
        try {
          final auth = Supabase.instance.client.auth;
          if (auth.currentSession == null) {
            return loginFor(state.uri.toString());
          }
          if (auth.mfa.getAuthenticatorAssuranceLevel().currentLevel !=
              AuthenticatorAssuranceLevels.aal2) {
            return Uri(
                path: '/account/mfa',
                queryParameters: {'returnTo': state.uri.toString()}).toString();
          }
        } catch (_) {
          return loginFor(state.uri.toString());
        }
      }
      return legacyShoppingRedirect(state.uri);
    },
    initialLocation: AppRoutes.workspace,
    errorBuilder: (BuildContext context, GoRouterState state) {
      return const _RouteErrorPage(
        message: '요청한 페이지를 찾을 수 없습니다.',
      );
    },
    routes: <RouteBase>[
      GoRoute(
          path: AppRoutes.shoppingAffiliateWorkflow,
          builder: (_, __) => const WorkspaceFrame(
              location: AppRoutes.shoppingAffiliateWorkflow,
              child: ShoppingAffiliateAdminPage(guided: true))),
      GoRoute(
          path: AppRoutes.shoppingAffiliateDisplay,
          builder: (_, state) => AffiliateDisplayPage(
              ingredient: state.uri.queryParameters['q'] ?? '',
              expectedId: state.uri.queryParameters['id'])),
      GoRoute(
          path: AppRoutes.shoppingAffiliateAdmin,
          builder: (_, __) => const WorkspaceFrame(
              location: AppRoutes.shoppingAffiliateAdmin,
              child: ShoppingAffiliateAdminPage())),
      GoRoute(
          path: '/guide/practice/:lesson',
          builder: (_, state) => GuideSamplePage(
              key: ValueKey(state.pathParameters['lesson']),
              lessonId: state.pathParameters['lesson']!),
          routes: [
            GoRoute(
                path: 'pdf/:request',
                builder: (_, state) => GuideSamplePdfPage(
                    requestId: state.pathParameters['request']!))
          ]),
      GoRoute(
        path: AppRoutes.guide,
        builder: (_, state) => Consumer(builder: (context, ref, _) {
          final profile = ref.watch(workspaceProfileProvider);
          final mode = profile.valueOrNull?.active;
          final explicit = GuideAudience.values
              .where((a) => a.name == state.uri.queryParameters['audience'])
              .firstOrNull;
          if (profile.isLoading &&
              explicit == null &&
              state.uri.queryParameters['lesson'] == null) {
            return const Scaffold(
                body: Center(child: CircularProgressIndicator()));
          }
          return ProductGuidePage(
              initialLesson: state.uri.queryParameters['lesson'],
              initialAudience: explicit ??
                  switch (mode) {
                    WorkspaceMode.personal => GuideAudience.home,
                    WorkspaceMode.professional => GuideAudience.professional,
                    WorkspaceMode.supplier => GuideAudience.supplier,
                    null => null
                  });
        }),
      ),
      // Keep registration above supplier pickers opened in a root dialog.
      GoRoute(
          path: AppRoutes.publicSupplierAdmin,
          builder: (_, __) => const WorkspaceFrame(
              location: AppRoutes.publicSupplierAdmin,
              child: PublicSupplierAdminPage())),
      GoRoute(
          path: AppRoutes.supplierBusiness,
          builder: (_, state) => WorkspaceFrame(
              location: state.uri.toString(),
              child: SupplierBusinessPage(
                  section:
                      state.uri.queryParameters['section'] ?? 'overview'))),
      GoRoute(
          path: '/business-workspaces/:workspace/menus',
          builder: (_, state) => WorkspaceFrame(
              location: state.uri.toString(),
              child: BusinessMenuPage(
                  workspace: state.pathParameters['workspace']!))),
      GoRoute(
          path: '/business-workspaces/:workspace/inventory/:item',
          builder: (_, state) => WorkspaceFrame(
              location: state.uri.toString(),
              child: Consumer(
                  builder: (_, ref, __) => BusinessInventoryPage(
                      key: ValueKey(
                          '${ref.watch(activeAccountIdProvider)}:${state.uri}'),
                      workspace: state.pathParameters['workspace']!,
                      itemId: state.pathParameters['item']!)))),
      GoRoute(
          path: '/business-workspaces/:workspace/records/:record',
          builder: (_, state) => WorkspaceFrame(
              location: state.uri.toString(),
              child: Consumer(
                  builder: (_, ref, __) => BusinessRecordPage(
                      key: ValueKey(
                          '${ref.watch(activeAccountIdProvider)}:${state.pathParameters['record']}'),
                      workspace: state.pathParameters['workspace']!,
                      recordId: state.pathParameters['record']!)))),
      GoRoute(
          path: '/account/mfa',
          builder: (_, state) => WorkspaceFrame(
              location: state.uri.toString(),
              child: MfaPage(returnTo: state.uri.queryParameters['returnTo']))),
      GoRoute(
          path: AppRoutes.login,
          builder: (BuildContext context, GoRouterState state) =>
              WorkspaceFrame(
                  location: state.uri.toString(),
                  child: LoginPage(
                      returnTo: state.uri.queryParameters['returnTo']))),
      ShellRoute(
          builder: (context, state, child) =>
              WorkspaceFrame(location: state.uri.toString(), child: child),
          routes: [
            GoRoute(
                path: '/business-samples',
                builder: (_, __) => Consumer(
                    builder: (_, ref, __) => BusinessSamplesPage(
                        key: ValueKey(ref.watch(activeAccountIdProvider))))),
            GoRoute(
                path: '/membership/admin/business-tests',
                builder: (_, __) => Consumer(
                    builder: (_, ref, __) => BusinessTestAdminPage(
                        key: ValueKey(ref.watch(activeAccountIdProvider))))),
            GoRoute(
                path: '/business-workspaces',
                builder: (_, __) => const BusinessWorkspacesPage()),
            GoRoute(
                path: '/business-workspaces/:workspace',
                builder: (_, state) => Consumer(
                    builder: (_, ref, __) => BusinessWorkspacePage(
                        key: ValueKey(
                            '${ref.watch(activeAccountIdProvider)}:${state.uri}'),
                        section: businessSection(
                            state.uri.queryParameters['section']),
                        initialStatus:
                            state.uri.queryParameters['status'] ?? 'all',
                        workspace: state.pathParameters['workspace']!))),
            GoRoute(
                path: '/business-workspaces/:workspace/meals',
                builder: (_, state) => BusinessMealsPage(
                    workspace: state.pathParameters['workspace']!)),

            GoRoute(
                path: '/business-workspaces/:workspace/menu-fast',
                onExit: (context, state) => ProviderScope.containerOf(context)
                    .read(workspaceNavigationProvider)
                    .confirmLeave(),
                builder: (_, state) => BusinessMenuFastPage(
                    workspace: state.pathParameters['workspace']!,
                    mealSources: state.extra is MealPurchaseSelection
                        ? (state.extra as MealPurchaseSelection)
                        : null)),
            GoRoute(
                path: '/business-workspaces/:workspace/menu-purchase',
                onExit: (context, state) => ProviderScope.containerOf(context)
                    .read(workspaceNavigationProvider)
                    .confirmLeave(),
                builder: (_, state) => BusinessMenuPurchasePage(
                    workspace: state.pathParameters['workspace']!)),
            GoRoute(
              path: '/business-workspaces/:workspace/suppliers',
              builder: (_, state) => BusinessSuppliersPage(
                  key: ValueKey(state.uri.toString()),
                  workspace: state.pathParameters['workspace']!),
            ),
            GoRoute(
              path: '/business-workspaces/:workspace/suppliers/:supplier',
              builder: (_, state) => BusinessSupplierProductsPage(
                  workspace: state.pathParameters['workspace']!,
                  supplierId: state.pathParameters['supplier']!),
            ),
            GoRoute(
              path: '/business-workspaces/:workspace/inventory',
              builder: (_, state) => Consumer(
                  builder: (_, ref, __) => BusinessInventoryPage(
                      key: ValueKey(
                          '${ref.watch(activeAccountIdProvider)}:${state.uri}'),
                      workspace: state.pathParameters['workspace']!)),
            ),

            GoRoute(
              path: '/business-workspaces/:workspace/receiving/:request',
              builder: (_, state) => Consumer(
                  builder: (_, ref, __) => BusinessReceivingPage(
                      key: ValueKey(
                          '${ref.watch(activeAccountIdProvider)}:${state.uri}'),
                      workspace: state.pathParameters['workspace']!,
                      request: state.pathParameters['request']!)),
            ),
            GoRoute(
                path: '/business-workspaces/:workspace/members',
                builder: (_, state) => Consumer(
                    builder: (_, ref, __) => BusinessMembersPage(
                        key: ValueKey(ref.watch(activeAccountIdProvider)),
                        workspace: state.pathParameters['workspace']!))),
            GoRoute(
                path: '/business-workspaces/:workspace/sales',
                builder: (_, state) => Consumer(
                    builder: (_, ref, __) => BusinessSalesPage(
                        key: ValueKey(ref.watch(activeAccountIdProvider)),
                        workspace: state.pathParameters['workspace']!))),

            GoRoute(
                path: '/business-workspaces/:workspace/new/:kind',
                onExit: (context, state) => ProviderScope.containerOf(context)
                    .read(workspaceNavigationProvider)
                    .confirmLeave(),
                builder: (_, state) => BusinessRecordEditorPage(
                    workspace: state.pathParameters['workspace']!,
                    kind: state.pathParameters['kind']!)),
            GoRoute(
                path: '/business-workspaces/:workspace/edit/:record',
                onExit: (context, state) => ProviderScope.containerOf(context)
                    .read(workspaceNavigationProvider)
                    .confirmLeave(),
                builder: (_, state) => BusinessRecordEditorPage(
                    workspace: state.pathParameters['workspace']!,
                    recordId: state.pathParameters['record']!)),
            GoRoute(
                path: '/workspace-settings',
                builder: (_, __) => const WorkspacePreferencesPage()),
            GoRoute(
                path: '/workspace-menu',
                builder: (_, __) => const WorkspaceMenuPage()),
            GoRoute(
                path: '/shopping/organize',
                onExit: (context, _) => ProviderScope.containerOf(context)
                    .read(workspaceNavigationProvider)
                    .confirmLeave(),
                builder: (_, state) => PurchaseCleanupPage(
                    archived: state.uri.queryParameters['archived'] == 'true')),
            GoRoute(
                path: '/shopping/kitchen',
                onExit: (context, _) => ProviderScope.containerOf(context)
                    .read(workspaceNavigationProvider)
                    .confirmLeave(),
                builder: (_, __) => Consumer(
                    builder: (_, ref, __) => KitchenPage(
                        key: ValueKey(ref.watch(activeAccountIdProvider)),
                        toolsOnly: true))),
            GoRoute(
                path: '/business-workspaces/:workspace/organize',
                onExit: (context, _) => ProviderScope.containerOf(context)
                    .read(workspaceNavigationProvider)
                    .confirmLeave(),
                builder: (_, state) => PurchaseCleanupPage(
                    workspace: state.pathParameters['workspace'],
                    archived: state.uri.queryParameters['archived'] == 'true')),
            GoRoute(
                path: '/business-workspaces/:workspace/coupang/:record',
                builder: (_, state) => Consumer(
                    builder: (_, ref, __) => BusinessCoupangPage(
                        key: ValueKey(
                            '${ref.watch(activeAccountIdProvider)}:${state.uri}'),
                        workspace: state.pathParameters['workspace']!,
                        recordId: state.pathParameters['record']!))),
            GoRoute(
                path: '/shopping',
                onExit: (context, state) => ProviderScope.containerOf(context)
                    .read(workspaceNavigationProvider)
                    .confirmLeave(),
                builder: (_, state) => ShoppingHubPage(
                    stage: shoppingStage(state.uri.queryParameters['stage']),
                    listId: state.uri.queryParameters['list'],
                    view: state.uri.queryParameters['view'],
                    requestId: state.uri.queryParameters['request'])),
            GoRoute(
                path: '/workspace-switch/:mode',
                builder: (_, state) =>
                    WorkspaceSwitchPage(mode: state.pathParameters['mode']!)),
            GoRoute(
                path: AppRoutes.workspace,
                builder: (_, state) => WorkspacePage(
                    personalStudio:
                        state.uri.queryParameters['area'] == 'personal')),
            GoRoute(
                path: AppRoutes.supplierDirectory,
                builder: (_, state) => SupplierDirectoryPage(
                    selectMode: state.uri.queryParameters['select'] == '1',
                    query: state.uri.queryParameters['q'] ?? '')),
            GoRoute(
                onExit: (context, state) => ProviderScope.containerOf(context)
                    .read(workspaceNavigationProvider)
                    .confirmLeave(),
                path: AppRoutes.procurementPlan,
                builder: (_, state) => ProcurementPlanPage(
                    listId: state.uri.queryParameters['list'])),
            GoRoute(
                onExit: (context, state) => ProviderScope.containerOf(context)
                    .read(workspaceNavigationProvider)
                    .confirmLeave(),
                path: AppRoutes.shoppingStores,
                builder: (_, state) => SupplierRequestsPage(
                    listId: state.uri.queryParameters['list'],
                    showStores: true)),
            GoRoute(
                onExit: (context, state) => ProviderScope.containerOf(context)
                    .read(workspaceNavigationProvider)
                    .confirmLeave(),
                path: '/purchases',
                builder: (_, state) => SupplierRequestsPage(
                    listId: state.uri.queryParameters['list'],
                    requestId: state.uri.queryParameters['request'],
                    initialStage: purchaseStageFromName(
                        state.uri.queryParameters['stage']))),
            GoRoute(
                onExit: (context, state) => ProviderScope.containerOf(context)
                    .read(workspaceNavigationProvider)
                    .confirmLeave(),
                path: AppRoutes.supplierRequests,
                builder: (_, state) => SupplierRequestsPage(
                    listId: state.uri.queryParameters['list'],
                    requestId: state.uri.queryParameters['request'],
                    initialStage: purchaseStageFromName(
                        state.uri.queryParameters['stage']))),
            GoRoute(
                onExit: (context, state) => ProviderScope.containerOf(context)
                    .read(workspaceNavigationProvider)
                    .confirmLeave(),
                path: '/supplier-request-ledger',
                builder: (_, __) => const RequestLedgerPage()),
            GoRoute(
                path: AppRoutes.shoppingAssistant,
                builder: (_, state) => ShoppingAssistantPage(
                    listId: state.uri.queryParameters['list'])),
            GoRoute(
                path: AppRoutes.shoppingPreparation,
                builder: (_, state) => ShoppingPreparationPage(
                    listId: state.uri.queryParameters['list'])),

            GoRoute(
                path: AppRoutes.chef, builder: (_, __) => const ChefHubPage()),
            GoRoute(
                path: AppRoutes.chefSales,
                builder: (_, __) => const ChefSalesPage()),
            GoRoute(
                path: '/chef-sales/:id',
                builder: (_, state) =>
                    ChefSalesPage(recipeId: state.pathParameters['id']!)),
            GoRoute(
              onExit: (context, state) => ProviderScope.containerOf(context)
                  .read(workspaceNavigationProvider)
                  .confirmLeave(),
              path: '/chef/:id',
              builder: (_, state) =>
                  ChefWorkbenchPage(recipeId: state.pathParameters['id']!),
            ),
            GoRoute(
                path: AppRoutes.operations,
                builder: (_, __) => const OperationsPage()),
            GoRoute(
                path: AppRoutes.operationsInbox,
                builder: (_, __) => const OperationsInboxPage()),
            GoRoute(
              path: '/classics/:id',
              builder: (_, state) {
                final matches = koreanClassics
                    .where((recipe) => recipe.id == state.pathParameters['id']);
                if (matches.isEmpty) {
                  return const _RouteErrorPage(message: '요청한 페이지를 찾을 수 없습니다.');
                }
                return ClassicRecipePage(recipe: matches.first);
              },
              routes: [
                GoRoute(
                    onExit: (context, state) =>
                        ProviderScope.containerOf(context)
                            .read(workspaceNavigationProvider)
                            .confirmLeave(),
                    path: 'draft',
                    builder: (_, state) {
                      final matches = koreanClassics.where(
                          (recipe) => recipe.id == state.pathParameters['id']);
                      if (matches.isEmpty) {
                        return const _RouteErrorPage(
                            message: '요청한 페이지를 찾을 수 없습니다.');
                      }
                      return ClassicDraftPage(recipe: matches.first);
                    })
              ],
            ),
            if (!kReleaseMode)
              GoRoute(
                  path: AppRoutes.diagnostics,
                  builder: (_, __) => const DiagnosticsPage()),
            GoRoute(
              path: AppRoutes.ingredientSearch,
              builder: (BuildContext context, GoRouterState state) =>
                  const IngredientSearchPage(),
            ),
            GoRoute(
              path: AppRoutes.ingredientSearchResults,
              builder: (BuildContext context, GoRouterState state) {
                final rawIngredients =
                    state.uri.queryParameters['ingredients'] ?? '';

                final ingredients = rawIngredients
                    .split(',')
                    .map((item) => item.trim())
                    .where((item) => item.isNotEmpty)
                    .take(5)
                    .toList(growable: false);

                if (ingredients.isEmpty) {
                  return const _RouteErrorPage(
                    message: '선택한 재료가 없습니다.',
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

            GoRoute(
              path: AppRoutes.recommendedSearch,
              builder: (BuildContext context, GoRouterState state) =>
                  RecommendedRecipeSearchPage(
                initialQuery: state.uri.queryParameters['q'] ?? '',
              ),
            ),

            // YouTube recipe search.
            GoRoute(
              onExit: (context, state) => ProviderScope.containerOf(context)
                  .read(workspaceNavigationProvider)
                  .confirmLeave(),
              path: AppRoutes.youtube,
              builder: (BuildContext context, GoRouterState state) =>
                  YoutubeSearchPage(
                initialQuery: state.uri.queryParameters['q'],
              ),
            ),

            GoRoute(
              path: AppRoutes.marketing,
              builder: (BuildContext context, GoRouterState state) =>
                  const MarketingPage(),
            ),

            // Auth.

            GoRoute(
              path: AppRoutes.account,
              builder: (BuildContext context, GoRouterState state) =>
                  const AccountPage(),
            ),
            GoRoute(
              path: AppRoutes.membership,
              builder: (BuildContext context, GoRouterState state) =>
                  const MembershipPage(),
            ),
            GoRoute(
              path: AppRoutes.membershipAdmin,
              builder: (BuildContext context, GoRouterState state) =>
                  const MembershipAdminPage(),
            ),
            GoRoute(
              path: AppRoutes.membershipDiscountAdmin,
              builder: (BuildContext context, GoRouterState state) =>
                  const MembershipDiscountAdminPage(),
            ),
            GoRoute(
              path: AppRoutes.membershipPolicyAdmin,
              builder: (BuildContext context, GoRouterState state) =>
                  const MembershipPolicyAdminPage(),
            ),
            GoRoute(
              path: AppRoutes.resetPassword,
              builder: (BuildContext context, GoRouterState state) =>
                  const ResetPasswordPage(),
            ),

            // Public recipes.
            GoRoute(
              path: '/recipes/:id',
              builder: (BuildContext context, GoRouterState state) {
                final String id = state.pathParameters['id'] ?? '';
                if (id.isEmpty) {
                  return const _RouteErrorPage(message: '레시피를 찾을 수 없습니다.');
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
              onExit: (context, state) => ProviderScope.containerOf(context)
                  .read(workspaceNavigationProvider)
                  .confirmLeave(),
              path: AppRoutes.creatorNew,
              builder: (BuildContext context, GoRouterState state) =>
                  const CreateCreatorRecipePage(),
            ),
            GoRoute(
              onExit: (context, state) => ProviderScope.containerOf(context)
                  .read(workspaceNavigationProvider)
                  .confirmLeave(),
              path: '/creator/:id',
              builder: (BuildContext context, GoRouterState state) {
                final String id = state.pathParameters['id'] ?? '';
                if (id.isEmpty) {
                  return const _RouteErrorPage(message: '레시피를 찾을 수 없습니다.');
                }

                return CreatorRecipeDetailPage(recipeId: id);
              },
            ),

            // My recipes.
            GoRoute(
              path: AppRoutes.myRecipes,
              builder: (BuildContext context, GoRouterState state) =>
                  MyRecipesPage(
                initialTab:
                    state.uri.queryParameters['tab'] == 'excluded' ? 1 : 0,
              ),
            ),
            GoRoute(
              onExit: (context, state) => ProviderScope.containerOf(context)
                  .read(workspaceNavigationProvider)
                  .confirmLeave(),
              path: '/my-recipes/:id',
              builder: (BuildContext context, GoRouterState state) {
                final String id = state.pathParameters['id'] ?? '';
                if (id.isEmpty) {
                  return const _RouteErrorPage(message: '레시피를 찾을 수 없습니다.');
                }

                return SubscriberRecipeDetailPage(recipeId: id);
              },
            ),

            // Kitchen.
            GoRoute(
              path: AppRoutes.kitchen,
              builder: (BuildContext context, GoRouterState state) {
                final String tab =
                    state.uri.queryParameters['tab'] ?? 'ingredients';

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
          ]),
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
        title: const Text('페이지 안내'),
      ),
      body: CenteredStateView(
        icon: Icons.explore_off_outlined,
        title: '다른 레시피를 찾아볼까요?',
        message: message,
        actionLabel: '홈으로 이동',
        onAction: () => context.go(AppRoutes.home),
      ),
    );
  }
}
