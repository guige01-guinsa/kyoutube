const affiliateUiTranslations = <String, String>{
  '클립보드에서 붙여넣기': 'Paste from clipboard',
  '중복 확인 다시 시도': 'Retry duplicate check',
  '중복 확인 필요': 'Duplicate check required',
  '가져올 상품이 없습니다. 제목 행과 상품 목록을 함께 입력해 주세요.':
      'There are no products to import. Include the header row and product list.',
  '클립보드가 비어 있습니다. 엑셀 표나 상품 목록을 먼저 복사해 주세요.':
      'The clipboard is empty. Copy an Excel table or product list first.',
  '클립보드를 읽지 못했습니다. 목록 입력란을 누르고 Ctrl+V 또는 붙여넣기를 사용해 주세요.':
      'Could not read the clipboard. Select the list field and use Ctrl+V or Paste.',
  '선택한 파일을 읽지 못했습니다. 파일을 다시 선택하거나 표를 복사해 목록 입력란에 붙여넣어 주세요.':
      'Could not read the selected file. Select it again, or copy the table and paste it into the list field.',
  '목록은 읽었지만 서버에서 중복 확인을 완료하지 못했습니다. 연결을 확인하고 미리보기를 다시 실행해 주세요.':
      'The list was read, but the server could not finish checking duplicates. Check your connection and run the preview again.',
  '이 CSV는 한글 CP949 형식입니다. 엑셀에서 CSV UTF-8로 저장하거나 XLSX 파일을 선택해 주세요. 표를 제목 행과 함께 복사해 붙여넣어도 됩니다.':
      'This CSV uses the Korean CP949 encoding. Save it as CSV UTF-8 in Excel or select an XLSX file. You can also copy and paste the table with its header row.',
  '파일이나 붙여넣은 내용이 너무 큽니다. 2MB 이하로 나누어 가져와 주세요.':
      'The file or pasted content is too large. Split it into parts of 2 MB or less.',
  '한 번에 상품 2,000개까지 가져올 수 있습니다. 목록을 나누어 주세요.':
      'You can import up to 2,000 products at a time. Split the list into smaller parts.',
  '첫 행의 상품명·제휴 링크 제목을 확인해 주세요. 같은 제목의 열은 한 번만 사용합니다.':
      'Check the product title and affiliate link headers in the first row. Use each column header only once.',
  'CSV의 따옴표가 맞지 않습니다. 엑셀에서 CSV UTF-8로 다시 저장하거나 표를 복사해 붙여넣어 주세요.':
      'The CSV has unmatched quotation marks. Save it again as CSV UTF-8 in Excel, or copy and paste the table.',
  '파일이나 표를 읽지 못했습니다. XLSX 또는 CSV UTF-8 파일을 사용하거나 제목 행을 포함한 표를 붙여넣어 주세요.':
      'The file or table could not be read. Use an XLSX or CSV UTF-8 file, or paste the table including its header row.',
  '재료가 비어 있으면 상품명을 사용합니다. 엑셀 표는 제목 행부터 복사해 붙여넣을 수 있습니다.':
      'If the ingredient is blank, the product title is used. You can copy and paste an Excel table starting with its header row.',
  '재고 연결을 다시 선택해 주세요.': 'Select the stock link again.',
  '재고 다시 불러오기': 'Reload stock',
  '숨김': 'Hidden',
  '허용': 'Allowed',
  '앱 공개': 'App visibility',
  '웹 공개': 'Web visibility',
  '제휴 링크': 'Affiliate link',
  '판매 규격': 'Pack size',
  '권한이 확인되었습니다. 입력 내용과 연결 상태를 확인한 뒤 다시 시도해 주세요.':
      'Access confirmed. Check the input and connection, then retry.',
  "로그인 후 계속할 수 있습니다.": "Sign in to continue.",
  "2단계 인증을 완료해 주세요.": "Complete two-step verification.",
  "권한 확인 중입니다.": "Checking access…",
  "관리자 권한이 필요합니다. 권한이 변경됐다면 다시 확인해 주세요.":
      "Administrator access is required. Refresh your access if it changed.",
  "로그인 후 계속": "Sign in & continue",
  "인증 후 계속": "Verify & continue",
  "권한 다시 확인": "Check access again",
  "인증 이메일을 다시 보냈습니다. 받은편지함과 스팸함을 확인해 주세요.":
      "Verification email resent. Check your inbox and spam folder.",
  "인증 이메일을 보내지 못했습니다. 연결 상태를 확인하고 다시 시도해 주세요.":
      "Could not send verification email. Check your connection and retry.",
  "인증 이메일 다시 보내기": "Resend verification email",
  "재고 등록·입고": "Add stock item & receive",
  "조리 완료는 저장되었습니다. 구매 준비 내역에서 예약을 다시 확인해 주세요.":
      "Cooking completion saved. Reopen preparation details to review reservations.",
  "재고 품목": "Stock item",
  "판매 메뉴 설정": "Set up selling menus",
  "상품·규격 추가": "Add product / pack",
  "재고 품목 추가": "Add stock item",
  "레시피 시험 조리·승인 확인": "Review recipe trial & approval",
  "재료명·규격·재고 단위가 같으면 기존 품목을 사용합니다. 실제 관리 단위로 등록하세요. 소유자는 환산 영향을 확인한 뒤 단위를 변경할 수 있습니다.":
      "Matching names, specifications and units reuse an existing item. Choose the unit you track. Owners can change units after reviewing the conversion.",
  "입고를 기록하려면 재고 품목을 먼저 등록해 주세요.": "Add a stock item to record this receipt.",
  "재고 품목 등록 후 계속": "Add stock item & continue",
  "등록된 항목이 없습니다.": "No registered items.",
  "검색 결과가 없습니다. 검색어를 바꾸거나 지워 주세요.": "No matches. Change or clear the search.",
  "새로 등록": "Add new",
  "같은 제휴 링크가 등록되어 있습니다. 아래에서 기존 상품을 확인해 주세요.":
      "This affiliate link is already registered. Review the existing product below.",
  "다른 변경 사항이 있습니다. 최신 내용과 비교한 뒤 계속할 수 있습니다.":
      "The product changed. Compare the latest details before continuing.",
  "기존 상품을 찾을 수 없습니다. 목록을 다시 확인해 주세요.":
      "Could not find the existing product. Check the list again.",
  "등록된 상품 확인": "Review existing product",
  "변경 내용 비교": "Compare changes",
  "휴지통에 있는 상품입니다. 복원 후 수정할 수 있습니다.":
      "This product is in trash. Restore it to edit.",
  "입력 유지·돌아가기": "Keep input & go back",
  "내 입력으로 이어서 검토": "Continue reviewing my input",
  "복원 후 편집": "Restore & edit",
  "최신 상품 편집": "Edit latest product",
  "최신 상품을 확인하지 못했습니다. 연결·권한을 확인하고 다시 시도해 주세요.":
      "Could not load the latest product. Check your connection and access, then retry.",
  "기존 상품 확인": "Review existing product",
  "최신 내용과 비교": "Compare latest details",
  "확인 중 기록이 바뀌었거나 삭제되었습니다. 다시 확인을 눌러 최신 영향을 검토해 주세요.":
      "The record changed or was deleted. Review the latest effects again.",
  "관련 자료 확인": "Review related records",
  "연결된 구매요청서": "Linked purchase request",
  "관련 예약·요청서 확인": "Review reservations / requests",
  "내 거래처 등록·직접 요청서 작성": "Add my supplier & write a request",
  "최신 상품": "Latest product",
  "내 입력": "My input",
  "검토 메모": "Review note",
  "묶음 수": "Units per order",
  "이 재료에 공개된 쿠팡 상품이 없습니다.":
      "No published Coupang products for this ingredient.",
  "쿠팡에서 다른 상품 찾기": "Find other products on Coupang",
  "일반 검색은 제휴 링크가 아닙니다. 승인된 규격·수량을 확인하고 실제 구매 내역을 기록하세요.":
      "General search is not an affiliate link. Check approved specifications and quantities and record the actual purchase.",
  "승인된 상품이 변경되었습니다. 요청서를 수정하고 다시 승인해 주세요.":
      "The approved product changed. Edit and reapprove the request.",
  "쿠팡 일반 검색으로 이동합니다. 제휴 링크가 아니며 주문·입고는 자동 기록되지 않습니다.":
      "This opens general Coupang search, not an affiliate link. Orders and receipts are not recorded automatically.",
  "승인된 거래처·규격·구매량·금액을 확인했고, 조건이 다르면 요청서를 수정·재승인하겠습니다.":
      "I reviewed the approved purchasing terms and will edit and reapprove the request if they differ.",
  "쿠팡을 열지 못했습니다. 다시 시도해 주세요.": "Could not open Coupang. Retry.",
  "일반 검색은 제휴 링크가 아닙니다. 판매 규격을 확인하고 돌아와 실제 구매량을 기록하세요.":
      "General search is not an affiliate link. Check the package size and return to record your actual purchase.",
  "제휴 상품이 없습니다. 품명·수량·단위를 직접 입력하고, 요청서 승인 후 쿠팡에서 다른 상품을 찾을 수 있습니다.":
      "No affiliate product. Enter the name, quantity and unit. After approval, you can search other Coupang products.",
  "품명 후보 찾기": "Find matching names",
  "후보를 불러오지 못했습니다. 직접 입력하거나 다시 조회해 주세요.":
      "Could not load suggestions. Enter a name or retry.",
  "다시 조회": "Retry",
  "일치하는 등록 품명이 없습니다. 입력한 이름을 그대로 사용할 수 있습니다.":
      "No registered names match. You can use the name you entered.",
  "이전 결과": "Previous",
  "다음 결과": "More results",
  "입력한 이름 사용": "Use entered name",
  '개': 'each',
  '묶음': 'set',
  '쿠팡': 'Coupang',
  '추가 필요 1 1 → 구매 총량 1 1': 'Additional need 1 1 → total purchase 1 1',
  '구매량: 1 1': 'Purchase quantity: 1 1',
  '단가: 미정': 'Unit price: not set',
  '쿠팡 상품이나 판매 규격이 변경되었습니다. 목록에서 상품·수량을 다시 확인해 주세요.':
      'The Coupang product or sale packaging changed. Review the product and quantity in the list.',
  '쿠팡 품목은 공급업체 품목과 별도 요청서로 저장해 주세요. 메뉴 구매 목록에서는 자동으로 나누어 생성합니다.':
      'Save Coupang items in a separate request from supplier items. Menu purchase lists split them automatically.',
  '최신 상품을 확인하지 못했습니다. 상품을 다시 불러온 뒤 확인해 주세요.':
      'Could not verify the latest product. Reload products and try again.',
  '쿠팡 상품 선택': 'Choose a Coupang product',
  '쿠팡 상품 다시 불러오기': 'Reload Coupang products',
  '연결된 쿠팡 상품 준비 중 · 기존 구매 방법을 이용할 수 있습니다.':
      'Matching Coupang products are not ready. You can use your existing purchase method.',
  '쿠팡 제휴 상품': 'Coupang affiliate product',
  '상품이 변경되었거나 공개가 중단되었습니다. 다시 선택해 주세요.':
      'The product changed or is no longer published. Select it again.',
  '권장 구매 수량: 1 1': 'Suggested order quantity: 1 1',
  '판매 규격 또는 필요량·단위 확인 후 자동 계산할 수 있습니다.':
      'Verify the sale packaging, required quantity and unit to calculate automatically.',
  '구매 수량 줄이기': 'Decrease order quantity',
  '구매 수량 늘리기': 'Increase order quantity',
  '구매 총량: 1 1': 'Total purchase quantity: 1 1',
  '여유량': 'Surplus',
  '상품 변경': 'Change product',
  '기존 구매량으로 돌아가기': 'Restore original purchase quantity',
  '쿠팡에서 최종 옵션·수량·가격을 확인하세요. 수령 후 실제 구매량을 기록합니다.':
      'Confirm the final option, quantity and price on Coupang. Record the actual quantity after delivery.',
  '상품·수량을 저장하고 요청서를 승인한 뒤 구매할 수 있습니다.':
      'Save the product and quantity, then approve the request before purchasing.',
  '판매 규격의 내용량·묶음 수·옵션명을 확인해 주세요.':
      'Check the pack content, inner pack count and option name.',
  '구매량 자동 계산용 판매 규격 (선택)': 'Sale packaging for quantity calculation (optional)',
  '예: 500g × 2봉 상품은 내용량 500, 단위 g, 묶음 수 2입니다. 실제 판매 옵션을 확인하세요.':
      'For 500g × 2 bags, enter content 500, unit g and inner pack count 2. Verify the actual sale option.',
  '개별 포장 내용량 (비우면 자동 계산 안 함)':
      'Content per inner pack (leave blank to skip calculation)',
  '한 번 주문에 포함된 포장 수': 'Inner packs per order unit',
  '판매 단위 이름 (봉·병·묶음 등)': 'Sale unit label (bag, bottle, set)',
  '확인한 판매 옵션명': 'Verified sale option name',
  "쿠팡에서 검색": "Search on Coupang",
  "이 재료에 연결된 쿠팡 추천 상품은 아직 준비 중입니다. 아래에서 직접 검색할 수 있어요.":
      "Coupang recommendations for this ingredient are not ready yet. You can search below.",
  "상품 등록·공개 도우미": "Product publishing assistant",
  "미완료 항목 확인부터 실제 구매 화면 확인까지":
      "Review unfinished steps and check the live purchase screen",
  "실제 노출 확인": "Check live visibility",
  "현재 기기에서 회원에게 공개되는 상품을 조회합니다. 초안이나 만료된 상품은 표시하지 않습니다.":
      "Shows products available to customers on this platform. Drafts and expired products are excluded.",
  "조회·새로고침": "Search / refresh",
  "선택한 상품이 표시되지 않습니다. 공개 상태, 현재 기기의 게시 허용, 확인 만료일과 재료 이름을 확인하세요.":
      "The selected product is not visible. Check publication, placement permission for this platform, review expiry and ingredient names.",
  "등록부터 공개 확인까지": "From registration to live display",
  "① 링크 등록 → ② 실제 상품·규격 확인 → ③ 게시 근거와 공개 설정 → ④ 실제 노출 확인\n검토가 필요한 초안부터 표시합니다. API 키가 없어도 발급받은 링크를 직접 등록할 수 있습니다.":
      "1. Add a link → 2. Verify the product and size → 3. Confirm placement and publish → 4. Check live visibility\nDrafts are shown first. You can enter an issued link without API keys.",
  "제휴 상품 관리": "Affiliate offers",
  "제휴 상품 추가": "Add affiliate offer",
  "제휴 상품": "Affiliate offers",
  "제휴 상품 다시 불러오기": "Retry affiliate offers",
  "쿠팡 API 연결 준비가 필요합니다. 운영자에게 연결 설정을 요청하세요.":
      "Coupang API setup is required. Ask the operator to configure it.",
  "관리자 2단계 인증을 완료한 뒤 다시 시도하세요.":
      "Complete administrator two-step verification and try again.",
  "관리자 계정으로 다시 로그인하세요.": "Sign in again as an administrator.",
  "쿠팡 조회 한도에 도달했습니다. 잠시 후 다시 시도하세요. 일일 한도라면 다음 날 이용해 주세요.":
      "The request limit was reached. Try later, or tomorrow if the daily limit was reached.",
  "쿠팡에서 요청을 승인하지 않았습니다. 파트너스 API 사용 권한과 연결 설정을 확인하세요.":
      "Coupang declined the request. Check Partners API access and connection settings.",
  "검색어 또는 쿠팡 상품 상세 주소를 확인하세요.": "Check the keyword or Coupang product URL.",
  "쿠팡 정보를 불러오지 못했습니다. 다시 시도하거나 기존 발급 링크를 직접 등록하세요.":
      "Could not load Coupang data. Retry or add an existing issued link manually.",
  "쿠팡 상품 검색·링크 생성": "Coupang products and links",
  "상품을 검색하거나 쿠팡 상품 상세 주소를 붙여 넣으세요. 생성한 링크는 편집기에서 확인 후 저장합니다.":
      "Search products or paste a Coupang product URL. Review the generated link in the editor before saving.",
  "재료·상품 검색어": "Ingredient / product keyword",
  "쿠팡 상품 검색": "Search Coupang",
  "쿠팡 상품 상세 주소": "Coupang product URL",
  "주소로 제휴 링크 생성": "Create affiliate link from URL",
  "검색 결과가 없습니다. 다른 검색어를 입력하세요.": "No results. Try another keyword.",
  "가격은 조회 시점의 참고 정보입니다. 옵션·규격·최종 가격과 배송비는 쿠팡에서 다시 확인하세요.":
      "Prices are a snapshot. Check options, size, final price and shipping on Coupang.",
  "링크 생성 후 검토": "Generate link and review",
  "상품 태그 영상 보기": "Watch shoppable video",
  "제휴 상품 열기": "Open affiliate offer",
  "제휴 상품을 불러오지 못했습니다. 일반 검색은 계속 사용할 수 있습니다.":
      "Affiliate offers could not be loaded. Regular search is still available.",
  "이 링크를 통한 구매로 레시피 스카우트 운영자가 수수료를 받을 수 있습니다. 최종 가격과 배송비는 판매처에서 확인하세요.":
      "The Recipe Scout operator may earn a commission from purchases through this link. Check final prices and shipping at the retailer.",
  "영상의 상품 태그를 통한 구매로 채널 운영자가 수수료를 받을 수 있습니다.":
      "The channel operator may earn a commission from purchases through product tags in the video.",
  "제휴사 링크 등록부터 시작하세요.": "Start by adding an issued affiliate link.",
  "네이버 쇼핑 커넥트": "Naver Shopping Connect",
  "YouTube Shopping 영상": "YouTube Shopping video",
  "재료 이름·별칭 (쉼표로 구분)": "Ingredient names / aliases (comma separated)",
  "제휴 링크 또는 상품 태그 영상 주소": "Issued affiliate link or tagged video URL",
  "사용 허용 근거·확인일": "Permission evidence / review date",
  "모바일 앱 게시 가능 확인": "Mobile app placement verified",
  "웹 게시 가능 확인": "Web placement verified",
  "초안·숨김": "Draft / hidden",
  "링크와 입력 항목을 확인해 주세요.": "Check the link and required fields.",
  "저장하지 못했습니다. 관리자 2단계 인증·입력값을 확인하거나 새로고침 후 다시 시도하세요.":
      "Could not save. Check administrator MFA and the fields, or refresh and retry.",
  "승인된 게시 위치와 근거가 있어야 공개할 수 있습니다. 저장할 때마다 30일 후 재확인하도록 설정됩니다.":
      "Publishing requires verified placement permission and evidence. Each save schedules a review in 30 days.",
  "가입·연결 순서": "Setup steps",
  "공식 안내 열기": "Open official guide",
  "주소를 열지 못했습니다. 다시 시도해 주세요.": "Could not open the link. Please retry.",
  "만료됨·숨김": "Expired / hidden",
  "쿠팡 파트너스": "Coupang Partners",
  "식자재 분류": "Ingredient category",
  "상품 브랜드": "Product brand",
  "관리 번호": "Reference number",
  "실제 상품 확인": "Check linked product",
  "연결된 상품과 규격을 직접 확인했습니다.": "I checked the linked product and package size.",
  "목록 가져오기": "Import catalog",
  "상품·재료·분류 검색": "Search products, ingredients or categories",
  "전체 상품": "All products",
  "휴지통": "Trash",
  "선택 공개": "Publish selected",
  "공개 중단": "Hide offers",
  "휴지통으로 이동": "Move to trash",
  "복원": "Restore",
  "처리 완료": "Completed",
  "실패": "Failed",
  "선택한 상품을 휴지통으로 이동합니다. 기존 레시피와 구매 기록은 유지됩니다.":
      "Move selected offers to trash. Existing recipes and purchase records are preserved.",
  "초안으로 복원합니다. 확인 후 다시 공개하세요.":
      "Restore as drafts. Review before publishing again.",
  "선택한 상품에 적용합니다. 공개 조건을 충족하지 못한 상품은 변경되지 않습니다.":
      "Apply to selected offers. Offers that fail publication checks will not be changed.",
  "실패한 항목은 새로고침 후 상태와 공개 조건을 확인해 주세요.":
      "For failed items, refresh and check their status and publication requirements.",
  "현재 페이지 모두 선택": "Select current page",
  "표시할 상품이 없습니다.": "No offers to display.",
  "불러오지 못했습니다. 다시 시도해 주세요.": "Could not load. Please retry.",
  "더 불러오기": "Load more",
  "가져오지 못했습니다. 파일 형식·크기와 관리자 인증을 확인해 주세요.":
      "Could not import. Check the file format, size and administrator authentication.",
  "선택 항목 등록": "Save selected items",
  "선택한 항목만 초안으로 저장합니다. 기존 상품을 선택했다면 해당 내용을 교체하고 공개를 중단합니다.":
      "Save only selected items as drafts. Selected existing offers will be replaced and hidden.",
  "응답을 확인하지 못했습니다. 목록을 다시 불러와 저장 여부를 확인한 뒤 재시도하세요.":
      "The result could not be confirmed. Reload the list to check what was saved before retrying.",
  "저장 완료": "Saved",
  "중복 링크": "Duplicate link",
  "수정 충돌": "Edit conflict",
  "휴지통 상품": "Offer in trash",
  "입력 오류": "Invalid fields",
  "목록 내 중복": "Duplicate in this list",
  "기존 상품 수정": "Update existing offer",
  "신규 등록": "New offer",
  "TXT·CSV·TSV·XLSX, 최대 2MB·1,000행. 엑셀은 첫 번째 시트를 읽습니다.":
      "TXT, CSV, TSV or XLSX: up to 2 MB and 1,000 rows. Only the first Excel worksheet is read.",
  "TXT·CSV·TSV·XLSX, 최대 2MB·2,000행. 엑셀은 첫 번째 시트를 읽습니다.":
      "TXT, CSV, TSV or XLSX: up to 2 MB and 2,000 rows. Only the first Excel worksheet is read.",
  "상품명과 제휴 링크는 필수입니다. 같은 링크는 중복 확인하며 기존 상품은 직접 선택해야 수정됩니다.":
      "Product name and affiliate link are required. Existing links are checked for duplicates; select existing offers explicitly to update them.",
  "목록 붙여넣기": "Paste catalog rows",
  "CSV를 만들기 어렵다면 아래에 한 줄씩 붙여넣으세요. 재료명 | 상품명 | 제휴 링크 순서이며, 상품명 | 제휴 링크만 입력해도 됩니다.":
      "If creating a CSV is difficult, paste one line at a time below. Use ingredient | product name | affiliate link, or product name | affiliate link.",
  "붙여넣은 내용을 확인해 주세요. 한 줄에 재료명·상품명·제휴 링크를 | 로 구분해 입력합니다.":
      "Check the pasted text. On each line, separate ingredient, product name and affiliate link with |.",
  "파일 선택": "Choose file",
  "빠른 붙여넣기 미리보기": "Preview quick paste",
  "중복 확인·미리보기": "Check duplicates / preview",
  "신규 항목 모두 선택": "Select all new items",
  "선택 해제": "Clear selection",
  "쿠팡에서 구매": "Shop on Coupang",
  "유사 상품입니다. 재료의 종류·부위와 판매 규격을 확인한 뒤 구매해 주세요.":
      "This is a similar product. Check the ingredient type, cut and package size before buying.",
  "1개의 쿠팡 제휴 상품이 있습니다. 판매 규격을 비교해 선택해 주세요.":
      "1 Coupang affiliate product is available. Compare package sizes and choose one.",
  "쿠팡 제휴 상품이 있습니다. 판매 규격을 확인해 선택해 주세요.":
      "A Coupang affiliate product is available. Check the package size and choose it.",
  "상품 1개 중 선택": "Choose from 1 product",
  "상품 확인·선택": "Review and choose product",
  "이 링크는 쿠팡 파트너스 활동의 일환으로, 이에 따른 일정액의 수수료를 제공받습니다. 최종 가격과 배송비는 쿠팡에서 확인하세요.":
      "This is a Coupang Partners affiliate link. We receive a commission from qualifying purchases. Check final prices and shipping on Coupang.",
  "같은 제휴 링크가 이미 등록되어 있습니다. 기존 상품이나 휴지통을 확인해 주세요.":
      "This affiliate link already exists. Check existing offers or trash.",
  "다른 변경 사항이 있습니다. 닫은 뒤 새로고침하고 다시 수정해 주세요.":
      "This offer changed elsewhere. Close, refresh and edit again.",
  "제휴 링크를 변경하면 초안으로 저장됩니다. 저장 후 다시 열어 검토·공개해 주세요.":
      "Changing the affiliate link saves a draft. Reopen after saving to review and publish.",
  '쿠팡 상품과 판매 규격을 먼저 확인할 수 있도록 상품 정보를 수정해 주세요.':
      'Edit the product details so the Coupang product and package size can be checked first.',
  '쿠팡 상품과 이미지 확인': 'Verify Coupang product and image',
  '같은 상품과 판매 규격인지 사진·상품명을 확인하고 선택하세요. 선택한 쿠팡 사진이 저장되고 장보기에 공개됩니다.':
      'Check the product name and photo to confirm the item and package size. The selected Coupang photo will be saved and published in Shopping.',
  '장보기에 공개할까요?': 'Publish to Shopping?',
  '확인하면 쿠팡 상품 사진을 저장하고 앱 장보기 목록에 공개합니다. 발급받은 제휴 링크는 그대로 유지되며 30일 뒤 다시 확인하도록 설정됩니다.':
      'Confirm to save the Coupang product photo and publish it in the app shopping list. The issued affiliate link stays unchanged, and the offer will need review again in 30 days.',
  '확인·공개': 'Confirm and publish',
  '쿠팡 검색 상품·사진을 관리자 확인함': 'Coupang search result and photo verified by admin',
  '쿠팡 상품 사진 저장 및 앱 장보기 노출을 확인했습니다':
      'Coupang product photo saved and confirmed visible in app Shopping',
  '상품과 사진은 저장·공개했지만 앱 장보기에서 즉시 확인하지 못했습니다. 공개 상태와 연결을 확인해 주세요.':
      'The product and photo were saved and published, but could not be confirmed in app Shopping yet. Check publication status and connectivity.',
  '쿠팡 상품 사진 저장 및 앱 장보기 노출을 확인했습니다.':
      'Coupang product photo saved and confirmed visible in app Shopping.',
  '저장은 완료했지만 장보기 노출을 확인하지 못했습니다.':
      'Saved successfully, but Shopping visibility could not be confirmed.',
  '쿠팡 파트너스 API 연결 설정이 필요합니다.': 'Coupang Partners API setup is required.',
  '관리자 2단계 인증 후 다시 시도해 주세요.':
      'Complete administrator two-step verification and try again.',
  '관리자 계정으로 다시 로그인해 주세요.': 'Sign in again as an administrator.',
  '쿠팡 조회 한도에 도달했습니다. 잠시 후 다시 시도해 주세요.':
      'The Coupang lookup limit was reached. Please try again later.',
  '사진이 포함된 쿠팡 상품을 찾지 못했습니다. 공개하지 않았습니다.':
      'No Coupang product with a photo was found. Nothing was published.',
  '쿠팡 상품을 확인하지 못했습니다. 연결 상태를 확인한 뒤 다시 시도해 주세요.':
      'Could not verify the Coupang product. Check your connection and try again.',
  '저장하지 못했습니다. 관리자 권한과 상품 정보를 확인한 뒤 다시 시도해 주세요.':
      'Could not save. Check administrator access and product details, then try again.',
  '쿠팡 상품 확인·장보기 공개': 'Verify Coupang product and publish to Shopping',
  '쿠팡 상품 사진': 'Coupang product photo',
};

