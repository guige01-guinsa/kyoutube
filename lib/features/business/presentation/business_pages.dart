import '../../../core/format/user_number.dart';
import '../../../core/auth/auth_return.dart';
import '../../../core/localization/localized_text.dart';
import '../../shopping/presentation/purchase_cleanup_menu.dart';
import '../../shopping/presentation/record_management.dart';
import '../../shopping/data/purchase_cleanup_repository.dart';
import '../../../core/search/product_search.dart';
import '../../shopping/presentation/purchase_name_field.dart';
import 'package:intl/intl.dart';
import 'package:flutter/material.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/scout_page.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../auth/application/auth_providers.dart';
import '../../shopping/domain/supplier_request.dart';
import '../../shopping/application/supplier_request_pdf.dart';
import '../../shopping/application/request_document_service.dart';
import '../../shopping/presentation/request_document_preview.dart';
import '../../shopping/presentation/supplier_request_document.dart';
import '../../shopping/presentation/shopping_assistant_dialogs.dart'
    show ShoppingAccountGuard;
import '../../chef/domain/chef_sales.dart';
import '../../workspace/presentation/workspace_menu.dart';
import '../../workspace/application/workspace_navigation.dart';
import '../data/business_repository.dart';
import '../data/business_menu_repository.dart';
import '../domain/business_menu.dart';
import '../../shopping/data/supplier_request_repository.dart';
import '../domain/business_workspace.dart';
import '../domain/business_navigation.dart';
import 'business_work_overview.dart';
import 'business_coupang_page.dart';
import 'business_record_list.dart';
import 'business_recipe_collection.dart';
import '../../recipes/domain/recipe_library_name.dart';
import '../../recipes/application/recipe_library_provider.dart';
import '../../../core/localization/app_localizations.dart';
import '../data/business_supplier_repository.dart';
import '../domain/business_supplier.dart';
import '../data/business_inventory_repository.dart';
import '../domain/business_inventory.dart';
import '../data/business_menu_fast_repository.dart';
import '../data/business_meal_repository.dart';
import '../domain/business_meal.dart';
import '../domain/business_purchase_review.dart';
import '../../shopping/domain/shopping_preparation.dart';
import '../../shopping/domain/shopping_assistant.dart';
import '../../shopping/domain/coupang_purchase_plan.dart';
import '../../shopping/presentation/coupang_purchase_planner.dart';
import '../../shopping/presentation/coupang_disclosure.dart';
import '../../shopping/domain/shopping_navigation.dart';
import '../../shopping/presentation/shopping_stage_tabs.dart';
part 'business_purchasing_page.dart';
part 'business_purchase_ingredients.dart';
part 'business_meal_pages.dart';
part 'business_design_sections.dart';
part 'business_menu_fast_page.dart';
part 'business_plan_management.dart';
part 'business_inventory_pages.dart';
part 'business_owner_management.dart';
part 'business_stock_form.dart';
part 'business_stock_hints.dart';
part 'business_supplier_pages.dart';
part 'business_supplier_choice.dart';
part 'business_members_page.dart';
part 'business_member_profile_editor.dart';
part 'business_record_editor.dart';
part 'business_record_page.dart';
part 'business_test_pages.dart';
part 'business_menu_pages.dart';
part 'business_menu_purchase_page.dart';
part 'business_ingredient_editor.dart';

String bt(BuildContext context, String ko, String en) =>
    workspaceText(context, ko, en);
String _businessDate(BuildContext context, Object? value) {
  final date = DateTime.tryParse(value?.toString() ?? '')?.toLocal();
  return date == null ? '' : DateFormat('yyyy-MM-dd HH:mm').format(date);
}

String businessKindLabel(BuildContext context, String kind) => switch (kind) {
      'recipe' => bt(context, '공동 레시피', 'Team recipes'),
      'meal' => bt(context, '식단 계획', 'Meal plans'),
      'purchase' => bt(context, '구매·입고', 'Purchasing'),
      'cost' => bt(context, '원가·판매가', 'Cost & price'),
      'sale' => bt(context, '판매 기록', 'Sales records'),
      _ => kind
    };
String businessStatusLabel(BuildContext context, String status) =>
    switch (status) {
      'draft' => bt(context, '작성 중', 'Draft'),
      'review' => bt(context, '승인 대기', 'Awaiting approval'),
      'approved' => bt(context, '승인 완료', 'Approved'),
      'sent' => bt(context, '전달 확인', 'Sharing confirmed'),
      'received' => bt(context, '입고 확인', 'Receipt confirmed'),
      'cancelled' => bt(context, '취소', 'Cancelled'),
      _ => status
    };
