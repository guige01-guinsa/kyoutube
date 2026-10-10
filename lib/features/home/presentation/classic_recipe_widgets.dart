import '../../../core/localization/localized_text.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../core/localization/app_localizations.dart';
import '../../../core/router/app_router.dart';
import '../../../core/theme/app_theme.dart';
import '../../auth/application/auth_providers.dart';
import '../../recipes/domain/recipe.dart';
import '../../recipes/presentation/youtube_recipe_enrichment_page.dart';
import '../domain/korean_classics.dart';

String homeText(BuildContext context, HomeText text) =>
    AppLocalizations.of(context).bilingual(text.ko, text.en);
ClassicVideo classicVideo(BuildContext context, KoreanClassic recipe) =>
    recipe.videoFor(AppLocalizations.of(context).isEnglish ? 'en' : 'ko');

String homeLabel(BuildContext context, String key) =>
    homeText(context, homeCopy[key]!);

final classicImageProvider =
    Provider.family<ImageProvider, String>((_, url) => NetworkImage(url));

class ClassicImage extends ConsumerWidget {
  const ClassicImage(
      {super.key, required this.recipe, this.aspectRatio = 16 / 9});
  final KoreanClassic recipe;
  final double aspectRatio;

  @override
  Widget build(BuildContext context, WidgetRef ref) => AspectRatio(
        aspectRatio: aspectRatio,
        child: Image(
          image: ref.watch(
              classicImageProvider(classicVideo(context, recipe).thumbnailUrl)),
          fit: BoxFit.cover,
          excludeFromSemantics: true,
          errorBuilder: (_, __, ___) => const ColoredBox(
            color: ScoutStyle.mint,
            child: Center(
                child: Icon(Icons.restaurant_menu,
                    size: 32, color: ScoutStyle.forest)),
          ),
          loadingBuilder: (_, child, progress) => progress == null
              ? child
              : const ColoredBox(
                  color: ScoutStyle.mint,
                  child: Center(
                      child: Icon(Icons.restaurant_menu,
                          color: ScoutStyle.forest, size: 32)),
                ),
        ),
      );
}

class ClassicRecipeCard extends StatelessWidget {
  const ClassicRecipeCard(
      {super.key,
      required this.recipe,
      required this.index,
      this.featured = false});
  final KoreanClassic recipe;
  final int index;
  final bool featured;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context).textTheme;
    final title = homeText(context, recipe.name);
    void open() => context.push(AppRoutes.classicDetail(recipe.id));
    final details =
        Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      LocalizedText(
          '${index.toString().padLeft(2, '0')} / ${homeText(context, classicCategories[recipe.category]!)}',
          style: theme.labelSmall
              ?.copyWith(color: ScoutStyle.forest, letterSpacing: 1.1)),
      const SizedBox(height: 6),
      Text(title,
          style: (featured ? theme.headlineSmall : theme.titleLarge)
              ?.copyWith(fontWeight: FontWeight.w700)),
      const SizedBox(height: 6),
      Text(homeText(context, recipe.focus), style: theme.bodySmall),
      const SizedBox(height: 12),
      LocalizedText(
          '${homeLabel(context, 'videoLanguage')} · ${classicVideo(context, recipe).creator}',
          style: theme.labelMedium?.copyWith(color: ScoutStyle.muted)),
    ]);
    return Card(
      key: ValueKey('classic-card-${recipe.id}'),
      margin: EdgeInsets.zero,
      clipBehavior: Clip.antiAlias,
      child: InkWell(
          onTap: open,
          child: LayoutBuilder(builder: (_, constraints) {
            final largeText = MediaQuery.textScalerOf(context).scale(1) > 1.3;
            final wideFeature =
                featured && constraints.maxWidth >= 680 && !largeText;
            final image = Stack(alignment: Alignment.bottomRight, children: [
              ClassicImage(recipe: recipe),
              Padding(
                  padding: const EdgeInsets.all(16),
                  child: IconButton.filled(
                    key: ValueKey('classic-play-${recipe.id}'),
                    tooltip: homeLabel(context, 'watch'),
                    style: IconButton.styleFrom(
                        backgroundColor: ScoutStyle.ink,
                        foregroundColor: Colors.white,
                        minimumSize: const Size(48, 48)),
                    onPressed: () => openClassicSource(
                        context, classicVideo(context, recipe).videoUrl),
                    icon: const Icon(Icons.play_arrow_rounded, size: 26),
                  )),
            ]);
            if (wideFeature) {
              return Padding(
                padding: const EdgeInsets.all(20),
                child: Row(children: [
                  Expanded(
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(12),
                      child: image,
                    ),
                  ),
                  const SizedBox(width: 24),
                  Expanded(child: details),
                ]),
              );
            }
            final stacked = featured || constraints.maxWidth < 500 || largeText;
            if (!stacked) {
              return Padding(
                  padding: const EdgeInsets.all(14),
                  child: Row(children: [
                    SizedBox(
                        width: 120,
                        child: ClipRRect(
                            borderRadius: BorderRadius.circular(10),
                            child: ClassicImage(recipe: recipe))),
                    const SizedBox(width: 16),
                    Expanded(child: details),
                    const SizedBox(width: 8),
                    const Icon(Icons.arrow_outward,
                        size: 18, color: ScoutStyle.forest),
                  ]));
            }
            return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  image,
                  Padding(padding: const EdgeInsets.all(20), child: details),
                  if (featured)
                    Padding(
                        padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
                        child: FilledButton.icon(
                            onPressed: () => openClassicSource(context,
                                classicVideo(context, recipe).videoUrl),
                            icon: const Icon(Icons.play_arrow_rounded),
                            label: Text(homeLabel(context, 'watch')))),
                ]);
          })),
    );
  }
}

