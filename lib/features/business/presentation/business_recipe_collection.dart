import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../core/localization/app_localizations.dart';
import '../../auth/application/auth_providers.dart';
import '../../recipes/application/recipe_library_provider.dart';
import '../../recipes/application/recipe_providers.dart';
import '../../recipes/domain/recipe.dart';
import '../../recipes/domain/recipe_library_name.dart';
import '../../shopping/presentation/shopping_assistant_dialogs.dart'
    show ShoppingAccountGuard;
import '../../workspace/presentation/workspace_menu.dart';
import '../data/business_repository.dart';
import '../domain/business_workspace.dart';

/// Import is an explicit, permission-checked copy. Collection remains private
/// until the user reviews the selected recipe and confirms this destination.
Future<void> collectPersonalRecipe(
    BuildContext context, WidgetRef ref, BusinessContext business) async {
  final account = ref.read(activeAccountIdProvider);
  if (account == null || !business.can('recipes.write')) return;
  bool active() =>
      context.mounted && account == ref.read(activeAccountIdProvider);
  String tr(String ko, String en) => workspaceText(context, ko, en);
  try {
    final recipes = await ref.read(creatorRecipesProvider('').future);
    if (!context.mounted || !active()) return;
    final selected = await showDialog<Recipe>(
      context: context,
      builder: (ctx) => ShoppingAccountGuard(
          child: AlertDialog(
        title: Text(tr('가져올 개인 레시피 선택', 'Choose a personal recipe')),
        content: SizedBox(
            width: 480,
            height: 350,
            child: recipes.isEmpty
                ? Text(tr('먼저 레시피를 수집하고 편집 가능한 개인 레시피로 저장해 주세요.',
                    'Collect and save an editable personal recipe first.'))
                : ListView(children: [
                    for (final recipe in recipes)
                      ListTile(
                          title: Text(recipe.title),
                          onTap: () => Navigator.pop(ctx, recipe))
                  ])),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: Text(tr('취소', 'Cancel')))
        ],
      )),
    );
    if (!context.mounted || selected == null || !active()) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => ShoppingAccountGuard(
          child: AlertDialog(
        title: Text(recipeLibraryName(
            owner: business.name,
            business: true,
            english: AppLocalizations.of(ctx).isEnglish)),
        content: Text(tr(
            '「${selected.title}」의 재료·조리법·팁을 검토 자료로 가져옵니다.\n\n이 업소의 권한 있는 직원과 공유됩니다. 개인 원본과 사진은 공유되지 않습니다. 판매 메뉴 등록은 메뉴선정 권한자의 검토 후 별도로 진행합니다.',
            'Copy the ingredients, steps and tips of “${selected.title}” for review.\n\nAuthorized staff in this business can access the copy. The personal original and photos remain private. A menu approver must separately review it for a sales menu.')),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: Text(tr('취소', 'Cancel'))),
          FilledButton(
              key: const Key('confirm-business-recipe-copy'),
              onPressed: () => Navigator.pop(ctx, true),
              child: Text(tr('검토 자료로 가져오기', 'Copy for review'))),
        ],
      )),
    );
    if (!context.mounted || confirmed != true || !active()) return;
    // Recheck access after the user has selected and reviewed a recipe.
    final repository = ref.read(businessRepositoryProvider);
    final latest = await repository.context(business.id);
    if (!context.mounted || !active()) return;
    if (!latest.can('recipes.write')) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(tr('이 업소에 레시피를 저장할 권한이 없습니다.',
              'You cannot save recipes to this business.'))));
      return;
    }
    final saved = await repository.importRecipe(business.id, selected.id);
    if (!context.mounted || !active()) return;
    ref.invalidate(businessRecordsProvider);
    context.push('/business-workspaces/${business.id}/records/${saved.id}');
  } catch (_) {
    if (context.mounted && active()) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(tr('레시피를 가져오지 못했습니다. 업소 권한과 연결 상태를 확인해 주세요.',
              'Could not copy the recipe. Check business permissions and your connection.'))));
    }
  }
}

class BusinessRecipeCollectionPage extends ConsumerStatefulWidget {
  const BusinessRecipeCollectionPage({super.key, required this.business});
  final BusinessContext business;
  @override
  ConsumerState<BusinessRecipeCollectionPage> createState() =>
      _BusinessRecipeCollectionState();
}

class _BusinessRecipeCollectionState
    extends ConsumerState<BusinessRecipeCollectionPage> {
  bool _busy = false;
  @override
  Widget build(BuildContext context) {
    String tr(String ko, String en) => workspaceText(context, ko, en);
    final personal = recipeLibraryName(
        owner: ref.watch(recipeOwnerNameProvider),
        english: AppLocalizations.of(context).isEnglish);
    final shared = recipeLibraryName(
        owner: widget.business.name,
        business: true,
        english: AppLocalizations.of(context).isEnglish);
    return Scaffold(
      appBar: AppBar(title: Text(tr('레시피 수집', 'Collect recipes'))),
      body: Center(
          child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 840),
        child: ListView(padding: const EdgeInsets.all(24), children: [
          Text(shared, style: Theme.of(context).textTheme.headlineSmall),
          const SizedBox(height: 16),
          Text(
              tr('1. 검색·영상에서 레시피 수집',
                  '1. Collect recipes from search or videos'),
              style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 8),
          Text(tr('수집한 내용은 먼저 $personal에 저장하고 재료·조리법을 검토합니다.',
              'Save to $personal first, then review the ingredients and cooking steps.')),
          const SizedBox(height: 12),
          OutlinedButton.icon(
              key: const Key('business-collect-search'),
              onPressed: () => context.push('/'),
              icon: const Icon(Icons.search),
              label: Text(tr('레시피 검색·수집 열기', 'Open recipe discovery'))),
          const SizedBox(height: 28),
          Text(
              tr('2. 검토한 레시피를 업소에 가져오기',
                  '2. Copy a reviewed recipe to this business'),
              style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 8),
          Text(tr('저장 위치: $shared\n업소 직원에게 공유할 사본을 선택합니다. 판매 메뉴는 자동 등록되지 않습니다.',
              'Destination: $shared\nSelect the copy to share with staff. It will not automatically become a sales menu.')),
          const SizedBox(height: 12),
          if (widget.business.can('recipes.write'))
            FilledButton.icon(
                key: const Key('business-collect-import'),
                onPressed: _busy
                    ? null
                    : () async {
                        setState(() => _busy = true);
                        await collectPersonalRecipe(
                            context, ref, widget.business);
                        if (mounted) setState(() => _busy = false);
                      },
                icon: const Icon(Icons.copy_outlined),
                label: Text(tr('$personal에서 가져오기', 'Copy from $personal')))
          else
            Text(tr(
                '업소에 가져오려면 레시피 작성 권한과 활성 이용권이 필요합니다. 개인 레시피 수집은 계속할 수 있습니다.',
                'Copying to this business requires recipe editing access and an active plan. You can still collect personal recipes.')),
        ]),
      )),
    );
  }
}
