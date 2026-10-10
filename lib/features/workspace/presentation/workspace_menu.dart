import 'package:flutter/material.dart';
import '../../../core/localization/app_localizations.dart';
import '../domain/workspace_profile.dart';
export 'workspace_space_button.dart' show WorkspaceModeButton;

String workspaceText(BuildContext context, String ko, String en) {
  final l10n = AppLocalizations.of(context);
  return l10n.isKorean ? ko : l10n.translate(en);
}

String modeTitle(BuildContext context, WorkspaceMode mode) => switch (mode) {
      WorkspaceMode.personal => workspaceText(context, '일반 사용자', 'Home cook'),
      WorkspaceMode.professional =>
        workspaceText(context, '업소·전문가', 'Kitchen professional'),
      WorkspaceMode.supplier =>
        workspaceText(context, '식자재 공급업체', 'Food supplier'),
    };
String modeDescription(BuildContext context, WorkspaceMode mode) =>
    switch (mode) {
      WorkspaceMode.personal => workspaceText(
          context,
          '레시피를 찾고, 나만의 요리와 장보기를 준비해요.',
          'Discover recipes, save your cooking ideas and plan shopping.'),
      WorkspaceMode.professional => workspaceText(
          context,
          '업소에서는 메뉴·레시피·구매를 함께, 개인 작업실에서는 나의 연구를 관리해요.',
          'Manage shared menus, recipes and purchasing, or use your personal research studio.'),
      WorkspaceMode.supplier => workspaceText(
          context,
          '업체와 취급상품을 등록하고 회원에게 소개해요.',
          'Register your business and products for members to discover.'),
    };
IconData modeIcon(WorkspaceMode mode) => switch (mode) {
      WorkspaceMode.personal => Icons.restaurant_outlined,
      WorkspaceMode.professional => Icons.balance_outlined,
      WorkspaceMode.supplier => Icons.storefront_outlined,
    };

class WorkspaceLink {
  const WorkspaceLink(this.path, this.ko, this.en, this.icon);
  final String path, ko, en;
  final IconData icon;
  String label(BuildContext context, {String? personalName}) =>
      workspaceText(context, ko, en);
}

const workspaceHome =
    WorkspaceLink('/workspace', '홈', 'Home', Icons.home_outlined);
const workspaceSearch =
    WorkspaceLink('/', '레시피 찾기', 'Find recipes', Icons.search);
const workspaceRecipes = WorkspaceLink(
    '/my-recipes', '레시피 보관함', 'Recipe library', Icons.menu_book_outlined);
const workspaceShopping = WorkspaceLink(
    '/shopping', '장보기', 'Shopping', Icons.shopping_basket_outlined);
const workspaceRequests = WorkspaceLink(
    '/supplier-requests', '요청하기', 'Requests', Icons.receipt_long_outlined);
const workspacePurchases = WorkspaceLink(
    '/purchases', '구매', 'Purchasing', Icons.shopping_bag_outlined);
const workspaceContacts = WorkspaceLink(
    '/shopping-stores', '공급업체', 'Suppliers', Icons.handshake_outlined);
const workspaceChef = WorkspaceLink(
    '/chef', '레시피 개발', 'Recipe development', Icons.balance_outlined);
const workspaceBusiness = WorkspaceLink('/supplier-business', '업체 정보',
    'Business profile', Icons.storefront_outlined);
const workspaceProducts = WorkspaceLink('/supplier-business?section=products',
    '상품·가격', 'Products', Icons.inventory_2_outlined);
const workspaceTerms = WorkspaceLink('/supplier-business?section=terms', '거래조건',
    'Trade terms', Icons.local_shipping_outlined);
const workspaceDirectory = WorkspaceLink(
    '/supplier-directory', '공급업체 찾기', 'Find suppliers', Icons.manage_search);
const workspaceAll = WorkspaceLink(
    '/workspace-menu', '더보기', 'More', Icons.account_circle_outlined);
const workspaceLedger = WorkspaceLink('/supplier-request-ledger', '구매요청 대장',
    'Request ledger', Icons.fact_check_outlined);
const workspaceSales =
    WorkspaceLink('/chef-sales', '매출 현황', 'Sales', Icons.bar_chart_outlined);
const workspaceAccount = WorkspaceLink(
    '/account', '내 계정', 'My account', Icons.account_circle_outlined);

String dutyTitle(BuildContext context, ProfessionalDuty duty) => switch (duty) {
      ProfessionalDuty.purchasing =>
        workspaceText(context, '구매·입고', 'Purchasing'),
      ProfessionalDuty.culinary => workspaceText(context, '조리 연구', 'Cooking'),
      ProfessionalDuty.management =>
        workspaceText(context, '경영 관리', 'Management'),
    };
String dutyDescription(BuildContext context, ProfessionalDuty duty) =>
    switch (duty) {
      ProfessionalDuty.purchasing => workspaceText(
          context,
          '구매량 확인부터 업체 비교, 요청서와 입고 기록까지.',
          'Confirm quantities, compare suppliers, prepare requests and record receipt.'),
      ProfessionalDuty.culinary => workspaceText(
          context,
          '레시피를 연구하고 인분·배합·조리 버전을 관리해요.',
          'Develop recipes, scale servings and compare cooking versions.'),
      ProfessionalDuty.management => workspaceText(
          context,
          '원가와 판매가를 정하고 매출·구매 내역을 살펴봐요.',
          'Set costs and prices, then review sales and purchasing records.'),
    };