/// Kept injectable so guest playback and launch failures can be tested without
/// opening an external app. URLs only come from the curated catalog.
final classicUrlLauncherProvider = Provider<Future<bool> Function(Uri)>(
    (ref) => (uri) => launchUrl(uri, mode: LaunchMode.externalApplication));

Future<void> openClassicSource(BuildContext context, String url) async {
  final launch = ProviderScope.containerOf(context, listen: false)
      .read(classicUrlLauncherProvider);
  try {
    if (await launch(Uri.parse(url))) return;
  } catch (_) {
    // Present the same recoverable state for missing apps and platform errors.
  }
  if (!context.mounted) return;
  ScaffoldMessenger.of(context)
      .showSnackBar(SnackBar(content: Text(homeLabel(context, 'unavailable'))));
}

class ClassicRecipePage extends ConsumerWidget {
  const ClassicRecipePage({super.key, required this.recipe});
  final KoreanClassic recipe;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final signedIn = ref.watch(authUserProvider).valueOrNull != null;
    return Scaffold(
      appBar: AppBar(title: Text(homeText(context, recipe.name))),
      body: Align(
          alignment: Alignment.topCenter,
          child: ConstrainedBox(
            constraints:
                const BoxConstraints(maxWidth: ScoutStyle.contentWidth),
            child: ListView(padding: const EdgeInsets.all(20), children: [
              ClipRRect(
                  borderRadius: BorderRadius.circular(18),
                  child: ClassicImage(recipe: recipe)),
              const SizedBox(height: 24),
              Text(homeText(context, recipe.name),
                  style: Theme.of(context).textTheme.headlineMedium),
              const SizedBox(height: 8),
              LocalizedText(
                  '${homeLabel(context, 'videoLanguage')} · ${classicVideo(context, recipe).creator}',
                  style: Theme.of(context).textTheme.labelLarge),
              const SizedBox(height: 24),
              Text(homeLabel(context, 'focus'),
                  style: Theme.of(context)
                      .textTheme
                      .labelLarge
                      ?.copyWith(color: ScoutStyle.forest)),
              const SizedBox(height: 8),
              Text(homeText(context, recipe.focus),
                  style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: 24),
              FilledButton.icon(
                  key: const Key('classic-watch'),
                  onPressed: () => openClassicSource(
                      context, classicVideo(context, recipe).videoUrl),
                  icon: const Icon(Icons.play_arrow_rounded),
                  label: Text(homeLabel(context, 'watch'))),
              const SizedBox(height: 8),
              if (classicVideo(context, recipe).recipeUrl != null)
                OutlinedButton.icon(
                    onPressed: () => openClassicSource(
                        context, classicVideo(context, recipe).recipeUrl!),
                    icon: const Icon(Icons.open_in_new, size: 18),
                    label: Text(homeLabel(context, 'source'))),
              const SizedBox(height: 24),
              const Divider(),
              const SizedBox(height: 16),
              Text(homeLabel(context, 'draftNote'),
                  style: Theme.of(context).textTheme.bodyMedium),
              const SizedBox(height: 16),
              OutlinedButton.icon(
                  key: const Key('classic-draft'),
                  onPressed: () async {
                    if (!signedIn) {
                      await context.push(AppRoutes.login);
                      // Creating a draft remains an explicit authenticated action.
                      return;
                    }
                    final result = await context
                        .push<String>(AppRoutes.classicDraft(recipe.id));
                    if (context.mounted &&
                        result != null &&
                        result.isNotEmpty) {
                      context.push(AppRoutes.creatorDetail(result));
                    }
                  },
                  icon: Icon(signedIn ? Icons.edit_note : Icons.lock_outline),
                  label: Text(
                      homeLabel(context, signedIn ? 'draft' : 'signInDraft'))),
              const SizedBox(height: 24),
              Text(homeLabel(context, 'curation'),
                  style: Theme.of(context).textTheme.bodySmall),
            ]),
          )),
    );
  }
}

/// A direct/deep link must not start an AI request for an unauthenticated user.
Recipe classicDraftRecipe(KoreanClassic recipe, String languageCode) {
  final video = recipe.videoFor(languageCode);
  return Recipe(
    id: '',
    title: languageCode != 'ko' ? recipe.name.en : recipe.name.ko,
    ingredients: const [],
    steps: const [],
    youtubeUrl: video.videoUrl,
    imageUrl: video.thumbnailUrl,
    sourceType: 'youtube_import',
  );
}

class ClassicDraftPage extends ConsumerWidget {
  const ClassicDraftPage({super.key, required this.recipe});
  final KoreanClassic recipe;
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (ref.watch(authUserProvider).valueOrNull == null) {
      return ClassicRecipePage(recipe: recipe);
    }
    return YoutubeRecipeEnrichmentPage(
        recipe: classicDraftRecipe(
            recipe, AppLocalizations.of(context).isEnglish ? 'en' : 'ko'));
  }
}
