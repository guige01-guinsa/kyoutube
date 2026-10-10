// Menu candidates and fast purchase preparation.
const businessMenuFastUiTranslations = <String, String>{
  '환산 범위를 벗어난 수량이 있습니다. 재료별 수량을 먼저 확인하세요.':
      'A quantity is outside the conversion range. Check each ingredient first.',
  '무게·부피·개수·포장을 구분하세요. 1봉·1컵의 양이나 g↔ml 환산은 재료마다 다르므로 추정하지 않습니다.':
      'Keep weight, volume, counts and packages distinct. A bag, cup or g↔ml conversion needs an ingredient-specific basis.',
  '표준 단위로 정리 (g·ml·개)': 'Standardize units (g / ml / each)',
  '부족량': 'Shortfall',
  '포장 올림 여유량': 'Pack rounding surplus',
  '포장 환산': 'Converted pack',
  'g↔kg, mL↔L은 표준 환산합니다. 무게↔부피·개수·포장은 실제 상품 기준을 확인해 입력하세요.':
      'g↔kg and mL↔L use standard conversion. For weight↔volume, counts or packs, enter a verified product-specific basis.',
  '요청할 재료를 하나 이상 선택하세요.': 'Select at least one ingredient.',
  '재고·입고 예정량으로 충당됩니다. 추가 구매할 수량이 없습니다.':
      'Stock and incoming quantities cover this plan. No additional purchase is needed.',
  '필요량 → 사용 가능 재고 → 부족량 → 포장 단위 구매량 순서로 확인하세요.':
      'Check required quantity → available stock → shortfall → packs to buy.',
  '분류는 목록 정리용입니다. 같은 분류라도 재료·규격이 다르면 합치지 않습니다.':
      'Categories organize the list. Different ingredients or specifications are kept separate.',
  '확인 필요만': 'Needs review only',
  '조건에 맞는 재료가 없습니다. 전체 재료를 선택하거나 필터를 해제하세요.':
      'No matching ingredients. Select all categories or clear the filters.',
  '수량·환산 범위를 확인하세요.': 'Check the quantity / conversion range.',
  '필요한 재료부터 입고까지': 'From ingredients to receiving',
  '메뉴로 구매 목록 만들기': 'Plan purchases from menus',
  '레시피·시험 조리 구매': 'Recipe / trial purchases',
  '직접 구매요청 작성': 'Write a request',
  '판매 메뉴와 인분을 고르면 재료를 취합하고, 재고와 포장을 확인해 업체별 초안을 만듭니다.':
      'Choose selling menus and servings, review stock and pack sizes, then prepare supplier drafts.',
  '진행할 구매요청': 'Purchase requests to follow up',
  '업체·재료·요청서 검색': 'Search supplier, ingredient or request',
  '검색·단계별 건수는 현재 불러온 50개 이내의 요청서 기준입니다.':
      'Search and status counts apply to this page of up to 50 requests.',
  '아직 구매요청이 없습니다. 위에서 구매 목록을 만들어 시작하세요.':
      'No requests yet. Start by planning your purchase list above.',
  '조건에 맞는 요청서가 없습니다. 검색어나 단계를 바꿔 보세요.':
      'No matching requests. Change the search or status.',
  '승인 내용 검토': 'Review for approval',
  '전달 준비': 'Prepare to share',
  '미정': 'Not set',
  '부분 입고가 있으면 남은 수량을 확인하세요.':
      'For partial receipts, check the remaining quantity.',
  '상세 보기': 'Details',
  '재료 분류·단위 합산·보유량을 확인하고 구매할 목록을 확정하세요.':
      'Group ingredients, combine compatible units and check stock before buying.',
  '가격 미정': 'Price pending',
  "각 재료의 구매 기준을 설정하거나 변경된 상품을 다시 확인하세요.":
      "Set purchasing defaults or reconfirm changed products.",
  "같은 요청 재확인": "Retry the same request",
  "개 메뉴": "menus",
  "건의 재고 예약. 조리 후 사용 기록 또는 미사용 예약 해제가 필요합니다.":
      "stock reservations. Record actual use after cooking or release unused stock.",
  "계획 이름 (예: 월요일 점심)": "Plan name (e.g. Monday lunch)",
  "계획 저장": "Save plan",
  "공통 구매 기준": "Purchasing defaults",
  "구매 계획 불러오기": "Load a menu plan",
  "구매 계획을 저장했습니다.": "Menu plan saved.",
  "구매 준비를 완료했습니다. 단가·납품 조건을 확인하고 승인 절차를 진행하세요.":
      "Preparation complete. Review prices and delivery terms, then follow the approval process.",
  "구매처·규격·환산·중복 요청·재고 예약을 확인했습니다.":
      "I checked suppliers, packs, conversions, open requests and stock reservations.",
  "기본 구매처": "Default supplier",
  "납품 희망일 (YYYY-MM-DD)": "Requested delivery (YYYY-MM-DD)",
  "납품일을 YYYY-MM-DD로 입력하세요.": "Enter delivery as YYYY-MM-DD.",
  "레시피 버전 선택": "Choose recipe revision",
  "메뉴 1~20개와 올바른 인분을 입력하세요.": "Select 1–20 menus with valid servings.",
  "메뉴 선정 담당": "Menu approver",
  "메뉴 선정·출시·가격 관리": "Select, launch and price menus",
  "메뉴 후보": "Menu candidate",
  "메뉴·구매 기준·재고 또는 진행 중 요청이 바뀌었습니다. 다시 계산하고 확인하세요.":
      "Menus, defaults, inventory or open requests changed. Recalculate and review.",
  "상품 선택": "Choose product",
  "상품·재료·단위 환산과 재고 연결이 맞습니다.":
      "Product, ingredient, conversion and stock link are correct.",
  "새 구매 준비": "Start another plan",
  "업체별 초안 생성·재고 예약": "Create supplier drafts and reserve stock",
  "연결 안 함 · 차감 없음": "No link / no stock deduction",
  "연결한 재고의 사용 가능량 반영·예약": "Use and reserve linked available stock",
  "요일·저장 계획": "Saved plans",
  "응답을 확인하지 못했습니다. 같은 요청 재확인으로 중복 생성을 방지하세요.":
      "Response uncertain. Retry the same request to avoid duplicates.",
  "이 버전을 메뉴 후보로 담기": "Add this revision as a menu candidate",
  "입고 예정량은 자동 차감하지 않습니다. 진행 중 요청을 확인하고 중복 계획은 조정하세요. 재고 연결이 없으면 재고를 차감하지 않습니다.":
      "Incoming quantities are not automatically deducted. Check open requests and adjust overlapping plans. Unlinked stock is not deducted.",
  "재고 사용": "From stock",
  "재고 연결 (선택)": "Stock link (optional)",
  "재고·예약 관리": "Manage stock / reservations",
  "재료·구매량 계산": "Calculate ingredients and purchases",
  "저장된 계획의 메뉴가 변경·중지되었습니다. 현재 판매 메뉴와 인분을 다시 선택하세요.":
      "A saved menu changed or stopped. Select current menus and servings again.",
  "준비 인분": "Servings to prepare",
  "지난 구매 계획": "Recent plans",
  "진행 중 구매요청 확인": "Review open purchases",
  "판매 메뉴로 빠른 구매": "Quick purchase from menus",
  "판매 메뉴와 인분으로 업체별 초안을 준비합니다. 개발용 구매는 메뉴판 관리에서 진행합니다.":
      "Prepare supplier drafts from active menus and servings. Use menu management for development purchases.",
  "판매 메뉴와 인분을 선택하면 재료를 합산하고 기본 구매처별 초안을 준비합니다.":
      "Choose active menus and servings to combine ingredients and prepare supplier drafts.",
  "판매 중인 메뉴가 없습니다. 메뉴판 관리에서 판매 상태를 확인하세요.":
      "No active menus. Review their selling state in menu management.",
  "필요량": "Required",
  "후보는 개발 버전, 판매 메뉴는 승인 버전을 선택하세요.":
      "Use a development revision for candidates; an approved revision for launch.",
  "후보는 개발 중에도 등록할 수 있습니다. 출시 준비·판매 전에는 승인된 레시피 버전과 판매가를 확인합니다.":
      "Add candidates during development. Launch requires an approved revision and a selling price.",
};