const affiliateSetupSteps = <(String, String, String)>[
  (
    "쿠팡: 파트너스에서 발급한 링크를 등록하세요. 상품·규격과 앱·웹 게시 위치를 확인한 뒤 공개하세요. 목록 가져오기는 초안으로만 저장됩니다.",
    "Coupang: register issued Partners links. Verify products, package sizes and app/website placement before publishing. Imports are saved as drafts.",
    "https://partners.coupang.com"
  ),
  (
    "1. 네이버: 크리에이터로 가입하고 스페이스를 만드세요. 가입 과정에서 지원 채널 연결을 요구하면 본인 채널을 사용하세요. 레시피 스카우트 앱·웹의 등록 가능 여부와 실적 인정은 다음 단계에서 별도로 확인합니다.",
    "1. Naver: register as a creator and create a space. If enrollment requires a supported channel, use your own. Separately confirm Recipe Scout app/website registration and purchase attribution in the next step.",
    "https://help.naver.com/service/30027/contents/23014?osType=COMMONOS"
  ),
  (
    "2. 네이버: 고객센터에 레시피 스카우트 앱·웹의 상품 링크 게시와 실적 인정 여부를 확인하세요. 확인 전에는 상품을 초안으로만 저장하세요.",
    "2. Naver: confirm app and website link placement and attribution with support. Keep offers in draft until confirmed.",
    "https://help.naver.com/service/30027/contents/24105?osType=COMMONOS"
  ),
  (
    "3. 네이버: 쇼핑 커넥트 → 상품 찾기 → 링크 발급 → 링크 복사. 실제 발급 링크와 재료 별칭을 등록하고 승인된 게시 위치만 선택하세요.",
    "3. Naver: Shopping Connect → find products → issue link → copy link. Register the issued link and ingredient aliases, selecting only approved placements.",
    "https://help.naver.com/service/30027/contents/24104?osType=COMMONOS"
  ),
  (
    "4. 구글: YouTube Studio → 수익 창출에서 Shopping 참여 자격을 확인하세요. 가입 후 본인 영상에 상품 태그를 추가하고 해당 영상 주소를 등록하세요. Google 쇼핑 검색 자체에는 수수료가 연결되지 않습니다.",
    "4. Google: check Shopping eligibility under Earn in YouTube Studio. After joining, tag products in your own video and register its URL. Google Shopping search itself does not earn a referral commission.",
    "https://support.google.com/youtube/answer/13376398?hl=ko"
  ),
  (
    "5. 공개 후 장보기의 구매처 찾기에서 재료별 제휴 상품을 확인하세요. 수익은 네이버 또는 YouTube Studio의 확정 실적으로 확인합니다. 클릭·수동 구매 기록은 수익이 아닙니다.",
    "5. After publishing, check matching offers in Find a store. Verify confirmed earnings in Naver or YouTube Studio. Clicks and manual purchase records are not earnings.",
    "https://support.google.com/youtube/answer/12257682?hl=ko"
  ),
];
