import 'guide_curriculum.dart';

/// A concrete action for every record-backed lesson; no login prerequisites.
const guideSampleTasks = <String, GuideText>{
  'home-search': (
    ko: '샘플 3개 중 요리를 선택하고 저장하세요. 다음 초안 검토에 선택한 요리가 이어집니다.',
    en: 'Choose one of three recipes and save. Your choice carries into draft review.'
  ),
  'home-draft': (
    ko: '재료 수량 하나를 바꾼 뒤 검토 표시를 하고 저장하세요. 레시피 저장 체험에서 수정한 값을 확인할 수 있어요.',
    en: 'Edit one ingredient amount, mark your review and save. Your changes appear in the recipe-saving lesson.'
  ),
  'home-save': (
    ko: '레시피 이름이나 메모를 바꾸고 저장하세요. 닫았다 다시 열면 수정한 자료가 남아 있어요.',
    en: 'Edit the recipe name or note and save. Close and reopen to see your saved changes.'
  ),
  'home-shopping': (
    ko: '구매할 재료를 선택하고 구매 수량을 바꾼 뒤 목록을 만드세요. 다음 체험에서 구매 완료를 기록합니다.',
    en: 'Select ingredients, edit purchase quantities and create a list. Record completed purchases in the next lesson.'
  ),
  'home-repeat': (
    ko: '구매한 재료를 체크하고 다음 조리 메모를 남기세요. 다시 준비를 누르면 완료 표시를 비운 구매 목록이 됩니다.',
    en: 'Check purchased items and add a cooking note. Prepare again clears purchase completion for a new trip.'
  ),
  'pro-standard': (
    ko: '준비된 레시피 5개 중 하나를 골라 기준 인분·재료·조리 순서를 수정하고 저장하세요.',
    en: 'Choose one of five recipes. Edit base servings, ingredients or instructions and save.'
  ),
  'pro-scale': (
    ko: '목표 인분을 4에서 20으로 바꿔 보세요. 조리 사용량은 5배가 되고 구매 목록은 유지됩니다.',
    en: 'Change target servings from 4 to 20. Cooking quantities multiply by five; the shopping list stays unchanged.'
  ),
  'pro-yield': (
    ko: '첫 재료의 수율을 80%에서 100%로 바꿔 보세요. 원가용 손질 전 분량과 원가가 줄어듭니다.',
    en: 'Change the first ingredient’s yield from 80% to 100%. Pre-trim quantity and ingredient cost decrease.'
  ),
  'pro-cost': (
    ko: '첫 재료의 구매가를 바꾸고 추가 비용을 하나 넣어 보세요. 하단의 1인분 원가에서 변화를 확인하세요.',
    en: 'Change an ingredient purchase price and add a cost item. Check the updated portion cost below.'
  ),
  'pro-pricing': (
    ko: '가산율을 50%로 입력하세요. 판매가는 원가의 1.5배를 기준으로 자동 계산됩니다.',
    en: 'Enter a 50% markup. Selling price is calculated as 1.5 times portion cost, rounded to the currency.'
  ),
  'pro-sales': (
    ko: '판매 수량 10개를 기록하고 일·주·월을 바꿔 보세요. 매출과 기록 원가 차액을 비교할 수 있어요.',
    en: 'Record ten sold portions and switch day, week and month. Compare revenue and recorded costs.'
  ),
  'pro-versions': (
    ko: '가산율이나 메모를 바꾸고 이전 버전과 차이를 확인한 뒤 새 버전으로 저장하세요.',
    en: 'Change markup or notes, compare with a saved version, then save a new version.'
  ),
  'pro-ai': (
    ko: '준비된 분석 결과를 불러오고 메모·수량을 검토해 저장하세요. 실제 AI는 호출하지 않습니다.',
    en: 'Load the prepared analysis, review notes and quantities, then save. No live AI is called.'
  ),
  'buy-quantity': (
    ko: '당근 구매량을 1kg에서 2kg으로 바꾸고 목록을 만드세요. 업체 비교와 요청서에도 이어집니다.',
    en: 'Change the carrot purchase quantity from 1 kg to 2 kg and create the list. It carries into comparison and requests.'
  ),
  'buy-suppliers': (
    ko: '가상 업체 B를 내 거래처로 선택하고 저장하세요. 업체 후보에서 내 거래처가 먼저 보입니다.',
    en: 'Save fictional supplier B as your supplier. It appears first in candidate selection.'
  ),
  'buy-candidates': (
    ko: '당근의 업체 후보를 바꿔 보세요. 재료별로 최대 3곳까지 선택한 뒤 저장합니다.',
    en: 'Change carrot supplier candidates. Select up to three per ingredient and save.'
  ),
  'buy-compare': (
    ko: '세 가지 비교 결과 중 기준을 하나 고르고 초안을 만드세요. 선택한 업체별로 요청서가 만들어집니다.',
    en: 'Choose one of three comparison priorities and create drafts. One request is made for each selected supplier.'
  ),
  'buy-request': (
    ko: '업소명·수량·납품 조건을 수정하고 미리보기 또는 PDF를 확인하세요. 검토 표시 후 모의 발송할 수 있어요.',
    en: 'Edit buyer, quantities and delivery details. Preview the request or PDF, then review and simulate sending.'
  ),
  'buy-ledger': (
    ko: '요청서 상태를 바꾸거나 다시 요청 초안을 눌러 보세요. 재요청은 새 가격과 납품일을 확인해서 입력합니다.',
    en: 'Change a request status or draft a repeat request. Enter newly confirmed prices and delivery dates for repeats.'
  ),
  'supplier-profile': (
    ko: '가상의 업체명과 배송 지역을 바꾸고 저장하세요. 공개 검토 화면에 반영됩니다.',
    en: 'Edit the fictional business name and delivery area, then save. Your changes appear in publication review.'
  ),
  'supplier-product': (
    ko: '상품 6개 중 하나를 골라 이름·그림·분류를 바꾸고 저장하세요.',
    en: 'Choose one of six products, edit its name, illustration and category, then save.'
  ),
  'supplier-pack': (
    ko: '상품의 포장당 내용량을 1kg에서 2kg으로 바꿔 보세요. 1kg당 가격이 절반으로 바뀝니다.',
    en: 'Change pack content from 1 kg to 2 kg. The displayed price per kg halves.'
  ),
  'supplier-publish': (
    ko: '준비된 업체와 상품 정보를 검토하고 공개 모의 실행을 누르세요. 연습 공간 안에서만 공개됩니다.',
    en: 'Review the business and products, then simulate publication. It is visible only within practice.'
  ),
  'supplier-update': (
    ko: '상품 가격을 수정하고 저장한 뒤 공개 체험으로 이동해 보세요. 변경 후 다시 검토할 수 있어요.',
    en: 'Edit and save a product price, then return to publication practice to review the updated details.'
  ),
};
