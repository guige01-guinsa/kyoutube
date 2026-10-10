import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:k_youtube/core/localization/localized_text.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/router/app_router.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/localization/app_localizations.dart';
import '../../../core/widgets/scout_brand_mark.dart';
import '../../../core/widgets/scout_navigation_bar.dart';
import '../../auth/application/account_service.dart';
import '../../auth/application/auth_providers.dart';
import '../../recipes/application/recipe_providers.dart';
import '../domain/korean_classics.dart';
import 'classic_recipe_widgets.dart';
import 'classic_category_picker.dart';
import '../../workspace/presentation/workspace_menu.dart';
import '../../workspace/presentation/workspace_frame.dart';
import '../../../core/widgets/official_channels_card.dart';
import '../../recipes/application/recipe_library_provider.dart';
import '../../recipes/domain/recipe_library_name.dart';

enum _HomeMenuAction { guide, account, signIn, signOut, diagnostics }

class HomePage extends ConsumerStatefulWidget {
  const HomePage({super.key});
  @override
  ConsumerState<HomePage> createState() => _HomePageState();
}

class _HomePageState extends ConsumerState<HomePage> {
  String _category = 'all';

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final recipes = koreanClassics
        .where((recipe) => _category == 'all' || recipe.category == _category)
        .toList();
    final user = ref.watch(authUserProvider).valueOrNull;
    return Scaffold(
      appBar: WorkspaceScope.active(context)
          ? null
          : AppBar(
              automaticallyImplyLeading: false,
              title: Row(children: <Widget>[
                const ScoutBrandMark(excludeFromSemantics: true),
                const SizedBox(width: 10),
                Flexible(
                    child: LocalizedText(l10n.appName,
                        maxLines: 1, overflow: TextOverflow.ellipsis)),
              ]),
              actions: <Widget>[
                if (!WorkspaceScope.hasFrame(context))
                  PopupMenuButton<_HomeMenuAction>(
                    tooltip: l10n.more,
                    icon: const Icon(Icons.more_horiz),
                    onSelected: (action) async {
                      switch (action) {
                        case _HomeMenuAction.guide:
                          context.push(AppRoutes.guide);
                        case _HomeMenuAction.account:
                          context.push(AppRoutes.account);
                        case _HomeMenuAction.signIn:
                          context.push(AppRoutes.login);
                        case _HomeMenuAction.signOut:
                          await ref
                              .read(accountServiceProvider)
                              .signOutCurrentAccount();
                        case _HomeMenuAction.diagnostics:
                          context.push(AppRoutes.diagnostics);
                      }
                    },
                    itemBuilder: (_) => <PopupMenuEntry<_HomeMenuAction>>[
                      PopupMenuItem(
                          value: _HomeMenuAction.guide,
                          child: LocalizedText(l10n.gettingStarted)),
                      if (user != null)
                        PopupMenuItem(
                            value: _HomeMenuAction.account,
                            child: LocalizedText(l10n.account)),
                      PopupMenuItem(
                          value: user == null
                              ? _HomeMenuAction.signIn
                              : _HomeMenuAction.signOut,
                          child: LocalizedText(
                              user == null ? l10n.signIn : l10n.signOut)),
                      if (!kReleaseMode)
                        PopupMenuItem(
                            value: _HomeMenuAction.diagnostics,
                            child: LocalizedText(l10n.diagnostics)),
                    ],
                  ),
                const SizedBox(width: 8),
              ],
            ),
      bottomNavigationBar: const ScoutNavigationBar(selectedIndex: 0),
      body: Align(
        alignment: Alignment.topCenter,
        child: ConstrainedBox(
          constraints:
              const BoxConstraints(maxWidth: ScoutStyle.workspaceWidth),
          child: RefreshIndicator(
            onRefresh: () async {
              ref.invalidate(kitchenSummaryProvider);
            },
            child: CustomScrollView(
              key: const PageStorageKey('scout-home'),
              physics: const AlwaysScrollableScrollPhysics(),
              slivers: <Widget>[
                SliverPadding(
                  padding: const EdgeInsets.fromLTRB(20, 12, 20, 0),
                  sliver: SliverToBoxAdapter(
                      child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: <Widget>[
                      if (!WorkspaceScope.hasFrame(context)) ...[
                        const Align(
                            alignment: Alignment.centerLeft,
                            child: WorkspaceModeButton()),
                        const SizedBox(height: 8),
                      ],
                      _CollectionHero(
                        signedIn: user != null,
                        owner: ref.watch(recipeOwnerNameProvider),
                        l10n: l10n,
                      ),
                      if (user != null) ...[
                        const SizedBox(height: 20),
                        const _KitchenSummaryCard(),
                      ],
                      const SizedBox(height: 32),
                      const Divider(),
                      const SizedBox(height: 24),
                      Text(homeLabel(context, 'collection'),
                          key: const Key('home-curated-heading'),
                          style: Theme.of(context).textTheme.titleLarge),
                      const SizedBox(height: 8),
                      Text(homeLabel(context, 'intro'),
                          style: Theme.of(context).textTheme.bodySmall),
                      const SizedBox(height: 16),
                      ClassicCategoryPicker(
                          selected: _category,
                          onSelected: (category) =>
                              setState(() => _category = category)),
                      const SizedBox(height: 20),
                    ],
                  )),
                ),
                SliverPadding(
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  sliver: SliverLayoutBuilder(builder: (context, constraints) {
                    final width = constraints.crossAxisExtent;
                    final columns =
                        MediaQuery.textScalerOf(context).scale(1) > 1.3
                            ? 1
                            : width >= 1000
                                ? 3
                                : width >= 680
                                    ? 2
                                    : 1;
                    return SliverList.separated(
                      itemCount: (recipes.length / columns).ceil(),
                      separatorBuilder: (_, __) => const SizedBox(height: 20),
                      itemBuilder: (_, row) => Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          for (var column = 0; column < columns; column++) ...[
                            if (column > 0) const SizedBox(width: 20),
                            Expanded(
                                child: row * columns + column < recipes.length
                                    ? ClassicRecipeCard(
                                        recipe: recipes[row * columns + column],
                                        index: koreanClassics.indexOf(recipes[
                                                row * columns + column]) +
                                            1)
                                    : const SizedBox()),
                          ],
                        ],
                      ),
                    );
                  }),
                ),
                SliverPadding(
                  padding: const EdgeInsets.fromLTRB(20, 24, 20, 32),
                  sliver: SliverToBoxAdapter(
                      child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Text(homeLabel(context, 'curation'),
                          style: Theme.of(context).textTheme.bodySmall),
                      const SizedBox(height: 12),
                      Text(homeLabel(context, 'guest'),
                          style: Theme.of(context).textTheme.bodySmall),
                      const SizedBox(height: 20),
                      Align(
                        alignment: Alignment.centerLeft,
                        child: TextButton.icon(
                          key: const Key('recipe-scout-guide-banner'),
                          onPressed: () => context.push(AppRoutes.guide),
                          icon:
                              const Icon(Icons.auto_stories_outlined, size: 20),
                          label: LocalizedText(l10n.oneMinuteGuide),
                        ),
                      ),
                      const SizedBox(height: 12),
                      const OfficialChannelsCard(),
                    ],
                  )),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _CollectionHero extends StatelessWidget {
  const _CollectionHero(
      {required this.signedIn, required this.owner, required this.l10n});
  final bool signedIn;
  final String? owner;
  final AppLocalizations l10n;
  @override
  Widget build(BuildContext context) => LayoutBuilder(builder: (context, box) {
        final wide = box.maxWidth >= 820 &&
            MediaQuery.textScalerOf(context).scale(1) <= 1.3;
        final recipe = koreanClassics.first;
        final introduction =
            Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Text(
              workspaceText(
                  context, '오늘의 한 끼,\n나답게.', 'Your table,\nyour way.'),
              style: Theme.of(context).textTheme.headlineLarge?.copyWith(
                  fontSize: wide ? 44 : 28,
                  height: 1.25,
                  fontWeight: FontWeight.w800,
                  letterSpacing: -1.2)),
          SizedBox(height: wide ? 12 : 8),
          Text(
              workspaceText(
                  context, '발견한 레시피를 나의 요리로.', 'Make every recipe your own.'),
              style: Theme.of(context)
                  .textTheme
                  .bodyLarge
                  ?.copyWith(color: ScoutStyle.muted)),
          SizedBox(height: wide ? 20 : 16),
          const _PublicRecipeSearchBar(),
          const SizedBox(height: 12),
          LayoutBuilder(builder: (context, constraints) {
            final stacked = constraints.maxWidth < 280 ||
                MediaQuery.textScalerOf(context).scale(1) > 1.3;
            final width =
                stacked ? constraints.maxWidth : (constraints.maxWidth - 8) / 2;
            final style = FilledButton.styleFrom(
                minimumSize: const Size(0, 48),
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 12));
            return Wrap(spacing: 8, runSpacing: 8, children: [
              SizedBox(
                  width: width,
                  child: FilledButton.icon(
                      key: const Key('video-recipe-entry'),
                      style: style,
                      onPressed: () => context.push(AppRoutes.youtube),
                      icon: !stacked && constraints.maxWidth < 300
                          ? null
                          : const Icon(Icons.add_link, size: 20),
                      label: Text(
                          workspaceText(context, '레시피 가져오기', 'Import recipe'),
                          textAlign: TextAlign.center))),
              SizedBox(
                  width: width,
                  child: FilledButton.tonalIcon(
                      key: const Key('home-create-recipe'),
                      style: style,
                      onPressed: () => context.push(
                          signedIn ? AppRoutes.creatorNew : AppRoutes.login),
                      icon: !stacked && constraints.maxWidth < 300
                          ? null
                          : const Icon(Icons.edit_note, size: 20),
                      label: Text(
                          workspaceText(context, '직접 만들기', 'Create recipe'),
                          textAlign: TextAlign.center))),
            ]);
          }),
          const SizedBox(height: 12),
          Text(
              workspaceText(
                  context,
                  '저장 위치: ${recipeLibraryName(owner: owner)}',
                  'Save to: ${recipeLibraryName(owner: owner, english: true)}'),
              key: const Key('collection-save-destination'),
              style: Theme.of(context).textTheme.bodySmall),
          const SizedBox(height: 16),
          _DiscoveryShortcuts(l10n: l10n),
        ]);
        final photo = Card(
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: () => context.push(AppRoutes.classicDetail(recipe.id)),
            child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  ClassicImage(
                      recipe: recipe, aspectRatio: wide ? 1.45 : 16 / 9),
                  Padding(
                      padding: const EdgeInsets.all(20),
                      child: Row(children: [
                        Expanded(
                            child: Text(homeText(context, recipe.name),
                                style: Theme.of(context).textTheme.titleLarge)),
                        const Icon(Icons.arrow_outward, color: ScoutStyle.plum),
                      ])),
                ]),
          ),
        );
        if (wide) {
          return Padding(
              padding: const EdgeInsets.symmetric(vertical: 24),
              child:
                  Row(crossAxisAlignment: CrossAxisAlignment.center, children: [
                Expanded(flex: 6, child: introduction),
                const SizedBox(width: 40),
                Expanded(flex: 5, child: photo),
              ]));
        }
        return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              introduction,
              const SizedBox(height: 24),
              photo,
            ]);
      });
}