String businessError(BuildContext context, Object error) {
  final code = error is PostgrestException ? error.message : error.toString();
  if (code.contains('BUSINESS_COUPANG_CHANGED')) {
    return bt(context, '쿠팡 상품이나 판매 규격이 변경되었습니다. 목록에서 상품·수량을 다시 확인해 주세요.',
        'The Coupang product or sale option changed. Review the product and quantity again.');
  }
  if (error is PostgrestException &&
      ['PGRST202', 'PGRST205', '42P01', '42883'].contains(error.code)) {
    return bt(
        context,
        '업소 공동 업무를 사용하려면 서버 업데이트가 필요합니다. 기존 개인 업무는 계속 사용할 수 있습니다.',
        'The server needs an update for shared business work. Personal tools are still available.');
  }
  if (code.contains('MEAL_SLOT_EXISTS')) {
    return bt(context, '같은 날짜·끼니의 식단이 있습니다. 기존 식단을 수정하거나 다른 끼니를 선택하세요.',
        'A plan already exists for this date and meal. Edit it or choose another meal.');
  }
  if (code.contains('MEAL_PURCHASE_LINKED')) {
    return bt(context, '이미 구매 준비한 식단입니다. 연결된 구매요청서와 재고 예약을 확인하세요.',
        'This meal already has purchase preparation. Review its requests and stock reservations.');
  }
  if (code.contains('MEAL_NOT_CONFIRMED')) {
    return bt(context, '확정된 식단만 구매 준비할 수 있습니다.',
        'Only confirmed meals can be prepared for purchasing.');
  }
  if (code.contains('MEAL_EMPTY')) {
    return bt(context, '복사할 식단이 없습니다.', 'There are no meals to copy.');
  }
  if (code.contains('FAST_CHANGED')) {
    return bt(context, '메뉴·구매 기준·재고 또는 진행 중 요청이 바뀌었습니다. 다시 계산하고 확인하세요.',
        'Menus, defaults, inventory or open requests changed. Recalculate and review.');
  }
  if (code.contains('FAST_MAPPING_REQUIRED')) {
    return bt(context, '각 재료의 구매 기준을 설정하거나 변경된 상품을 다시 확인하세요.',
        'Set purchasing defaults or reconfirm changed products.');
  }
  if (code.contains('INVENTORY_')) {
    if (code.contains('INVENTORY_STOCK')) {
      return bt(context, '사용 가능 재고가 부족합니다. 최신 입고·예약량을 확인하세요.',
          'Available stock is insufficient. Review current receipts and reservations.');
    }
    if (code.contains('INVENTORY_CONVERSION')) {
      return bt(context, '재고 품목·단위 환산을 확인하세요. 첫 입고 이후에는 같은 품목과 환산량을 사용합니다.',
          'Check the stock item and unit conversion. Later receipts must use the same item and conversion as the first receipt.');
    }
    if (code.contains('INVENTORY_OVER_RECEIPT')) {
      return bt(context, '미입고 수량보다 많이 입력했습니다. 최신 입고·반품을 확인하세요.',
          'This exceeds the outstanding quantity. Review current receipts and returns.');
    }
    if (code.contains('INVENTORY_RETURN')) {
      return bt(context, '이 입고 기록에서 반품할 수 있는 수량을 초과했습니다.',
          'This exceeds the quantity still returnable from this receipt.');
    }
    if (code.contains('INVENTORY_REASON')) {
      return bt(context, '용도·사유를 1~500자로 입력하세요.',
          'Enter a purpose or reason using 1–500 characters.');
    }
    if (code.contains('INVENTORY_SHORTAGE')) {
      return bt(context, '미입고 잔량을 확인하고 마감 여부를 선택하세요.',
          'Review and accept outstanding quantities before closing.');
    }
    if (code.contains('INVENTORY_RESERVATION')) {
      return bt(context, '남은 예약량을 확인하고 다시 입력하세요.',
          'Check the remaining reservation and enter the quantity again.');
    }
    return bt(context, '요청 상태가 변경됐습니다. 품목별 입고 화면에서 최신 상태를 확인하세요.',
        'The request state changed. Review the latest item receipts.');
  }
  if (code.contains('SUPPLIER_')) {
    return bt(
        context,
        '거래처·상품이 변경되었거나 재료 단위와 맞지 않습니다. 사용 상태·내용량·포장 단위를 확인하고 다시 선택해 주세요.',
        'The supplier or product changed, or its unit does not match. Check availability, content quantity and pack unit, then select it again.');
  }
  if (code.contains('MENU_')) {
    return bt(
        context,
        switch (code.split(':').last.trim()) {
          'MENU_STRUCTURED_REQUIRED' => '레시피에 수량·단위가 있는 구매 기준 재료를 먼저 등록해 주세요.',
          'MENU_APPROVAL_REQUIRED' => '시험 조리를 마친 레시피 버전의 출시 승인이 필요합니다.',
          'MENU_STOCK_CONFIRM' => '사용 가능 재고·입고 예정량·포장 규격을 확인해 주세요.',
          'MENU_NOTHING_TO_BUY' => '현재 계산으로는 구매할 재료가 없습니다.',
          'MENU_ON_SALE' => '이 레시피를 사용하는 메뉴의 판매를 먼저 중지해 주세요.',
          _ => '메뉴 상태나 참조 버전이 변경됐습니다. 최신 자료를 확인해 주세요.'
        },
        switch (code.split(':').last.trim()) {
          'MENU_STRUCTURED_REQUIRED' =>
            'First register recipe ingredients with quantities and units.',
          'MENU_APPROVAL_REQUIRED' =>
            'This tested recipe revision needs launch approval.',
          'MENU_STOCK_CONFIRM' =>
            'Confirm available stock, incoming quantities and pack sizes.',
          'MENU_NOTHING_TO_BUY' =>
            'No ingredients need purchasing with these quantities.',
          'MENU_ON_SALE' =>
            'Stop the menus using this recipe before archiving it.',
          _ =>
            'The menu state or source revision changed. Reload the latest records.'
        });
  }
  if (code.contains('ADMIN_MFA_REQUIRED')) {
    return bt(context, '관리자 2단계 인증을 완료한 뒤 다시 열어 주세요.',
        'Complete administrator two-step authentication and reopen this page.');
  }
  if (code.contains('ADMIN_REQUIRED')) {
    return bt(context, '관리자 계정만 테스트를 관리할 수 있습니다.',
        'Only administrators can manage tests.');
  }
  if (code.contains('BUSINESS_TEST_ACCOUNT') ||
      code.contains('BUSINESS_TEST_PARTICIPANT')) {
    return bt(context, '이메일 인증을 마친 테스트 참여 계정이 필요합니다. 관리자에게 테스터 등록을 확인해 주세요.',
        'A verified test participant account is required. Ask the administrator to check tester access.');
  }
  if (code.contains('BUSINESS_TEST_ACTIVE')) {
    return bt(context, '진행 중인 테스트를 먼저 종료해 주세요.',
        'End the current test before creating another.');
  }
  if (code.contains('BUSINESS_TEST_INVALID')) {
    return bt(context, '이름과 테스트 기간(1~90일)을 확인해 주세요.',
        'Check the name and test duration (1–90 days).');
  }
  if (code.contains('BUSINESS_TEST_')) {
    return bt(context, '테스트가 종료되었거나 참여 권한이 없습니다. 테스트 목록을 새로 열어 확인해 주세요.',
        'This test ended or access is unavailable. Refresh the test list.');
  }
  if (code.contains('BUSINESS_PROFILE_INVALID')) {
    return bt(context, '이름·직책·업무 연락처의 길이와 입력 내용을 확인해 주세요.',
        'Check the name, job title and work contact fields.');
  }
  if (code.contains('BUSINESS_STALE')) {
    return bt(context, '다른 담당자가 수정했습니다. 최신 자료를 다시 열어 변경 내용을 확인해 주세요.',
        'Another person changed this record. Reopen the latest version before editing.');
  }
  if (code.contains('BUSINESS_PLAN')) {
    return bt(context, '업소 책임자의 활성 비즈니스 이용권이 필요합니다.',
        'The business owner needs an active Business membership.');
  }
  if (code.contains('BUSINESS_INVITE_INVALID')) {
    return bt(
        context,
        '초대 코드가 만료되었거나 이메일이 다릅니다. 초대받은 이메일로 로그인하고 이메일 인증을 완료해 주세요.',
        'This invitation expired or belongs to another email. Sign in with the invited address and verify your email.');
  }
  if (code.contains('BUSINESS_PURCHASE_INCOMPLETE')) {
    return bt(context, '업체·요청 업소·품목별 구매 수량과 단위를 입력해 주세요.',
        'Enter supplier, buyer and each item’s purchase quantity and unit.');
  }
  if (code.contains('BUSINESS_LIMIT')) {
    return bt(context, '이 업소의 생성 한도에 도달했습니다. 기존 자료나 초대를 확인해 주세요.',
        'The workspace limit was reached. Review existing records or invitations.');
  }
  if (code.contains('BUSINESS_DENIED') || code.contains('BUSINESS_AUTH')) {
    return bt(context, '현재 계정의 접근 권한이 없습니다. 사장에게 권한을 확인해 주세요.',
        'This account has no access. Check your permissions with the owner.');
  }
  return bt(context, '처리하지 못했습니다. 입력 내용과 연결 상태를 확인한 뒤 다시 시도해 주세요.',
      'Could not complete this action. Check the fields and connection, then retry.');
}

