import 'package:flutter/widgets.dart';
import 'app_localizations.dart';

String chefText(BuildContext context, String key) {
  final entry = chefLabels[key];
  assert(entry != null, 'Missing chef label: $key');
  return entry == null
      ? key
      : AppLocalizations.of(context).bilingual(entry[0], entry[1]);
}

const chefLabels = <String, List<String>>{
  'purchaseUnitInUsageUnits': ['환산 기준', 'Unit conversion'],
  'conversionNeeded': [
    '환산 기준이 필요합니다. 단가 바로 수정에서 입력해 주세요.',
    'Conversion needed. Enter it in Quick price edit.'
  ],
  'upgradeRequired': [
    '이 작업의 단위를 안전하게 저장하려면 앱을 업데이트해 주세요.',
    'Update the app to safely save the units in this workspace.'
  ],
  'studio': ['셰프 작업실', 'Chef studio'],
  'pricing': ['판매가 설정', 'Set selling price'],
  'markupPercent': ['원가 가산율 (%)', 'Markup on cost (%)'],
  'pricingHint': [
    '0%는 원가와 같은 가격, 100%는 원가의 두 배입니다. 판매가를 기준으로 한 이익률과 다릅니다.',
    '0% equals cost; 100% doubles cost. This is a markup on cost, not a margin on selling price.'
  ],
  'sellingPrice': ['1인분 판매가', 'Selling price per serving'],
  'sales': ['매출 현황', 'Sales overview'],
  'salesMore': ['판매 기록 더 보기', 'Load more sales'],
  'salesCurrencyHint': [
    '판매 기록을 추가하려면 저장된 작업의 통화를 선택하세요.',
    'Select the saved workspace currency to record a sale.'
  ],
  'saveAndSales': ['저장하고 매출 관리', 'Save and manage sales'],
  'allSales': ['전체 요리 매출 보기', 'View sales for all dishes'],
  'day': ['일별', 'Daily'],
  'week': ['주별', 'Weekly'],
  'month': ['월별', 'Monthly'],
  'previousPeriod': ['이전 기간', 'Previous period'],
  'nextPeriod': ['다음 기간', 'Next period'],
  'saleDate': ['판매일', 'Sale date'],
  'saleQuantity': ['판매 수량 (인분)', 'Servings sold'],
  'revenue': ['매출액', 'Revenue'],
  'salesCost': ['판매분 원가', 'Cost of sales'],
  'profit': ['예상이익', 'Estimated profit'],
  'recordSale': ['판매 수량 기록', 'Record servings sold'],
  'editSale': ['판매 기록 수정', 'Edit sale'],
  'deleteSale': ['판매 기록 삭제', 'Delete sale'],
  'deleteSaleConfirm': ['이 판매 기록을 삭제할까요?', 'Delete this sale record?'],
  'salesHint': [
    '매출액 − 기록 당시 원가 = 예상이익. 입력하지 않은 비용과 세금은 포함되지 않습니다. 주별은 월요일부터 일요일까지입니다.',
    'Estimated profit = revenue minus recorded cost. Unentered expenses and taxes are excluded. Weeks run Monday through Sunday.'
  ],
  'saleSnapshotHint': [
    '저장된 판매가와 1인분 원가를 기록합니다. 이후 단가가 바뀌어도 과거 기록은 유지됩니다.',
    'Records the saved selling price and cost per serving. Later price changes do not alter past sales.'
  ],
  'saleEditHint': [
    '판매일과 수량만 수정합니다. 기록 당시 판매가와 원가는 유지됩니다.',
    'Only date and quantity change. The recorded price and cost stay unchanged.'
  ],
  'noSales': ['이 기간의 판매 기록이 없습니다.', 'No sales recorded for this period.'],
  'salesError': [
    '매출 정보를 처리하지 못했습니다. 다시 불러와 확인해 주세요.',
    'Could not process sales information. Reload and check your records.'
  ],
  'salesCostRequired': [
    '원가와 인분을 확인하고 작업을 저장하면 판매 수량을 기록할 수 있습니다.',
    'Complete costs and servings, then save the workspace before recording sales.'
  ],
  'salesStale': [
    '원가나 판매가가 변경되었습니다. 창을 닫고 다시 불러온 뒤 확인해 주세요.',
    'Costs or prices changed. Close this dialog and reload before recording the sale.'
  ],
  'intro': ['한 접시의 기준.', 'Refine every plate.'],
  'subtitle': [
    '인분·수율·원가를 연결하고, 더 나은 배합을 기록하세요.',
    'Scale portions, account for yield, and keep every refinement.'
  ],
  'formula': ['배합과 원가', 'Formula & cost'],
  'versions': ['버전 관리', 'Versions'],
  'base': ['기준 인분', 'Base servings'],
  'target': ['목표 인분', 'Target servings'],
  'title': ['요리 이름', 'Dish name'],
  'saved': ['저장됨', 'Saved'],
  'unsaved': ['저장하지 않은 변경', 'Unsaved changes'],
  'save': ['작업 저장', 'Save work'],
  'snapshot': ['새 버전 저장', 'Save a version'],
  'batchCost': ['목표 배치 원가', 'Target batch cost'],
  'portionCost': ['1인분 원가', 'Cost per serving'],
  'yield': ['조리 수율', 'Cooking yield'],
  'unknown': ['확인 필요', 'Needs review'],
  'knownCost': ['기준 배치의 확인된 재료비', 'Known ingredient cost · base batch'],
  'incomplete': [
    '수량·단가·단위를 확인하면 전체 원가가 계산됩니다.',
    'Complete quantities, prices and compatible units to calculate the full cost.'
  ],
  'baseHint': [
    '기준 인분을 확인해 입력하세요. 조리 시간과 온도는 자동 배수 환산하지 않습니다.',
    'Confirm the original serving count. Cooking time and temperature are not multiplied.'
  ],
  'ingredients': ['재료 배합', 'Ingredient formula'],
  'ingredientHint': [
    '사용량은 손질 후 기준입니다. 구매량에는 손질 손실을 반영합니다.',
    'Enter edible quantities after trimming. Purchase quantities include trimming loss.'
  ],
  'add': ['재료 추가', 'Add ingredient'],
  'edit': ['재료 수정', 'Edit ingredient'],
  'name': ['재료명', 'Ingredient'],
  'quantity': ['기준 사용량', 'Base edible quantity'],
  'unit': ['사용 단위', 'Recipe unit'],
  'purchaseQuantity': ['구매 포장량', 'Purchase pack quantity'],
  'purchaseUnit': ['구매 단위', 'Purchase unit'],
  'purchasePrice': ['포장 구매가', 'Price per pack'],
  'yieldPercent': ['손질 수율 (%)', 'Trim yield (%)'],
  'yieldHint': [
    '손실이 없으면 100%. 예: 80%이면 사용량 800g에 구매량 1kg.',
    '100% means no trimming loss. At 80%, 800 g edible requires 1 kg purchased.'
  ],
  'edible': ['환산 사용량', 'Scaled edible'],
  'purchase': ['필요 구매량', 'Purchase needed'],
  'lineCost': ['재료 원가', 'Ingredient cost'],
  'emptyIngredients': [
    '재료를 추가해 배합을 시작하세요.',
    'Add ingredients to start your formula.'
  ],
  'extraCost': ['기준 배치 추가 비용', 'Extra cost · base batch'],
  'costItems': ['추가 비용 관리', 'Manage additional costs'],
  'costItem': ['비용 항목 추가·삭제', 'Cost item added / removed'],
  'addCost': ['비용 항목 추가', 'Add cost item'],
  'editCost': ['비용 수정', 'Edit cost'],
  'removeCost': ['비용 삭제', 'Remove cost'],
  'costName': ['항목 이름', 'Item name'],
  'costAmount': ['기준 배치 금액', 'Amount for base batch'],
  'legacyCost': ['기존에 입력한 추가 비용', 'Previously entered additional cost'],
  'costTotal': ['기준 배치 추가 비용 합계', 'Additional cost total · base batch'],
  'costEmpty': [
    '필요한 비용을 항목별로 추가하세요.',
    'Add the costs that apply to this recipe.'
  ],
  'costLimit': [
    '비용 항목은 최대 100개까지 추가할 수 있습니다.',
    'You can add up to 100 cost items.'
  ],
  'costTotalLimit': [
    '추가 비용 합계가 입력 한도를 초과합니다.',
    'The additional cost total exceeds the allowed limit.'
  ],
  'deleteCostConfirm': [
    '이 비용을 원가 계산에서 제외할까요?',
    'Remove this item from the cost calculation?'
  ],
  'labor': ['인건비', 'Labor'],
  'packaging': ['포장비', 'Packaging'],
  'utilities': ['공과금', 'Utilities'],
  'delivery': ['배송비', 'Delivery'],
  'editPrice': ['단가 바로 수정', 'Quick price edit'],
  'extraHint': [
    '기준 인분에 드는 비용을 항목별로 입력하세요. 목표 인분에 비례해 환산되며, 작업 저장을 누르면 보관됩니다.',
    'Enter each cost for the base servings. Costs scale with target servings. Select Save work to keep your changes.'
  ],
  'currency': ['통화', 'Currency'],
  'currencyConfirm': [
    '숫자는 유지되고 통화만 바뀝니다. 환율 변환은 하지 않습니다. 단가를 다시 확인하세요.',
    'Amounts stay unchanged; only the currency changes. No exchange conversion is applied. Review your prices.'
  ],
  'weights': ['배치 중량과 조리 수율', 'Batch weight & cooking yield'],
  'inputWeight': ['기준 배치 조리 전 총중량 (g)', 'Base batch input weight (g)'],
  'outputWeight': ['기준 배치 완성 중량 (g)', 'Base batch finished weight (g)'],
  'weightHint': [
    '수율 = 완성 중량 ÷ 조리 전 중량. 물을 흡수하는 요리는 100%를 넘을 수 있습니다.',
    'Yield = finished weight ÷ input weight. Water absorption can produce a yield above 100%.'
  ],
  'cost100': ['완성품 100g 원가', 'Cost per 100 g finished'],
  'steps': ['조리법', 'Method'],
  'notes': ['개발 메모', 'Development notes'],
  'copy': ['환산 재료 복사', 'Copy scaled ingredients'],
  'copied': ['환산 재료를 복사했습니다.', 'Scaled ingredients copied.'],
  'copyReview': [
    '인분과 모든 재료 수량을 먼저 확인해 주세요.',
    'Confirm servings and all ingredient quantities first.'
  ],
  'noVersions': ['첫 버전을 기록해 보세요.', 'Save your first version.'],
  'versionHint': [
    '버전에는 배합·단가·수율·조리법이 함께 저장됩니다. 불러온 버전은 새 작업으로 편집합니다.',
    'Versions keep quantities, prices, yield and method together. Restore one to start a new working draft.'
  ],
  'versionLabel': ['버전 이름', 'Version name'],
  'versionNote': ['변경 이유', 'Reason for change'],
  'restore': ['작업으로 불러오기', 'Restore to workspace'],
  'compare': ['두 버전 비교', 'Compare two versions'],
  'older': ['기준 버전', 'Baseline version'],
  'newer': ['비교 버전', 'Comparison version'],
  'noChanges': ['배합과 조리 정보가 같습니다.', 'No formula or method changes.'],
  'more': ['이전 버전 더 보기', 'Load earlier versions'],
  'before': ['이전', 'Before'],
  'after': ['이후', 'After'],
  'remove': ['재료 삭제', 'Remove ingredient'],
  'cancel': ['취소', 'Cancel'],
  'confirm': ['확인', 'Confirm'],
  'required': ['필수 항목입니다.', 'Required.'],
  'number': ['유효한 범위의 숫자를 입력하세요.', 'Enter a number within the allowed range.'],
  'loadError': [
    '작업실을 불러오지 못했습니다. 로그인·네트워크·서버 적용 상태를 확인해 주세요.',
    'Could not load the workspace. Check login, connection and server availability.'
  ],
  'saveError': [
    '저장하지 못했습니다. 입력 내용은 화면에 남아 있습니다.',
    'Could not save. Your edits remain on this screen.'
  ],
  'conflict': [
    '다른 곳에서 수정한 내용이 있습니다. 다시 불러온 뒤 변경 내용을 확인해 주세요.',
    'This workspace changed elsewhere. Reload and review before saving.'
  ],
  'reload': ['다시 불러오기', 'Reload'],
  'discard': [
    '저장하지 않은 변경을 버리고 계속할까요?',
    'Discard unsaved changes and continue?'
  ],
  'historyError': [
    '작업은 저장했지만 버전 목록을 갱신하지 못했습니다. 다시 불러와 확인해 주세요.',
    'Work saved, but version history could not refresh. Reload to check it.'
  ],
  'saveSuccess': ['작업을 저장했습니다.', 'Workspace saved.'],
  'snapshotSuccess': ['새 버전을 저장했습니다.', 'New version saved.'],
  'sourceHint': [
    '내 레시피에 연결된 별도 배합 작업실입니다. 원본 레시피가 삭제되면 작업실과 버전도 삭제됩니다.',
    'A separate formula workspace linked to your recipe. Deleting the recipe also deletes its workspace and versions.'
  ],
  'ingredient': ['재료 추가·삭제', 'Ingredient added / removed'],
  'baseServings': ['기준 인분', 'Base servings'],
  'targetServings': ['목표 인분', 'Target servings'],
  'each': ['개', 'ea'],
  'limit': ['재료는 최대 200개까지 추가할 수 있습니다.', 'You can add up to 200 ingredients.'],
};