class _DiscoveryShortcuts extends StatelessWidget {
  const _DiscoveryShortcuts({required this.l10n});
  final AppLocalizations l10n;
  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (context, constraints) {
      final largeText = MediaQuery.textScalerOf(context).scale(1) > 1.3;
      final columns = largeText || constraints.maxWidth < 340 ? 1 : 2;
      final width = (constraints.maxWidth - (columns - 1) * 10) / columns;
      return Wrap(spacing: 10, runSpacing: 10, children: [
        SizedBox(
          width: width,
          child: OutlinedButton.icon(
              key: const Key('ingredient-recipe-entry'),
              onPressed: () => context.push(AppRoutes.ingredientSearch),
              icon: const Icon(Icons.kitchen_outlined, size: 20),
              label: LocalizedText(l10n.findWithIngredients)),
        ),
        SizedBox(
          width: width,
          child: OutlinedButton.icon(
              key: const Key('saved-recipe-entry'),
              onPressed: () => context.go(AppRoutes.myRecipes),
              icon: const Icon(Icons.menu_book_outlined, size: 20),
              label: const LocalizedText('저장한 레시피')),
        ),
      ]);
    });
  }
}

class _KitchenSummaryCard extends ConsumerWidget {
  const _KitchenSummaryCard();
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return ref.watch(kitchenSummaryProvider).when(
          data: (data) {
            final lists = data['active_shopping_list_count'] ?? 0;
            final open = data['open_shopping_item_count'] ?? 0;
            final expiring = data['expiring_soon_count'] ?? 0;
            return Card(
                color: ScoutStyle.mint,
                child: InkWell(
                  borderRadius: BorderRadius.circular(22),
                  onTap: () => context.go(AppRoutes.kitchenWithTab('shopping')),
                  child: Padding(
                      padding: const EdgeInsets.all(18),
                      child: Row(children: <Widget>[
                        const Icon(Icons.shopping_basket_outlined,
                            color: ScoutStyle.forest, size: 28),
                        const SizedBox(width: 14),
                        Expanded(
                            child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: <Widget>[
                              LocalizedText(
                                  lists > 0 ? '준비하던 장보기, 이어서 해요' : '오늘의 주방',
                                  style:
                                      Theme.of(context).textTheme.titleMedium),
                              const SizedBox(height: 4),
                              LocalizedText(
                                  lists > 0
                                      ? '장보기 $lists개 · 구매할 재료 $open개'
                                      : '레시피에서 필요한 재료만 모아보세요.',
                                  style: Theme.of(context).textTheme.bodySmall),
                              if (expiring > 0)
                                LocalizedText('유통기한이 가까운 재료 $expiring개',
                                    style:
                                        Theme.of(context).textTheme.bodySmall),
                            ])),
                        const Icon(Icons.chevron_right_rounded),
                      ])),
                ));
          },
          loading: () => LinearProgressIndicator(
              semanticsLabel: context.tr('주방 요약 불러오는 중')),
          error: (_, __) => OutlinedButton.icon(
              onPressed: () => ref.invalidate(kitchenSummaryProvider),
              icon: const Icon(Icons.refresh),
              label: const LocalizedText('주방 요약 다시 불러오기')),
        );
  }
}

class _PublicRecipeSearchBar extends StatefulWidget {
  const _PublicRecipeSearchBar();
  @override
  State<_PublicRecipeSearchBar> createState() => _PublicRecipeSearchBarState();
}

class _PublicRecipeSearchBarState extends State<_PublicRecipeSearchBar> {
  final _controller = TextEditingController();
  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _submit(String value) {
    final query = value.trim();
    if (query.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: LocalizedText('검색어를 입력해 주세요.')));
      return;
    }
    context.push(AppRoutes.recommendedSearchFor(query));
  }

  @override
  Widget build(BuildContext context) => TextField(
        key: const Key('home-recipe-search'),
        controller: _controller,
        textInputAction: TextInputAction.search,
        decoration: InputDecoration(
          labelText: context.tr('무엇을 만들어 볼까요?'),
          hintText: context.tr('요리 이름이나 재료로 검색'),
          prefixIcon: const Icon(Icons.search_rounded),
          suffixIcon: IconButton(
              onPressed: () => _submit(_controller.text),
              icon: const Icon(Icons.arrow_forward_rounded),
              tooltip: context.tr('추천 검색')),
        ),
        onSubmitted: _submit,
      );
}