Future<bool> businessConfirm(BuildContext context, String message) async =>
    await showDialog<bool>(
        context: context,
        builder: (ctx) => ShoppingAccountGuard(
                child: AlertDialog(
                    scrollable: true,
                    title: Text(bt(ctx, '확인해 주세요', 'Please confirm')),
                    content: Text(message),
                    actions: [
                  TextButton(
                      onPressed: () => Navigator.pop(ctx, false),
                      child: Text(bt(ctx, '취소', 'Cancel'))),
                  FilledButton(
                      onPressed: () => Navigator.pop(ctx, true),
                      child: Text(bt(ctx, '확인', 'Confirm')))
                ]))) ==
    true;

class _BusinessError extends StatelessWidget {
  const _BusinessError(this.error, this.retry);
  final Object error;
  final VoidCallback retry;
  @override
  Widget build(BuildContext context) => Padding(
      padding: const EdgeInsets.all(20),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        Text(businessError(context, error)),
        const SizedBox(height: 12),
        TextButton(onPressed: retry, child: Text(bt(context, '다시 시도', 'Retry')))
      ]));
}

class BusinessWorkspacesPage extends ConsumerStatefulWidget {
  const BusinessWorkspacesPage({super.key});
  @override
  ConsumerState<BusinessWorkspacesPage> createState() =>
      _BusinessWorkspacesPageState();
}