IconData dutyIcon(ProfessionalDuty duty) => switch (duty) {
      ProfessionalDuty.purchasing => Icons.shopping_bag_outlined,
      ProfessionalDuty.culinary => Icons.restaurant_menu,
      ProfessionalDuty.management => Icons.insights_outlined,
    };
const workspaceTeam = WorkspaceLink('/business-workspaces', '업소 공동 업무',
    'Business workspace', Icons.groups_outlined);
const workspaceCost =
    WorkspaceLink('/chef', '원가·판매가', 'Cost & price', Icons.balance_outlined);
const workspaceResearch = WorkspaceLink(
    '/chef', '인분·배합', 'Servings & formula', Icons.science_outlined);
const workspaceCombinedChef =
    WorkspaceLink('/chef', '조리·원가', 'Kitchen', Icons.restaurant_menu);
const workspaceMore =
    WorkspaceLink('/workspace-menu', '더보기', 'More', Icons.more_horiz);

List<WorkspaceLink> primaryWorkspaceLinks(WorkspaceMode mode,
        {WorkspaceProfile? profile, bool compact = false}) =>
    mode == WorkspaceMode.supplier
        ? [workspaceHome, workspaceProducts, workspaceTerms, workspaceMore]
        : [workspaceSearch, workspaceRecipes, workspaceShopping, workspaceMore];
List<WorkspaceLink> focusedWorkspaceLinks(WorkspaceMode mode,
        {WorkspaceProfile? profile}) =>
    switch (mode) {
      WorkspaceMode.personal => [
          workspaceSearch,
          workspaceRecipes,
          workspaceShopping,
          workspaceDirectory
        ],
      WorkspaceMode.supplier => [
          workspaceBusiness,
          workspaceProducts,
          workspaceTerms
        ],
      WorkspaceMode.professional => switch (profile?.effectiveDuty) {
          ProfessionalDuty.purchasing => [
              workspaceShopping,
              workspacePurchases,
              workspaceContacts,
              workspaceLedger
            ],
          ProfessionalDuty.culinary => [
              workspaceRecipes,
              workspaceResearch,
              workspaceSearch,
              workspaceShopping
            ],
          ProfessionalDuty.management => [
              workspaceCost,
              workspaceSales,
              workspaceLedger,
              workspacePurchases
            ],
          null => [
              workspacePurchases,
              workspaceCombinedChef,
              workspaceSales,
              workspaceRecipes
            ],
        },
    };

bool isRecipeCollectionPath(String path) =>
    ['/', '/search', '/youtube', '/ingredient-search'].contains(path) ||
    path.startsWith('/ingredient-search/') ||
    path.startsWith('/classics/') ||
    path.startsWith('/recipes/');

/// Related tools retain a meaningful section even when they are secondary tools.
String workspaceSectionPath(String path, WorkspaceMode mode,
    {WorkspaceProfile? profile}) {
  if (mode == WorkspaceMode.supplier) {
    if (path == '/workspace') return '/workspace';
    if (path == '/supplier-business') return path;
    return '/workspace-menu';
  }
  if (isRecipeCollectionPath(path) || path == '/workspace') return '/';
  if (path == '/my-recipes' ||
      path.startsWith('/my-recipes/') ||
      path.startsWith('/creator/') ||
      path == '/chef' ||
      path.startsWith('/chef/')) {
    return '/my-recipes';
  }
  if ([
    '/shopping',
    '/kitchen',
    '/purchases',
    '/supplier-requests',
    '/supplier-request-ledger',
    '/supplier-plan',
    '/shopping-assistant',
    '/shopping-review',
    '/shopping-preparation',
    '/shopping-stores',
    '/supplier-directory'
  ].contains(path)) {
    return '/shopping';
  }
  return '/workspace-menu';
}

int workspaceDestinationIndex(Uri location, WorkspaceMode mode,
    {WorkspaceProfile? profile, bool compact = false}) {
  final links = primaryWorkspaceLinks(mode, profile: profile, compact: compact);
  if (mode == WorkspaceMode.supplier && location.path == '/supplier-business') {
    return location.queryParameters['section'] == 'terms' ? 2 : 1;
  }
  final section = workspaceSectionPath(location.path, mode, profile: profile);
  final index =
      links.indexWhere((link) => Uri.parse(link.path).path == section);
  if (index < 0 && compact && mode == WorkspaceMode.professional) {
    return links.indexWhere((link) => link.path == '/workspace-menu');
  }
  return index;
}

String workspaceStartPath(WorkspaceMode mode) =>
    mode == WorkspaceMode.personal ? '/' : '/workspace';

String guideForMode(WorkspaceMode mode) => '/guide?audience=${switch (mode) {
      WorkspaceMode.personal => 'home',
      WorkspaceMode.professional => 'professional',
      WorkspaceMode.supplier => 'supplier'
    }}';
