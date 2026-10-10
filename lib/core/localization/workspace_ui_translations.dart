// Work-area ownership, shared business navigation and supplier management.
const workspaceUiTranslations = <String, String>{
  '진행 중인 조리 예약을 먼저 해제해 주세요.': 'Release active cooking reservations first.',
  '연결된 구매요청서를 먼저 정리해 주세요. 입고 기록만 지우면 중복 입고될 수 있습니다.':
      'Manage the linked purchase requests first. Erasing only receipts could allow duplicate deliveries.',
  '환산 결과가 허용 수량 또는 소수점 6자리 범위를 벗어납니다. 비율을 다시 확인해 주세요.':
      'The conversion exceeds quantity limits or six decimal places. Check the ratio.',
  '같은 재료·규격·단위의 품목이 이미 있습니다. 기존 품목을 확인해 주세요.':
      'An item with this name, specification and unit already exists. Review it first.',
  '확인 중 기록이 바뀌었거나 삭제되었습니다. 닫고 새로고침한 뒤 다시 확인해 주세요.':
      'The record changed or was deleted. Close, refresh and review again.',
  '소유자만 이 작업을 할 수 있습니다. 계정과 이용 권한을 확인해 주세요.':
      'Only the owner can perform this action. Check your account and access.',
  '처리하지 못했습니다. 서버 업데이트와 입력값을 확인한 뒤 다시 시도해 주세요.':
      'Could not complete. Check the server update and inputs, then retry.',
  '새 단위와 0보다 큰 환산 비율을 입력해 주세요.':
      'Enter a new unit and a positive conversion ratio.',
  '함께 삭제되는 이력': 'History erased',
  '함께 삭제되는 거래 평가': 'Reviews erased',
  '삭제되는 취급상품': 'Products erased',
  '해제되는 기본 구매 연결': 'Purchasing mappings detached',
  '관련 수불 기록': 'Related stock movements',
  '관련 예약 기록': 'Related reservations',
  '재고를 유지하는 입고·반품 기록': 'Receipts and returns retaining stock',
  '삭제 상태를 표시할 구매 준비 내역': 'Preparation results marked deleted',
  '재고 단위 변경': 'Change stock unit',
  '영구 삭제 확인': 'Review permanent deletion',
  '현재 단위': 'Current unit',
  '새 단위': 'New unit',
  '기존 1단위에 해당하는 새 단위 수량': 'New quantity for one old unit',
  '개·봉·박스 등은 실제 규격을 확인해 비율을 입력하세요. 구매 포장 수량과 금액은 유지됩니다.':
      'For pieces, bags or boxes, verify the pack size and enter the ratio. Purchased pack quantities and prices stay unchanged.',
  '환산 영향 확인': 'Preview conversion',
  '변경 후 레시피의 재고 연결을 다시 확인하세요. 이전 화면에서 입력하던 작업은 새로고침해야 합니다.':
      'Recheck recipe-to-stock mappings afterward. Refresh any screens opened before the change.',
  '이 기록은 복구할 수 없습니다. 외부에 전달한 주문의 취소·환불은 별도로 처리해야 합니다.':
      'This record cannot be restored. Cancel or refund externally shared orders separately.',
  '실제 재고 수량은 변경하지 않습니다.': 'Physical stock quantities are unchanged.',
  '이 품목의 현재고와 수불·예약 기록을 함께 삭제합니다.':
      'This item, its on-hand stock, movements and reservation history will be erased.',
  '공개 가능한 상품이 남지 않으면 공급업체도 비공개로 전환됩니다.':
      'The supplier will be unpublished if no publishable products remain.',
  '변경 대상과 영향을 확인했습니다.': 'I reviewed the target and its effects.',
  '단위 변경 적용': 'Apply unit change',
  '영구 삭제': 'Delete permanently',
  '삭제된 요청서': 'Deleted request',
  '상품명·규격 검색': 'Search product or specification',
  '사용 중지 상품 포함': 'Include inactive products',
  '상품명·브랜드 검색': 'Search product or brand',
  '판매 중지 상품 포함': 'Include inactive products',
  "계획 이름 변경": "Rename plan",
  "저장한 계획의 표시만 변경합니다. 이미 만든 구매요청서와 재고 예약은 유지됩니다.":
      "Change only saved plan visibility. Existing purchase requests and stock reservations are preserved.",
  "저장한 구매 계획 관리": "Manage saved purchase plans",
  "계획 검색": "Search plans",
  "보관한 계획": "Archived plans",
  "저장한 계획이 없습니다.": "No saved plans.",
  "불러오기": "Load",
  "구성 수정": "Edit contents",
  "복사해서 만들기": "Create a copy",
  "이름 변경": "Rename",
  "수정 중": "Editing",
  "다른 계획으로 저장": "Save as another plan",
  "수정 연결 해제": "Stop editing saved plan",
  "현재고·예약이 없는 품목 숨기기": "Hide items without stock or reservations",
  "관리 메모 수정": "Edit management note",
  "재고 관리 메모": "Stock management note",
  "보관 위치 등 관리 정보를 적으세요. 수량·단위는 바뀌지 않습니다.":
      "Add storage location or other notes. Quantities and units stay unchanged.",
  "거래처 이름": "Supplier name",
  "담당자·연락처": "Contact details",
  "규격 복제": "Copy specification",
  "앞으로 구매할 때의 선택 상태를 변경합니다. 이미 작성한 요청서와 입고 기록은 유지됩니다.":
      "Change availability for future purchases. Existing requests and receipts are preserved.",
  "초안을 만들 때 선택한 정보입니다. 요청서에서 이후 수정한 내용은 위의 현재 요청서를 확인하세요.":
      "These are the selections when the draft was created. Check the current request above for subsequent edits.",
  "관리": "Manage",
  "처리하지 못했습니다. 새로고침 후 다시 확인해 주세요.":
      "Could not complete. Refresh and check again.",
  "목록 표시만 변경합니다. 재고·금액과 처리 이력은 유지됩니다.":
      "Only list visibility changes. Stock, totals and history are preserved.",
  "보관·복원": "Archive / restore",
  "전달 이력이 없는 초안만 삭제합니다. 기록을 남기려면 보관을 선택하세요.":
      "Only a draft with no delivery history can be deleted. Archive it to keep the record.",
  "초안 삭제": "Delete draft",
  "판매 재개": "Resume selling",
  "새 구매에서 이 상품을 숨깁니다. 기존 구매요청서는 유지됩니다.":
      "Hide this product from new purchases. Existing requests are preserved.",
  "업체가 공개 상태이면 이 상품이 고객에게 다시 표시됩니다. 규격과 가격을 확인해 주세요.":
      "If the business is published, customers will see this product again. Check its specification and price.",
  "공급업체 작업공간": "SUPPLIER WORKSPACE",
  "* 필수 · 나머지는 선택 항목입니다.": "* Required · other fields are optional.",
  "업체명 *": "Business name *",
  "담당자 *": "Contact name *",
  "공개 연락처 *": "Public phone *",
  "소재 지역 *": "Business region *",
  "배송 가능 지역 *": "Delivery regions *",
  "* 필수 · 가격 없이도 견적 요청 상품으로 등록할 수 있습니다.":
      "* Required · products can request a quote without a listed price.",
  "상품 사진 선택 *": "Choose product photo *",
  "상품명 *": "Product name *",
  "대분류 *": "Category *",
  "소분류 *": "Subcategory *",
  "원산지 구분 *": "Origin type *",
  "판매 단위 * (예: box, pack)": "Selling unit * (e.g. box, pack)",
  "판매 단위 1개에 들어 있는 내용량 *": "Contents per selling unit *",
  "내용량 단위 * (예: kg, g, ea)": "Content unit * (e.g. kg, g, ea)",
  "최소 구매 판매단위 수 *": "Minimum selling units *",
  "판매 단위 1개 가격 (선택)": "Price per selling unit (optional)",
  "정정 사유": "Correction reason",
  "사유를 입력하세요.": "Enter a reason.",
  "취소하면 집계에서 제외되고 복원하면 다시 포함됩니다. 판매 단가·원가와 정정 이력은 유지되며 재고는 변경하지 않습니다.":
      "Voided sales are excluded from totals; restoration includes them again. Sale price, cost and history are preserved. Inventory does not change.",
  "처리 사유": "Reason",
  "매출 처리 이력 (최근 100건)": "Sale history (latest 100)",
  "등록": "Created",
  "정정": "Corrected",
  "기준 기록": "Baseline",
  "취소한 매출 보기": "Show voided sales",
  "계획 보관": "Archive plan",
  "계획 복원": "Restore plan",
  "변경 저장": "Save changes",
  "매출 복원": "Restore sale",
  "매출 취소": "Void sale",
  "기록 복원": "Restore record",
  "기록 보관": "Archive record",
  "다시 사용": "Reactivate",
  "추가 중인 재료를 불러오지 못했습니다. 다시 시도해 주세요.":
      "Could not load your ingredient draft. Retry.",
  "임시 저장하지 못했습니다. 연결을 확인하고 다시 시도해 주세요.":
      "Could not save your draft. Check and retry.",
  "재료명과 0보다 큰 수량·단위를 확인해 주세요.":
      "Enter an ingredient and a positive quantity with its unit.",
  "한 번에 추가할 재료 수를 줄여 주세요.": "Add fewer ingredients at a time.",
  "저장 결과를 확인하지 못했습니다. 같은 내용으로 다시 확인하면 중복으로 추가되지 않습니다.":
      "Could not confirm saving. Retry the same submission safely without duplicates.",
  "재료 직접 추가": "Add ingredients",
  "레시피에 없는 재료도 추가할 수 있습니다. 필요한 수량을 입력한 뒤 구매 리스트에서 함께 확인하세요.":
      "Add ingredients beyond your recipes. Enter required quantities and review them together in your purchase list.",
  "필요 수량": "Required quantity",
  "단위": "Unit",
  "규격·브랜드 (선택)": "Size or brand (optional)",
  "봉지·병·팩을 g 또는 ml로 자동 환산하지 않습니다. 실제 포장 규격을 확인해 주세요.":
      "Bags, bottles and packs are not automatically converted to g or ml. Check the actual package size.",
  "쿠팡 상품 찾기": "Find Coupang products",
  "담고 다음 재료 입력": "Add another ingredient",
  "추가 목록에서 빼기": "Remove from draft",
  "저장 결과를 확인하는 동안에는 재료를 수정할 수 없습니다.":
      "Ingredients stay locked while confirming this submission.",
  "저장 결과 다시 확인": "Retry saving",
  "장보기 목록에 추가": "Add to shopping list",
  "다른 상품의 규격을 확인하려면 쿠팡 일반 검색을 이용하세요. 일반 검색은 수익용 제휴 링크가 아니며 상품이 자동 등록되지 않습니다.":
      "Use Coupang search to check other product sizes. General search is not an affiliate link and does not import products automatically.",
  "상품 페이지를 열지 못했습니다.": "Could not open the product page.",
  "쿠팡 일반 검색으로 규격 확인": "Check sizes on Coupang",
  "확인 후 돌아와 필요한 재료명·수량·단위를 입력해 주세요.":
      "Return here after checking, then enter the ingredient, quantity and unit.",
  "목록 수정·재료 추가": "Edit list or add ingredients",
  "구매 리스트 확정됨 · 목록 수정": "List confirmed · Edit list",
  "구매 계속하기": "Continue shopping",
  '구매 담당 권한이 있어야 쿠팡 상품을 열 수 있습니다.': 'Purchasing access is required.',
  '연습용 업소에서는 실제 구매 링크를 열 수 없습니다.':
      'Real purchases are disabled in practice workspaces.',
  '요청서를 승인한 뒤 쿠팡 상품을 확인할 수 있습니다.':
      'Approve the request before opening Coupang products.',
  '이미 전달·입고·취소된 요청입니다. 기존 주문과 입고 내역을 확인하세요.':
      'This request is no longer awaiting purchase. Check its orders and receipts.',
  '구매요청서에서 이용해 주세요.': 'Open this from a purchase request.',
  '쿠팡 상품 확인': 'View Coupang products',
  '최신 권한과 요청서를 확인하지 못했습니다. 다시 확인':
      'Could not check access and the request. Retry',
  '최신 자료 다시 확인': 'Refresh',
  '승인된 요청서': 'Approved request',
  '요청서의 거래처·상품·규격·금액과 다르면 수정 후 다시 승인받으세요. 쿠팡에서 최종 옵션과 배송비를 확인합니다.':
      'If the supplier, product, specification or amount differs, edit and reapprove the request. Check final options and shipping at Coupang.',
  '상품 페이지를 열었습니다. 실제 주문 여부는 쿠팡 주문 내역에서 확인하세요.':
      'Product page opened. Check Coupang order history to confirm an actual order.',
  '확인할 수 있는 재료·수량이 없습니다. 요청서를 다시 확인하세요.':
      'No valid ingredient quantities. Review the request.',
  '상품을 불러오지 못했습니다. 다시 확인': 'Could not load products. Retry',
  '이 재료에 공개된 쿠팡 상품이 없습니다. 관리자에게 상품 등록·공개를 요청해 주세요.':
      'No published Coupang products for this ingredient. Ask an administrator to review the catalog.',
  '이 링크는 쿠팡 파트너스 활동의 일환으로, 이에 따른 일정액의 수수료를 제공받습니다.':
      'We may receive a commission through these Coupang Partners links.',
  '쿠팡 주문 후 요청서에서 ‘전달 완료로 기록’을 선택하고, 수령 후 ‘품목별 입고·반품’에서 실제 수량을 확인하세요. 링크를 열어도 구매 상태와 재고는 바뀌지 않습니다.':
      'After ordering, use “Record sharing” on the request, then record actual quantities under “Item receipts & returns” on delivery. Opening a link does not change purchase status or stock.',
  '요청서로 돌아가기': 'Back to request',
  '요청서의 구매 기준': 'Request purchasing details',
  '상품과 승인 내용이 다르면 먼저 요청서를 수정·재승인하세요. 최종 옵션·가격·배송비는 쿠팡에서 확인합니다.':
      'If this differs from the approval, edit and reapprove the request first. Check final options, price and shipping at Coupang.',
  '거래처·상품·규격·구매량·금액이 승인 내용과 맞는지 확인했습니다.':
      'I checked the supplier, product, size, quantity and amount against the approval.',
  '이미 주문했거나 다른 담당자가 주문 중인 건이 아닌지 확인했습니다.':
      'I checked that this has not already been ordered and no other buyer is ordering it.',
  "전문 도구": "Professional tools",
  "구매처 선택·관리": "Manage stores",
  "상품별 기록": "Items",
  "재료·구매처": "Ingredients & stores",
  "완료한 목록": "Completed lists",
  "목록 확인·완료": "Review & complete",
  "거래처 요청": "Supplier requests",
  "구매처에서 결제한 뒤 실제 구매량을 기록하세요.":
      "Buy at your store, then record the actual quantity.",
  "레시피에서 재료 가져오기": "Add ingredients from recipes",
  "공급업체 공간": "Supplier space",
  "개인 공간": "Personal space",
  "공간을 전환하지 못했습니다. 다시 시도해 주세요.": "Could not switch spaces. Try again.",
  "사용 공간 선택": "Choose space",
  "소속 업소를 불러오는 중": "Loading businesses",
  "소속 업소 다시 불러오기": "Reload businesses",
  "레시피 보관함": "Recipe library",
  "레시피의 인분·배합·원가 관리": "Servings, formulas and recipe costs",
  "전문·공급업체 기능 설정": "Professional & supplier settings",
  "시험 조리용": "For trial cooking",
  "작성 중인 목록": "Draft lists",
  "승인·전달·입고 확인": "Approval, sharing & receipt",
  "완료·취소 내역": "Completed & cancelled",
  "요청서 확인": "View request",
  "구매처 미지정": "Supplier not set",
  "업소 공유 자료": "Shared business records",
  "원가·매출 관리": "Costs & sales",
  "원가와 판매 기록을 확인합니다.": "Review costs and sales records.",
  "업무 요약": "Work overview",
  "식단·메뉴와 진행할 업무를 확인합니다.": "Review meals, menus and pending work.",
  '이 업소의 권한 있는 직원과 공유됩니다. 개인 원본과 사진은 공유되지 않습니다. 판매 메뉴 등록은 메뉴선정 권한자의 검토 후 별도로 진행합니다.':
      'Authorized staff in this business can access the copy. The personal original and photos remain private. A menu approver must separately review it for a sales menu.',
  '가져올 개인 레시피 선택': 'Choose a personal recipe',
  '먼저 레시피를 수집하고 편집 가능한 개인 레시피로 저장해 주세요.':
      'Collect and save an editable personal recipe first.',
  '검토 자료로 가져오기': 'Copy for review',
  '이 업소에 레시피를 저장할 권한이 없습니다.': 'You cannot save recipes to this business.',
  '레시피를 가져오지 못했습니다. 업소 권한과 연결 상태를 확인해 주세요.':
      'Could not copy the recipe. Check business permissions and your connection.',
  '레시피 수집': 'Collect recipes',
  '1. 검색·영상에서 레시피 수집': '1. Collect recipes from search or videos',
  '레시피 검색·수집 열기': 'Open recipe discovery',
  '2. 검토한 레시피를 업소에 가져오기': '2. Copy a reviewed recipe to this business',
  '업소에 가져오려면 레시피 작성 권한과 활성 이용권이 필요합니다. 개인 레시피 수집은 계속할 수 있습니다.':
      'Copying to this business requires recipe editing access and an active plan. You can still collect personal recipes.',
  '개인 레시피': 'Personal recipes',
  '업소 직원에게 공유할 사본을 선택합니다. 판매 메뉴는 자동 등록되지 않습니다.':
      'Select the copy to share with staff. It will not automatically become a sales menu.',
  '레시피 개발': 'Recipe development',
  '맡은 업무에 맞춰 개인 작업실 안내를 보여 드려요.':
      'Your personal studio guidance follows your responsibilities.',
  '판매 메뉴 준비': 'Prepare active menus',
  '비품·소모품은 직접 작성': 'Write a supplies request manually',
  '업무홈': 'Work home',
  '메뉴·레시피': 'Menus & recipes',
  '경영관리': 'Management',
  '업소 책임자': 'Owner',
  '조리·연구': 'Recipe development',
  '조회 권한': 'Read access',
  '업소 접근 권한과 연결 상태를 확인해 주세요.': 'Check business access and your connection.',
  '다시 확인': 'Retry',
  '업소 선택': 'Choose business',
  '이 업소의 권한 있는 직원과 공유하는 자료입니다.':
      'Records shared with authorized staff in this business.',
  '작업 공간 전환': 'Switch work area',
  '작업 공간 선택': 'Choose work area',
  '업소 설정·더보기': 'Business settings & more',
  '연습용 업소 · 실제 주문에 사용하지 마세요.':
      'Practice business · do not use for real orders.',
  '직원 초대와 업무별 접근 권한을 관리합니다.':
      'Invite staff and manage access to business records.',
  '다른 업소로 전환하거나 초대받은 업소에 참여합니다.': 'Switch businesses or join an invitation.',
  '개인 작업실': 'Personal studio',
  '개인 자료를 사용하는 공간으로 이동합니다.': 'Open your private tools and records.',
  '사용자 영역 선택': 'Choose user area',
  '일반사용자·업소·공급업체 화면을 설정합니다.':
      'Choose home cook, professional or supplier views.',
  '로그인과 계정 정보를 관리합니다.': 'Manage your sign-in and account.',
  '메뉴에서 구매까지, 같은 업소 자료로 이어가세요.':
      'Continue from menus to purchasing in one shared business.',
  '레시피 개발 → 시험 조리·출시 승인 → 메뉴 등록 → 구매 준비 → 승인·전달 → 입고 확인':
      'Develop recipes → trial & launch approval → menus → purchase preparation → approval & sharing → receipt',
  '구매 승인 대기 확인': 'Review purchase approvals',
  '요청 내용을 확인하고 승인하거나 초안으로 돌려보냅니다.':
      'Review requests, approve or return them to draft.',
  '메뉴·레시피에서 구매 준비': 'Prepare purchases from recipes',
  '판매 메뉴 또는 개발 레시피를 선택하고 준비 인분을 입력합니다.':
      'Choose active menus or development recipes and enter servings.',
  '판매 메뉴판 관리': 'Manage menus',
  '승인된 레시피 버전과 판매 메뉴를 연결합니다.': 'Link approved recipe revisions to your menus.',
  '입고는 담당자가 실제 내용을 확인해 기록합니다. 조리 사용량과 재고는 자동 차감하지 않습니다.':
      'Record receipts after checking deliveries. Cooking use and stock are not automatically deducted.',
  '상품·가격': 'Products & prices',
  '거래조건': 'Trade terms',
  '상품 규격과 가격을 관리하세요.': 'Manage product sizes and prices.',
  '배송과 주문 조건을 확인하세요.': 'Review delivery and order terms.',
  '무료배송 기준': 'Free delivery from',
  '가격: 견적 필요': 'Price: request a quote',
  '서울': 'Seoul',
  '어느 공간에서 일할까요?': 'Choose your work area',
  '직원과 함께하는 업무는 소속 업소에서, 혼자 연구하는 자료는 개인 작업실에서 관리하세요.':
      'Use your business for shared work and your personal studio for private research.',
  '소속 업소': 'Your businesses',
  '로그인하고 소속 업소 확인': 'Sign in to see your businesses',
  '소속 업소를 불러오지 못했습니다.': 'Could not load your businesses.',
  '참여한 업소가 없습니다. 업소를 만들거나 초대 코드로 참여하세요.':
      'Create a business or join one using your invitation code.',
  '공동 메뉴·레시피 · 구매·입고 · 경영관리':
      'Shared menus, recipes, purchasing and management',
  '업소 만들기·초대 참여': 'Create or join a business',
  '내 레시피·배합·원가·구매 기록. 업소에 자동 공유되지 않습니다.':
      'Your recipes, formulas, costs and purchases. Not automatically shared with staff.',
  '소속 업소에서 공동 업무하기': 'Open shared business work',
  '공급업체 관리 · 공개한 업체·상품 정보는 회원에게 표시됩니다.':
      'Supplier management · published business and products are visible to members.',
  '개인 작업실 · 이 계정의 자료이며 업소에 자동 공유되지 않습니다.':
      'Personal studio · these records are not automatically shared with your business.',
  '업소에서는 메뉴·레시피·구매를 함께, 개인 작업실에서는 나의 연구를 관리해요.':
      'Manage shared menus, recipes and purchasing, or use your personal research studio.',
  '인분·배합': 'Servings & formula',
  '작업공간': 'Work areas',
  '개인 구매': 'My purchases',
  '개인 연구': 'My research',
  '개인 작업실 도구': 'Personal studio tools',
  '이 영역의 다른 도구': 'Other tools in this area',
};