class _BusinessWorkspacesPageState
    extends ConsumerState<BusinessWorkspacesPage> {
  Future<void> _entry(bool create) async {
    final owner = ref.read(activeAccountIdProvider);
    if (owner == null) {
      context.push(loginFor(GoRouterState.of(context).uri.toString(), resume: true));
      return;
    }
    final first = TextEditingController(), display = TextEditingController();
    bool busy = false;
    String? error;
    await showDialog<void>(
        context: context,
        barrierDismissible: false,
        builder: (ctx) => ShoppingAccountGuard(
            child: StatefulBuilder(
                builder: (ctx, update) => PopScope(
                    canPop: !busy,
                    child: AlertDialog(
                        title: Text(create
                            ? bt(
                                ctx, '업소 작업공간 만들기', 'Create business workspace')
                            : bt(ctx, '직원 초대 수락', 'Accept staff invitation')),
                        scrollable: true,
                        content: SizedBox(
                            width: 440,
                            child: Column(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Text(create
                                      ? bt(
                                          ctx,
                                          '개인 자료는 자동 공유되지 않습니다. 업소당 직원은 최대 30명이며 비즈니스 이용권이 필요합니다.',
                                          'Personal records are not shared automatically. Each workspace supports up to 30 members and requires a Business membership.')
                                      : bt(ctx, '초대받은 이메일로 로그인한 뒤 코드를 입력하세요.',
                                          'Sign in with your invited email, then enter the code.')),
                                  const SizedBox(height: 16),
                                  TextField(
                                      controller: first,
                                      enabled: !busy,
                                      maxLength: create ? 120 : 64,
                                      decoration: InputDecoration(
                                          labelText: create
                                              ? bt(
                                                  ctx, '업소 이름', 'Business name')
                                              : bt(ctx, '초대 코드',
                                                  'Invitation code'))),
                                  TextField(
                                      controller: display,
                                      enabled: !busy,
                                      maxLength: 120,
                                      decoration: InputDecoration(
                                          labelText: bt(ctx, '직원에게 보일 이름',
                                              'Your display name'))),
                                  if (error != null)
                                    Text(error!,
                                        style: TextStyle(
                                            color: Theme.of(ctx)
                                                .colorScheme
                                                .error))
                                ])),
                        actions: [
                          TextButton(
                              onPressed: busy ? null : () => Navigator.pop(ctx),
                              child: Text(bt(ctx, '취소', 'Cancel'))),
                          FilledButton(
                              onPressed: busy
                                  ? null
                                  : () async {
                                      if (first.text.trim().isEmpty ||
                                          display.text.trim().isEmpty) {
                                        return;
                                      }
                                      update(() => busy = true);
                                      try {
                                        final repo = ref
                                            .read(businessRepositoryProvider);
                                        final id = create
                                            ? await repo.create(
                                                first.text.trim(),
                                                display.text.trim())
                                            : await repo.accept(
                                                first.text.trim(),
                                                display.text.trim());
                                        if (!mounted ||
                                            owner !=
                                                ref.read(
                                                    activeAccountIdProvider) ||
                                            !ctx.mounted) {
                                          return;
                                        }
                                        ref.invalidate(
                                            businessWorkspacesProvider);
                                        Navigator.pop(ctx);
                                        context
                                            .push('/business-workspaces/$id');
                                      } catch (e) {
                                        if (ctx.mounted &&
                                            mounted &&
                                            owner ==
                                                ref.read(
                                                    activeAccountIdProvider)) {
                                          update(() =>
                                              error = businessError(ctx, e));
                                        }
                                      } finally {
                                        if (ctx.mounted) {
                                          update(() => busy = false);
                                        }
                                      }
                                    },
                              child: Text(bt(ctx, '계속', 'Continue')))
                        ])))));
    // Dialog routes finish their reverse transition before controllers are released.
    await Future<void>.delayed(const Duration(milliseconds: 250));
    first.dispose();
    display.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final account = ref.watch(activeAccountIdProvider);
    return Scaffold(
        appBar:
            AppBar(title: Text(bt(context, '업소 공동 업무', 'Business workspace'))),
        body: Center(
            child: ConstrainedBox(
                constraints:
                    const BoxConstraints(maxWidth: ScoutStyle.formWidth),
                child: ListView(padding: const EdgeInsets.all(20), children: [
                  Text(
                      bt(context, '각자 로그인하고, 같은 업소에서 함께 일하세요.',
                          'Your own accounts. One shared business.'),
                      style: Theme.of(context).textTheme.headlineSmall),
                  const SizedBox(height: 12),
                  Text(bt(
                      context,
                      '사장이 업소를 만들고 직원을 초대하면 함께 사용할 수 있습니다. 업소 책임자의 비즈니스 이용권으로 공동 업무를 이용하며, 직원은 초대받은 권한으로 참여합니다. 개인 자료와 공동 자료는 별도로 보관됩니다.',
                      'The owner creates a business and invites staff. Shared work uses the owner’s Business membership; staff join with assigned permissions. Personal and shared records are kept separately.')),
                  const SizedBox(height: 20),
                  Wrap(spacing: 12, runSpacing: 8, children: [
                    FilledButton.icon(
                        onPressed: () => _entry(true),
                        icon: const Icon(Icons.add_business_outlined),
                        label: Text(bt(context, '업소 만들기', 'Create workspace'))),
                    OutlinedButton.icon(
                        onPressed: () => _entry(false),
                        icon: const Icon(Icons.person_add_alt),
                        label:
                            Text(bt(context, '초대 코드로 참여', 'Join with a code')))
                  ]),
                  const SizedBox(height: 16),
                  OutlinedButton.icon(
                      onPressed: () => context.push('/business-samples'),
                      icon: const Icon(Icons.science_outlined),
                      label: Text(bt(context, '샘플 20개로 업무 테스트',
                          'Practice with 20 samples'))),
                  const SizedBox(height: 24),
                  if (account == null)
                    TextButton(
                        onPressed: () => context.push(loginFor(GoRouterState.of(context).uri.toString(), resume: true)),
                        child: Text(bt(context, '로그인하기', 'Sign in')))
                  else
                    ref.watch(businessWorkspacesProvider).when(
                        data: (rows) => Column(children: [
                              for (final row in rows)
                                Card(
                                    child: ListTile(
                                        title: Text(row['name'] as String),
                                        subtitle: Text(row['owner_id'] ==
                                                account
                                            ? bt(context, '사장 · 직원 및 권한 관리',
                                                'Owner · staff and permissions')
                                            : bt(context, '직원 · 부여받은 업무',
                                                'Staff · assigned responsibilities')),
                                        trailing:
                                            const Icon(Icons.chevron_right),
                                        onTap: () => context.push(
                                            '/business-workspaces/${row['id']}'))),
                              if (rows.isEmpty)
                                Text(bt(context, '아직 참여한 업소가 없습니다.',
                                    'You have not joined a business yet.'))
                            ]),
                        loading: () => const LinearProgressIndicator(),
                        error: (e, _) => _BusinessError(e,
                            () => ref.invalidate(businessWorkspacesProvider)))
                ]))));
  }
}

class BusinessWorkspacePage extends ConsumerStatefulWidget {
  const BusinessWorkspacePage(
      {super.key,
      required this.workspace,
      this.section = BusinessSection.home,
      this.initialStatus = 'all'});
  final String workspace;
  final BusinessSection section;
  final String initialStatus;
  @override
  ConsumerState<BusinessWorkspacePage> createState() =>
      _BusinessWorkspacePageState();
}

class _BusinessWorkspacePageState extends ConsumerState<BusinessWorkspacePage> {
  String? _kind;
  int _offset = 0;
  String _search = '';
  late String _status = [
    'draft',
    'review',
    'approved',
    'sent',
    'received',
    'cancelled'
  ].contains(widget.initialStatus)
      ? widget.initialStatus
      : 'all';
  @override
  Widget build(BuildContext context) {
    final info = ref.watch(businessContextProvider(widget.workspace));
    return info.when(
        data: (business) {
          if (widget.section == BusinessSection.purchasing) {
            return _BusinessPurchasingPage(
                key: ValueKey(
                    '${ref.watch(activeAccountIdProvider)}:${business.id}'),
                business: business,
                initialStatus: _status);
          }
          if (widget.section == BusinessSection.collection) {
            return BusinessRecipeCollectionPage(
                key: ValueKey(business.id), business: business);
          }
          if (widget.section == BusinessSection.home ||
              widget.section == BusinessSection.settings) {
            return BusinessWorkOverview(
                business: business,
                settings: widget.section == BusinessSection.settings);
          }
          final kinds = businessSectionKinds(widget.section)
              .where((k) => business.can(businessPermission(k)))
              .toList();
          final suggested = business.can('purchasing.write') &&
                  !business.can('recipes.write')
              ? 'purchase'
              : business.can('finance.write') && !business.can('recipes.write')
                  ? 'cost'
                  : 'recipe';
          final kind = kinds.contains(_kind)
              ? _kind
              : (kinds.contains(suggested) ? suggested : kinds.firstOrNull);
          final query = (
            workspace: widget.workspace,
            kind: kind ?? 'recipe',
            offset: _offset
          );
          return Scaffold(
              appBar: AppBar(
                  title: Text(widget.section == BusinessSection.recipes
                      ? recipeLibraryName(
                          owner: business.name,
                          business: true,
                          english: AppLocalizations.of(context).isEnglish)
                      : business.name),
                  actions: [
                    IconButton(
                        tooltip: bt(context, '새로고침', 'Refresh'),
                        onPressed: () {
                          ref.invalidate(
                              businessContextProvider(widget.workspace));
                          ref.invalidate(businessRecordsProvider);
                        },
                        icon: const Icon(Icons.refresh)),
                    if (business.owner)
                      IconButton(
                          tooltip:
                              bt(context, '직원·권한 관리', 'Staff & permissions'),
                          onPressed: () => context.push(
                              '/business-workspaces/${widget.workspace}/members'),
                          icon: const Icon(Icons.manage_accounts_outlined))
                  ]),
              body: Center(
                  child: ConstrainedBox(
                      constraints: const BoxConstraints(
                          maxWidth: ScoutStyle.workspaceWidth),
                      child: ListView(
                          padding: const EdgeInsets.all(20),
                          children: [
                            if (business.isTest) const BusinessPracticeNotice(),
                            Text(
                                bt(context, '업소 공동 자료',
                                    'Shared business records'),
                                style:
                                    Theme.of(context).textTheme.headlineSmall),
                            const SizedBox(height: 8),
                            BusinessWorkflowStrip(business: business),
                            const SizedBox(height: 12),
                            ExpansionTile(
                                key: const Key('business-related-tools'),
                                tilePadding: EdgeInsets.zero,
                                title: Text(bt(context, '연결된 업무 도구',
                                    'Related work tools')),
                                childrenPadding:
                                    const EdgeInsets.only(bottom: 16),
                                children: [
                                  if (business.can('recipes.read') &&
                                      widget.section !=
                                          BusinessSection.management)
                                    Padding(
                                        padding:
                                            const EdgeInsets.only(bottom: 12),
                                        child: Wrap(
                                            spacing: 8,
                                            runSpacing: 8,
                                            children: [
                                              OutlinedButton.icon(
                                                  onPressed: () => context.push(
                                                      '/business-workspaces/${widget.workspace}/meals'),
                                                  icon: const Icon(Icons
                                                      .calendar_month_outlined),
                                                  label: Text(bt(
                                                      context,
                                                      '식단 달력',
                                                      'Meal calendar'))),
                                              OutlinedButton.icon(
                                                  onPressed: () => context.push(
                                                      '/business-workspaces/${widget.workspace}/menus'),
                                                  icon: const Icon(
                                                      Icons.restaurant_menu),
                                                  label: Text(bt(
                                                      context,
                                                      '메뉴판 관리',
                                                      'Menu management'))),
                                              if (business
                                                  .can('purchasing.write'))
                                                OutlinedButton.icon(
                                                    onPressed: () => context.push(
                                                        '/business-workspaces/${widget.workspace}/menu-purchase'),
                                                    icon: const Icon(Icons
                                                        .shopping_cart_outlined),
                                                    label: Text(bt(
                                                        context,
                                                        '메뉴·레시피에서 구매',
                                                        'Buy from menus / recipes')))
                                            ])),
                                  if (business.can('purchasing.read') &&
                                      widget.section ==
                                          BusinessSection.purchasing)
                                    OutlinedButton.icon(
                                        onPressed: () => context.push(
                                            '/business-workspaces/${widget.workspace}/suppliers'),
                                        icon: const Icon(
                                            Icons.storefront_outlined),
                                        label: Text(bt(context, '업소 거래처·상품',
                                            'Business suppliers & products'))),
                                  if (business.can('purchasing.read'))
                                    OutlinedButton.icon(
                                        onPressed: () => context.push(
                                            '/business-workspaces/${widget.workspace}/inventory'),
                                        icon: const Icon(
                                            Icons.inventory_2_outlined),
                                        label: Text(bt(context, '재고·조리 예약',
                                            'Stock & cooking reservations'))),
                                ]),
                            const SizedBox(height: 8),
                            Wrap(spacing: 8, runSpacing: 6, children: [
                              for (final k in kinds)
                                ChoiceChip(
                                    key: ValueKey('business-kind-$k'),
                                    label: Text(businessKindLabel(context, k)),
                                    selected: kind == k,
                                    onSelected: (_) => setState(() {
                                          _kind = k;
                                          _offset = 0;
                                          _search = '';
                                          _status = 'all';
                                        }))
                            ]),
                            if (kind == null)
                              Text(bt(
                                  context,
                                  '현재 사용할 수 있는 업무가 없습니다. 사장에게 권한을 확인해 주세요.',
                                  'No work is available with your current permissions. Check with the owner.'))
                            else ...[
                              const SizedBox(height: 16),
                              Wrap(spacing: 10, runSpacing: 8, children: [
                                if (business
                                    .can(businessPermission(kind, write: true)))
                                  FilledButton.icon(
                                      onPressed: () => context.push(kind ==
                                                  'purchase' &&
                                              business.can('recipes.read')
                                          ? '/business-workspaces/${widget.workspace}/menu-purchase'
                                          : '/business-workspaces/${widget.workspace}/new/$kind'),
                                      icon: const Icon(Icons.add),
                                      label: LocalizedText(kind == 'purchase' &&
                                              business.can('recipes.read')
                                          ? bt(context, '메뉴·레시피에서 구매',
                                              'Buy from menus / recipes')
                                          : '${businessKindLabel(context, kind)} ${bt(context, '추가', '— add')}')),
                                if (kind == 'recipe' &&
                                    business.can('recipes.write'))
                                  OutlinedButton.icon(
                                      onPressed: () => _importRecipe(business),
                                      icon: const Icon(Icons.copy_outlined),
                                      label: Text(bt(
                                          context,
                                          '${recipeLibraryName(owner: ref.watch(recipeOwnerNameProvider))}에서 가져오기',
                                          'Copy a personal recipe'))),
                                if (kind == 'sale')
                                  OutlinedButton.icon(
                                      onPressed: () => context.push(
                                          '/business-workspaces/${widget.workspace}/sales'),
                                      icon:
                                          const Icon(Icons.bar_chart_outlined),
                                      label: Text(bt(context, '일·주·월 매출',
                                          'Daily, weekly & monthly sales'))),
                              ]),
                              const SizedBox(height: 14),
                              TextField(
                                  key: ValueKey('business-search-$kind'),
                                  decoration: InputDecoration(
                                      prefixIcon: const Icon(Icons.search),
                                      labelText: bt(context, '현재 페이지에서 제목 검색',
                                          'Search titles on this page')),
                                  onChanged: (v) => setState(
                                      () => _search = v.trim().toLowerCase())),
                              if (kind == 'purchase')
                                Padding(
                                    padding: const EdgeInsets.only(top: 8),
                                    child: Wrap(
                                        spacing: 6,
                                        runSpacing: 4,
                                        children: [
                                          for (final status in [
                                            'all',
                                            'draft',
                                            'review',
                                            'approved',
                                            'sent',
                                            'received',
                                            'cancelled'
                                          ])
                                            ChoiceChip(
                                                label: Text(status == 'all'
                                                    ? bt(context, '전체', 'All')
                                                    : businessStatusLabel(
                                                        context, status)),
                                                selected: _status == status,
                                                onSelected: (_) => setState(
                                                    () => _status = status))
                                        ])),
                              const SizedBox(height: 12),
                              ref.watch(businessRecordsProvider(query)).when(
                                  data: (rows) {
                                    final filtered = rows.where((r) =>
                                        r.title
                                            .toLowerCase()
                                            .contains(_search) &&
                                        (kind != 'purchase' ||
                                            _status == 'all' ||
                                            r.status == _status));
                                    return Column(children: [
                                      if (filtered.isNotEmpty)
                                        BusinessRecordList(
                                            records: filtered.toList(),
                                            statusLabel: (r) =>
                                                r.status == 'cancelled' &&
                                                        kind != 'purchase'
                                                    ? bt(context, '사용 중지',
                                                        'Archived')
                                                    : businessStatusLabel(
                                                        context, r.status),
                                            onOpen: (r) => context.push(
                                                '/business-workspaces/${widget.workspace}/records/${r.id}')),
                                      if (filtered.isEmpty)
                                        Padding(
                                            padding: const EdgeInsets.all(16),
                                            child: Text(bt(
                                                context,
                                                '표시할 자료가 없습니다. 새 자료를 추가하거나 검색 조건을 바꿔 주세요.',
                                                'No matching records. Add a record or adjust the filters.'))),
                                      Wrap(spacing: 12, children: [
                                        if (_offset > 0)
                                          TextButton(
                                              onPressed: () =>
                                                  setState(() => _offset -= 50),
                                              child: Text(bt(context, '이전 50개',
                                                  'Previous 50'))),
                                        LocalizedText(
                                            '${rows.isEmpty ? 0 : _offset + 1}–${_offset + rows.length}'),
                                        if (rows.length == 50)
                                          TextButton(
                                              onPressed: () =>
                                                  setState(() => _offset += 50),
                                              child: Text(bt(context, '다음 50개',
                                                  'Next 50')))
                                      ])
                                    ]);
                                  },
                                  loading: () =>
                                      const LinearProgressIndicator(),
                                  error: (e, _) => _BusinessError(
                                      e,
                                      () => ref.invalidate(
                                          businessRecordsProvider(query)))),
                            ],
                            const SizedBox(height: 16),
                            Text(
                                bt(
                                    context,
                                    '구매량과 조리량은 별도입니다. 조리 재고를 자동 차감하지 않습니다.',
                                    'Purchase and cooking quantities stay separate. Cooking does not deduct stock.'),
                                style: Theme.of(context).textTheme.bodySmall)
                          ]))));
        },
        loading: () =>
            const Scaffold(body: Center(child: CircularProgressIndicator())),
        error: (e, _) => Scaffold(
            appBar: AppBar(
                title: Text(bt(context, '업소 공동 업무', 'Business workspace'))),
            body: _BusinessError(
                e,
                () => ref
                    .invalidate(businessContextProvider(widget.workspace)))));
  }

  Future<void> _importRecipe(BusinessContext business) =>
      collectPersonalRecipe(context, ref, business);
}
