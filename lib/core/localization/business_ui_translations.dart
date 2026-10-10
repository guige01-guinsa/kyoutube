// Shared business and duty-based workspace labels.
const businessUiTranslations = <String, String>{
  "구매 담당 기본값": "Purchasing preset",
  "조리 담당 기본값": "Cooking preset",
  "경영 담당 기본값": "Management preset",
  "기본값을 선택한 뒤 필요한 권한을 추가·해제하세요.":
      "Choose a preset, then add or remove individual permissions.",
  "레시피·식단 조회": "View recipes and meal plans",
  "레시피·식단 수정": "Edit recipes and meal plans",
  "구매·입고 조회": "View purchasing and receipt",
  "구매 작성·전달·입고 기록": "Edit purchases, confirm sharing and receipt",
  "원가·판매가·매출 조회": "View costs, prices and sales",
  "원가·판매가·매출 수정": "Edit costs, prices and sales",
  "구매 승인·수정 요청": "Approve purchases or request changes",
  "업소": "Business",
  "직원 초대": "Staff invited",
  "직원 권한 수정": "Edit staff permissions",
  "초대할 직원 이메일": "Staff email address",
  "이 코드를 초대한 직원에게 전달해 주세요. 24시간 동안 한 번 사용할 수 있고, 지정한 이메일로만 참여할 수 있습니다.":
      "Give this code to the invited staff member. It expires in 24 hours, works once and is bound to their email.",
  "초대 코드 복사": "Copy invitation code",
  "조회 권한을 최소 한 개 선택해 주세요.": "Select at least one read permission.",
  "이 직원의 업소 접근 권한을 해제할까요? 저장된 공동 자료와 작업 이력은 남습니다.":
      "Remove this person’s access? Shared records and work history remain.",
  "사장만 직원 권한을 관리할 수 있습니다.": "Only the owner can manage staff permissions.",
  "직원·권한 관리": "Staff & permissions",
  "직원 초대하기": "Invite staff",
  "구매 승인 후 전달하기": "Require approval before sharing",
  "켜면 구매 작성자와 승인 권한자의 확인 단계를 구분합니다.":
      "When enabled, purchases pass through an approval step.",
  "앞으로 작성할 구매요청에 승인 단계를 사용할까요?": "Require approval for draft purchases?",
  "구매 담당자가 승인 대기 없이 요청서를 확정할 수 있게 할까요?":
      "Allow purchasers to finalize drafts without waiting for approval?",
  "참여 직원": "Members",
  "사장 · 전체 권한": "Owner · full access",
  "참여 중": "Active",
  "접근 해제됨": "Access removed",
  "권한 수정·복구": "Edit or restore access",
  "접근 해제": "Remove access",
  "직원·권한 변경 이력": "Staff access history",
  "최근 50건 · 사장만 확인": "Latest 50 changes · owner only",
  "직원 참여": "Staff joined",
  "권한 변경·복구": "Access changed or restored",
  "직원 접근 해제": "Staff access removed",
  "업소 설정 변경": "Business settings changed",
  "최근 초대": "Recent invitations",
  "취소됨": "Revoked",
  "참여 완료": "Accepted",
  "초대 취소": "Revoke invitation",
  "공동 레시피": "Team recipes",
  "식단 계획": "Meal plans",
  "구매·입고": "Purchasing",
  "원가·판매가": "Cost & price",
  "판매 기록": "Sales records",
  "승인 대기": "Awaiting approval",
  "승인 완료": "Approved",
  "업소 공동 업무를 사용하려면 서버 업데이트가 필요합니다. 기존 개인 업무는 계속 사용할 수 있습니다.":
      "The server needs an update for shared business work. Personal tools are still available.",
  "다른 담당자가 수정했습니다. 최신 자료를 다시 열어 변경 내용을 확인해 주세요.":
      "Another person changed this record. Reopen the latest version before editing.",
  "업소 책임자의 활성 비즈니스 이용권이 필요합니다.":
      "The business owner needs an active Business membership.",
  "초대 코드가 만료되었거나 이메일이 다릅니다. 초대받은 이메일로 로그인하고 이메일 인증을 완료해 주세요.":
      "This invitation expired or belongs to another email. Sign in with the invited address and verify your email.",
  "업체·요청 업소·품목별 구매 수량과 단위를 입력해 주세요.":
      "Enter supplier, buyer and each item’s purchase quantity and unit.",
  "이 업소의 생성 한도에 도달했습니다. 기존 자료나 초대를 확인해 주세요.":
      "The workspace limit was reached. Review existing records or invitations.",
  "현재 계정의 접근 권한이 없습니다. 사장에게 권한을 확인해 주세요.":
      "This account has no access. Check your permissions with the owner.",
  "처리하지 못했습니다. 입력 내용과 연결 상태를 확인한 뒤 다시 시도해 주세요.":
      "Could not complete this action. Check the fields and connection, then retry.",
  "확인해 주세요": "Please confirm",
  "업소 작업공간 만들기": "Create business workspace",
  "직원 초대 수락": "Accept staff invitation",
  "개인 자료는 자동 공유되지 않습니다. 업소당 직원은 최대 30명이며 비즈니스 이용권이 필요합니다.":
      "Personal records are not shared automatically. Each workspace supports up to 30 members and requires a Business membership.",
  "초대받은 이메일로 로그인한 뒤 코드를 입력하세요.":
      "Sign in with your invited email, then enter the code.",
  "업소 이름": "Business name",
  "초대 코드": "Invitation code",
  "직원에게 보일 이름": "Your display name",
  "계속": "Continue",
  "업소 공동 업무": "Business workspace",
  "각자 로그인하고, 같은 업소에서 함께 일하세요.": "Your own accounts. One shared business.",
  "사장이 업소를 만들고 직원을 초대하면 함께 사용할 수 있습니다. 업소 책임자의 비즈니스 이용권으로 공동 업무를 이용하며, 직원은 초대받은 권한으로 참여합니다. 개인 자료와 공동 자료는 별도로 보관됩니다.":
      "The owner creates a business and invites staff. Shared work uses the owner’s Business membership; staff join with assigned permissions. Personal and shared records are kept separately.",
  "업소 만들기": "Create workspace",
  "초대 코드로 참여": "Join with a code",
  "사장 · 직원 및 권한 관리": "Owner · staff and permissions",
  "직원 · 부여받은 업무": "Staff · assigned responsibilities",
  "아직 참여한 업소가 없습니다.": "You have not joined a business yet.",
  "업소 공동 자료": "Shared business records",
  "조리 연구 → 구매량 확정 → 승인·전달 → 입고 확인 → 원가·판매 기록":
      "Recipe development → purchase quantities → approval & sharing → receipt → costs & sales",
  "현재 사용할 수 있는 업무가 없습니다. 사장에게 권한을 확인해 주세요.":
      "No work is available with your current permissions. Check with the owner.",
  "내 레시피에서 가져오기": "Copy a personal recipe",
  "일·주·월 매출": "Daily, weekly & monthly sales",
  "현재 페이지에서 제목 검색": "Search titles on this page",
  "사용 중지": "Archive",
  "표시할 자료가 없습니다. 새 자료를 추가하거나 검색 조건을 바꿔 주세요.":
      "No matching records. Add a record or adjust the filters.",
  "이전 50개": "Previous 50",
  "다음 50개": "Next 50",
  "구매량과 조리량은 별도입니다. 조리 재고를 자동 차감하지 않습니다.":
      "Purchase and cooking quantities stay separate. Cooking does not deduct stock.",
  "공동 자료로 복사할 레시피": "Choose a recipe to share",
  "선택한 재료·조리법·팁의 사본을 직원에게 공유합니다. 개인 원본과 사진은 변경·공유하지 않습니다.":
      "Share a copy of the ingredients, steps and tips. The personal original and photos are not changed or shared.",
  "올바른 수를 입력해 주세요.": "Enter a valid number.",
  "입력해 주세요.": "Required.",
  "연결할 자료를 선택해 주세요.": "Select a linked record.",
  "수정 권한이 없거나 확정된 자료입니다.": "Editing is not allowed for this account or record.",
  "여러 공동 레시피를 선택해 식단을 구성하세요. 구매량은 따로 확정합니다.":
      "Choose team recipes for this meal. Purchase quantities are confirmed separately.",
  "불러오는 중…": "Loading…",
  "연결 자료 확인 필요": "Check linked record",
  "원가·판매가 기준 선택": "Select cost & price",
  "공동 레시피 연결": "Link team recipe",
  "선택한 기준의 판매가·원가를 저장 시점에 기록합니다. 이후 가격 변경은 과거 매출에 반영되지 않습니다.":
      "The selected cost and price are recorded at save time. Later price changes do not alter past sales.",
  "조리 참고 내용을 확인하고 구매 품명·수량·단위를 별도로 확정해 주세요. 단가를 모르면 비워 두세요.":
      "Review the cooking reference, then confirm purchase names, quantities and units separately. Leave unknown prices blank.",
  "구매 단위 (직접 입력)": "Purchase unit (custom)",
  "30자 이내": "Up to 30 characters",
  "규격·조리 참고": "Pack / cooking reference",
  "이 품목 삭제": "Remove item",
  "구매 품목 추가": "Add purchase item",
  "공동 자료에 저장": "Save shared record",
  "변경 이력이 남으며, 저장 후에도 실제 발송·입고 상태는 자동 변경되지 않습니다.":
      "Changes are recorded in history. Saving does not confirm sharing or receipt.",
  "먼저 공동 자료를 등록해 주세요.": "Add a shared record first.",
  "업체에 실제로 요청서를 전달했나요? 파일 생성이나 공유창 열기만으로는 전달 완료가 아닙니다.":
      "Have you actually shared the request with the supplier? Generating a file or opening a share sheet does not confirm delivery.",
  "실제 도착한 품목과 수량을 확인했나요? 이 기록은 재고 수량을 변경하지 않습니다.":
      "Have you checked the received items and quantities? This record does not change stock.",
  "품목·구매량·단가·납품 조건을 확인하고 승인할까요?":
      "Approve after checking items, quantities, prices and delivery terms?",
  "작성 중으로 되돌릴까요? 수정 후에는 다시 승인을 진행합니다.":
      "Return to draft? Changes will require approval again.",
  "이 구매요청을 취소로 기록할까요? 이미 보냈다면 업체와 별도로 확인해 주세요.":
      "Record this request as cancelled? If already shared, confirm cancellation with the supplier separately.",
  "확정한 구매량과 조건으로 승인을 요청할까요?":
      "Submit the confirmed quantities and terms for approval?",
  "공동 구매요청서 PDF": "Team purchase request PDF",
  "문서 출력은 전달 상태를 바꾸지 않습니다.": "Exporting does not change the sharing status.",
  "최근 변경 이력": "Recent changes",
  "최신 자료 다시 열기": "Reload latest record",
  "수정하기": "Edit",
  "버전·변경 이력": "Versions & history",
  "이 자료를 사용 중지할까요? 판매 기록은 집계에서 제외되고 변경 이력은 남습니다.":
      "Archive this record? Sales will be excluded from totals and history is retained.",
  "재료를 공동 구매 준비로 넘길까요? 구매 담당자가 품명·구매량·단위를 따로 확인합니다.":
      "Send these ingredients to shared purchasing? The purchaser confirms item names, quantities and units separately.",
  "구매 준비로 넘기기": "Hand over to purchasing",
  "PDF 미리보기·공유·인쇄": "PDF preview, share & print",
  "승인 요청": "Request approval",
  "수정 요청·작성으로": "Return to draft",
  "구매 승인": "Approve purchase",
  "전달 완료로 기록": "Record sharing",
  "입고 완료로 기록": "Record receipt",
  "요청 취소": "Cancel request",
  "재료·조리 수량": "Ingredients & cooking quantities",
  "조리 순서·연구 기록": "Steps & research",
  "식단 날짜": "Meal date",
  "예정 인분": "Planned servings",
  "공동 레시피 열기": "Open team recipe",
  "연결된 레시피를 불러오지 못했습니다.": "Could not load a linked recipe.",
  "판매 날짜": "Sale date",
  "입력한 원가 기준이며 미입력 경비·세금은 포함되지 않습니다.":
      "Based on recorded costs; unentered expenses and taxes are excluded.",
  "메모·요청사항": "Notes / requests",
  "업소 매출 현황": "Business sales",
  "판매분 원가": "Recorded cost",
  "예상이익": "Estimated profit",
  "해당 통화의 공동 판매 기록만 집계합니다. 예상이익은 매출에서 기록한 원가를 뺀 값이며 실제 순이익과 다릅니다.":
      "Only shared sales in this currency are included. Estimated profit is revenue minus recorded cost; it is not net profit.",
  "업무 화면을 저장하지 못했어요. 다시 시도해 주세요.":
      "Could not save this work view. Please try again.",
  "내 업무, 한눈에 이어가기": "Your work, connected",
  "필요한 재료부터, 입고 확인까지.": "From ingredients to receipt.",
  "더 나은 한 접시를 연구하세요.": "Develop your next great dish.",
  "원가를 알고, 판매를 결정하세요.": "Know your costs. Plan your sales.",
  "하던 일을 이어가고, 다음 작업을 바로 시작하세요.":
      "Continue where you left off and move to the next task.",
  "내 업무 전체": "My work",
  "담당 업무 설정": "Responsibilities",
  "직원별 로그인 · 공동 자료 · 사장 권한 관리":
      "Staff accounts · shared records · owner permissions",
  "로그인하고 내 업무를 이어가세요.": "Sign in to continue your work.",
  "샘플 튜토리얼은 로그인 없이 체험할 수 있어요.":
      "You can try the sample tutorials without signing in.",
  "현재 로그인한 계정의 자료를 사용합니다. 업무 화면 선택은 자료 접근 권한을 바꾸지 않습니다.":
      "These views use the current account’s records. Choosing a work view does not change access permissions.",
  "구매량 준비": "Prepare quantities",
  "조리량과 별도로 구매 단위·수량 확정": "Set purchase quantities and units separately",
  "업체 비교·요청": "Compare & request",
  "재료별 후보 최대 3곳 → 요청서 검토": "Up to 3 candidates per item → review request",
  "전달·입고 확인": "Follow up & receive",
  "업체 답변과 실제 입고를 확인해 기록": "Record the reply and receipt after checking",
  "레시피 연구": "Research recipes",
  "영상 찾기 → 초안 검토 → 내 레시피": "Find a video → review draft → save recipe",
  "인분·버전 비교": "Scale & compare",
  "기준 레시피의 배합과 개선 기록": "Adjust the formula and keep revision notes",
  "구매 준비로 연결": "Prepare purchasing",
  "내 레시피 선택 → 장보기 준비": "Choose a recipe → prepare shopping",
  "원가·판매가 점검": "Review cost & price",
  "재료비·수율·추가 비용을 확인": "Check ingredients, yield and added costs",
  "매출 기록·분석": "Record & review sales",
  "요리별 판매량과 일·주·월 실적": "Sales by dish, day, week and month",
  "구매 대장 확인": "Review purchases",
  "기간·업체별 요청 내역과 문서 출력": "Review requests and export documents",
  "샘플로 배우기": "Learn with samples",
  "구매·입고 이력을 관리합니다. 조리로 인한 재고 차감은 하지 않습니다.":
      "Track purchasing and receipt. Cooking does not deduct stock.",
  "작업실에서 저장한 뒤 장보기 준비로 이어갈 수 있어요. 구매량은 별도로 확인하세요.":
      "Save your work before continuing to shopping preparation. Confirm purchase quantities separately.",
  "예상이익은 입력된 원가 기준입니다. 미입력 경비와 세금은 포함되지 않습니다.":
      "Estimated profit uses recorded costs. Unentered expenses and taxes are excluded.",
  "내 레시피에서 계속하기": "Continue with your recipes",
  "영상에서 초안을 만들거나 내 레시피에 요리를 저장하세요.":
      "Create a video draft or save a dish in My recipes.",
  "조리법·구매 준비": "Recipe & purchasing",
  "인분·버전 연구": "Scale & versions",
  "기록한 판매 실적": "Recorded sales",
  "선택한 통화의 기록만 표시합니다. 실제 결제 내역이나 순이익이 아닙니다.":
      "Only records in the selected currency are shown. These are not payment transactions or net profit.",
  "매출 상세 보기": "View sales details",
  "조리 연구": "Cooking",
  "경영 관리": "Management",
  "구매량 확인부터 업체 비교, 요청서와 입고 기록까지.":
      "Confirm quantities, compare suppliers, prepare requests and record receipt.",
  "레시피를 연구하고 인분·배합·조리 버전을 관리해요.":
      "Develop recipes, scale servings and compare cooking versions.",
  "원가와 판매가를 정하고 매출·구매 내역을 살펴봐요.":
      "Set costs and prices, then review sales and purchasing records.",
  "더보기": "More",
  "이용 목적·담당 업무": "Purpose & responsibilities",
  "맡고 있는 업무": "Your responsibilities",
  "함께 맡는 업무는 모두 선택하세요. 업무별 메뉴와 시작 화면을 맞춰 드려요.":
      "Select every responsibility you handle. Your menus and home will follow your choices.",
  "처음 볼 업무": "Default work view",
  "선택한 업무 한눈에": "All selected responsibilities",
  "최소 한 업무를 선택해 주세요. 이 설정은 내 화면을 정리하며 직원 초대나 자료 공유 권한을 부여하지 않습니다.":
      "Keep at least one responsibility selected. These preferences organize your view; they do not invite staff or grant access to shared records.",
  "조리 연구 · 5개 실습": "Cooking · 5 lessons",
  "경영 관리 · 3개 실습": "Management · 3 lessons",
  "재료·조리 수량 (한 줄에 한 재료)": "Ingredients & cooking quantities (one per line)",
  "식단 날짜 (YYYY-MM-DD)": "Meal date (YYYY-MM-DD)",
  "판매 날짜 (YYYY-MM-DD)": "Sale date (YYYY-MM-DD)",
  "공급업체": "Supplier",
  "연락처": "Phone",
  "납품 주소": "Delivery address",
  "배합·버전": "Formula & versions",
  "조리·원가": "Kitchen & cost",
  "관리자 2단계 인증을 완료한 뒤 다시 열어 주세요.":
      "Complete administrator two-step authentication and reopen this page.",
  "관리자 계정만 테스트를 관리할 수 있습니다.": "Only administrators can manage tests.",
  "이메일 인증을 마친 테스트 참여 계정이 필요합니다. 관리자에게 테스터 등록을 확인해 주세요.":
      "A verified test participant account is required. Ask the administrator to check tester access.",
  "진행 중인 테스트를 먼저 종료해 주세요.": "End the current test before creating another.",
  "이름과 테스트 기간(1~90일)을 확인해 주세요.":
      "Check the name and test duration (1–90 days).",
  "테스트가 종료되었거나 참여 권한이 없습니다. 테스트 목록을 새로 열어 확인해 주세요.":
      "This test ended or access is unavailable. Refresh the test list.",
  "샘플 20개로 업무 테스트": "Practice with 20 samples",
  "1. 구매 품명": "1. Purchase item",
  "연습 전용 공간": "Practice workspace",
  "이곳에 추가·수정한 자료도 테스트 종료 시 삭제될 수 있습니다. 실제 업소 자료는 별도로 유지됩니다. 샘플로 실제 발주하지 마세요. PDF에도 연습용 표시가 붙습니다.":
      "Records added or edited here may be deleted when testing ends. Real business records stay separate. Do not place real orders with samples. PDFs are marked as practice.",
  "입력 내용을 확인해 주세요.": "Check this field.",
  "테스터": "Tester",
  "내 연습 공간에 추가·수정한 자료를 모두 삭제하고 처음 샘플 20개로 되돌립니다. 초대한 직원은 유지됩니다. 실제 업소 자료는 바뀌지 않습니다. 다시 시작할까요?":
      "Delete all records added or edited in your practice workspace and restore the original 20 samples? Invited staff stay. Real business records are unchanged.",
  "업소 업무 테스트": "Business practice",
  "20개 샘플로, 한 업소의 업무를 끝까지": "Explore a complete workflow with 20 samples",
  "구매·조리·경영 업무가 연결된 내 연습 공간을 만듭니다. 테스트 기간에는 이 공간의 업무 기능을 이용권 결제 없이 체험할 수 있습니다.":
      "Create your own practice workspace linking purchasing, cooking and management. Its work features are available without a paid plan during the test.",
  "업무별 연습 순서": "Practice steps by role",
  "1. 조리: 레시피와 식단 열기 → 재료 요청\n2. 구매: 구매량·구매 단위 확인 → 승인 요청 → 전달·입고 확인\n3. 경영: 승인 → 원가·판매가 비교 → 일·주·월 판매 확인\n혼자서는 모든 업무를, 직원 초대로는 담당별 권한을 시험할 수 있습니다. 함께할 직원도 같은 테스트의 참여 계정이어야 합니다.":
      "1. Cooking: open recipes and meal plans → request ingredients\n2. Purchasing: confirm purchase quantities and units → request approval → confirm sharing and receipt\n3. Management: approve → compare costs and prices → review daily, weekly and monthly sales\nTry all tasks yourself or invite staff to test assigned permissions. Staff must also be participants in the same test.",
  "참여할 테스트가 없습니다. 관리자에게 로그인 이메일로 테스터 등록을 요청해 주세요.":
      "No test is available. Ask the administrator to register your sign-in email.",
  "종료 예정": "Ends",
  "내 샘플 20개 만들기": "Create my 20 samples",
  "이어서 연습하기": "Continue practice",
  "샘플 처음으로": "Reset samples",
  "테스트가 종료되었거나 참여가 해제되었습니다. 연습 공간을 더 이상 이용할 수 없습니다.":
      "This test has ended or access was removed. The practice workspace is no longer available.",
  "업소 업무 체험 테스트": "Business workflow test",
  "테스트 열기": "Open a test",
  "테스트 이름": "Test name",
  "이름을 입력해 주세요.": "Enter a name.",
  "테스트 기간 (1~90일)": "Duration (1–90 days)",
  "1~90일로 입력해 주세요.": "Enter 1–90 days.",
  "참여 범위": "Participants",
  "지정한 테스터": "Selected testers",
  "모든 회원": "All members",
  "이메일 인증을 완료한 계정이 참여할 수 있습니다. 테스터별로 샘플 20개가 생성되며 최대 1,000개 연습 공간을 지원합니다. 실제 이용권 권한은 변경되지 않습니다.":
      "Participants need verified email accounts. Each gets 20 samples, up to 1,000 practice workspaces. Paid membership entitlements do not change.",
  "테스트 시작": "Start test",
  "테스터의 로그인 이메일": "Tester sign-in email",
  "1 계정의 테스트 접근을 해제할까요? 이 계정 소유의 연습 공간은 초대한 직원도 접근할 수 없게 됩니다.":
      "Remove test access for 1? Staff invited to this account’s practice workspace will also lose access.",
  "업소 테스트 관리": "Business test management",
  "테스트 기간과 참여자를 한곳에서": "Manage the test and its participants",
  "관리자 2단계 인증이 필요합니다. 기간이 지나면 접근이 자동 중단됩니다. 자료 삭제는 관리자가 확인 후 실행하며, 연습 공간에 추가된 자료도 함께 삭제합니다.":
      "Administrator two-step authentication is required. Access stops when the test expires. Administrators confirm deletion, including records added in practice workspaces.",
  "관리자 계정으로 로그인해 주세요.": "Sign in as an administrator.",
  "종료됨": "Ended",
  "이메일 인증을 마친 모든 회원 (해제 계정 제외)":
      "All verified members, except removed accounts",
  "관리자가 지정한 테스터": "Selected testers",
  "참여 해제": "Remove access",
  "참여 허용": "Allow access",
  "테스터 등록": "Add tester",
  "테스트 종료": "End test",
  "샘플 자료 삭제": "Delete sample records",
  "종료하고 샘플 삭제": "End and delete samples",
  "레시피 5": "5 recipes",
  "식단 3": "3 meal plans",
  "구매요청 5": "5 requests",
  "원가·판매가 3": "3 cost sheets",
  "판매기록 4": "4 sales",
  "구매·입고 담당": "Purchasing and receipt",
  "원가·매출 담당": "Costs and sales",
  "원가·매출 조회": "View costs and sales",
  "구매 승인 담당": "Purchase approver",
  "이용 중지": "Access suspended",
  "담당 업무·권한": "Duties and permissions",
  "담당자 정보": "Staff profile",
  "업무·권한 수정": "Edit duties and permissions",
  "이용 복구": "Restore access",
  "이용 복구 · 권한 확인": "Restore access · review permissions",
  "저장하면 아래 권한으로 업소 이용이 다시 허용됩니다.":
      "Saving restores business access with the permissions below.",
  "권한을 수정해도 이용 중지 상태는 유지됩니다.": "Editing permissions keeps access suspended.",
  "사장이 담당자 정보와 업무 권한을 관리합니다. 이용 중지 시 공동 자료와 작업 이력은 보존됩니다.":
      "Manage staff profiles and permissions here. Suspending access preserves shared records and history.",
  "이름·직책·업무 연락처 검색": "Search name, job title or work contact",
  "조건에 맞는 담당자가 없습니다.": "No staff match these filters.",
  "담당자 정보 변경": "Staff profile changed",
  "담당자 정보 수정": "Edit staff profile",
  "표시 이름": "Display name",
  "직책·담당 표기 (선택)": "Job title or duty label (optional)",
  "직책은 표시용입니다. 실제 접근 권한은 별도로 지정합니다.":
      "A job title is a label. Access permissions are managed separately.",
  "업무 연락처 (선택)": "Work contact (optional)",
  "업무용 전화번호나 이메일을 입력하세요. 이 정보는 사장과 본인만 조회할 수 있습니다.":
      "Use a work phone number or email. Only the owner and this member can read this profile.",
  "이름·직책·업무 연락처의 길이와 입력 내용을 확인해 주세요.":
      "Check the name, job title and work contact fields.",
  "직책 (선택)": "Job title",
  "업무 연락처": "Work contact",
  "구매 기준 재료": "Ingredients for purchasing",
  "규격·손질 상태": "Specification / preparation",
  "기준 인분에 필요한 조리량": "Cooking quantity for base servings",
  "조리 단위 (g·ml·개 등)": "Cooking unit (g / ml / pcs etc.)",
  "반영": "Apply",
  "수량·단위를 등록하면 재료 목록을 이 값으로 저장합니다. 기존 자유 입력 재료는 자동 변환하지 않으므로 빠짐없이 확인하세요.":
      "Register quantities and units to save the ingredient list from these values. Existing free text is not converted automatically; check every ingredient.",
  "재료 삭제": "Remove ingredient",
  "수량·단위가 있는 재료 추가": "Add ingredient with quantity and unit",
  "개발 중": "In development",
  "시험 조리·승인 대기": "Trial cooking / awaiting approval",
  "출시 승인": "Approved for launch",
  "출시 준비": "Preparing launch",
  "출시 준비용 구매": "Launch purchase",
  "영업용 구매": "Operations purchase",
  "메뉴 변경 이력": "Menu history",
  "레시피 버전": "Recipe revision",
  "메뉴판 관리": "Menu management",
  "승인된 레시피 버전을 메뉴에 연결하세요. 개발 중 수정은 판매 메뉴에 자동 반영되지 않습니다.":
      "Link an approved recipe revision. Development edits do not automatically change a selling menu.",
  "메뉴 등록": "Add menu item",
  "관리 화면": "Manage",
  "판매 메뉴판 미리보기": "Preview selling menu",
  "메뉴·레시피에서 구매": "Buy from menus / recipes",
  "메뉴명·분류 검색": "Search menu names / categories",
  "표시할 메뉴가 없습니다.": "No matching menu items.",
  "수정·출시·판매 중지": "Edit / launch / stop",
  "변경 이력": "History",
  "업소 내부 미리보기입니다. 고객용 공개 링크나 QR은 생성되지 않습니다.":
      "Internal preview. No public customer link or QR is created.",
  "이 메뉴의 이름·가격·레시피 버전과 판매 상태를 저장할까요?":
      "Save this menu name, price, recipe revision and selling state?",
  "메뉴 등록·수정": "Menu item",
  "판매 메뉴명": "Menu name",
  "분류": "Category",
  "메뉴 설명": "Menu description",
  "판매가": "Selling price",
  "출시 승인된 레시피를 선택하세요.": "Choose an approved recipe revision.",
  "승인된 레시피 버전 선택": "Choose approved recipe revision",
  "판매 상태": "Selling state",
  "참조할 레시피 버전": "Recipe revision to use",
  "최근 30개 버전입니다. 재료·기준 인분을 확인한 뒤 선택하세요.":
      "Latest 30 revisions. Check ingredients and base servings before selecting.",
  "출시 승인된 버전이 없습니다. 시험 조리 후 출시 승인을 먼저 진행하세요.":
      "No approved revision. Complete trial cooking and launch approval first.",
  "인분": "servings",
  "이 버전 참조": "Use this revision",
  "시험 조리 결과·변경 사유 (필수)": "Trial result / reason (required)",
  "기록": "Record",
  "개발·출시 관리": "Development & launch",
  "새 내용을 저장하면 새 버전으로 개발을 이어갑니다. 판매 메뉴는 기존 승인 버전을 유지합니다.":
      "Saving edits continues development as a new revision. Selling menus keep their approved revision.",
  "구매 기준 재료의 수량·단위를 등록해야 시험 조리와 출시 승인을 진행할 수 있습니다.":
      "Register ingredient quantities and units before trial cooking and approval.",
  "시험 조리 결과 등록": "Record trial cooking",
  "개발 단계로 돌리기": "Return to development",
  "이 버전 출시 승인": "Approve this revision",
  "메뉴판에 연결": "Link to menu",
  "시험 조리·승인 이력": "Trial and approval history",
  "구매 작성 기준 · 메뉴·레시피 버전": "Purchase basis · menu / recipe revisions",
  "초안 생성 당시 기준입니다. 이후 요청 품목을 수동 수정하면 현재 구매량과 다를 수 있습니다.":
      "Basis at draft creation. Later manual edits may differ from these quantities.",
  "조리 필요량": "Required for cooking",
  "재료·배합": "Ingredients & quantities",
  "현재 개발 버전과 달라진 내용": "Differences from current development revision",
  "레시피 내용이 같습니다.": "Recipe contents are identical.",
  "판매 중 메뉴 선택": "Choose a selling menu",
  "판매 중인 메뉴가 없습니다. 메뉴판에서 출시 상태를 확인하세요.":
      "No selling menus. Check the menu release state.",
  "조리할 인분 (판매·시험 수량)": "Servings to prepare (sales / trial)",
  "등록한 공급업체 선택": "Choose a saved supplier",
  "선택한 업체명만 이 업소의 공동 요청서에 복사합니다.":
      "Only the selected supplier name is copied into this shared request.",
  "등록된 업체가 없습니다. 업체명을 직접 입력할 수 있습니다.":
      "No saved suppliers. You can enter a supplier name.",
  "표시된 구매량으로 공동 구매 초안을 만들까요? 다음 화면에서 납품일·단가를 확인하고 기존 승인 절차를 진행합니다.":
      "Create a shared purchase draft with these quantities? Confirm delivery and prices on the next screen, then follow the existing approval process.",
  "메뉴·레시피에서 구매요청": "Purchase from menus / recipes",
  "먼저 구매 목적과 기준 레시피를 선택하세요. 재료량은 서버에서 계산하며 재고를 자동 차감하지 않습니다.":
      "Choose the purchase purpose and recipe first. Quantities are calculated on the server; stock is not automatically deducted.",
  "구매 목적": "Purchase purpose",
  "개발·시험 조리용 구매": "Development / trial purchase",
  "제외": "Remove",
  "메뉴·레시피와 인분 추가": "Add menu / recipe and servings",
  "재료 필요량 계산": "Calculate ingredient requirements",
  "재고·입고 예정·포장 규격 확인": "Review stock, incoming and pack sizes",
  "이름·규격·단위가 같은 재료만 합산합니다. 재고와 입고 예정량은 다른 작업에 배정되지 않은 수량을 입력하세요. 없으면 0을 입력합니다.":
      "Only matching names, specifications and units are combined. Enter stock and incoming quantities not allocated to other work. Enter 0 if none.",
  "이번 공급업체에 요청": "Include for this supplier",
  "사용 가능 재고": "Available stock",
  "입고 예정": "Incoming",
  "포장 1개당 양": "Quantity per pack",
  "구매 단위 (봉·박스 등)": "Purchase unit (bag / box etc.)",
  "필요 구매량": "Net requirement",
  "포장 반올림 여유량": "Pack rounding surplus",
  "재고·입고 예정·포장 규격을 확인했습니다.":
      "I checked stock, incoming quantities and pack size.",
  "등록한 공급업체에서 선택": "Choose from saved suppliers",
  "이번 업체에 요청할 재료만 선택하세요. 나머지 재료는 다른 업체의 요청서에서 작성합니다.":
      "Select only ingredients for this supplier. Use another request for the remaining ingredients.",
  "확인한 수량으로 구매 초안 만들기": "Create purchase draft with reviewed quantities",
  "기타 비품·직접 구매요청 작성": "Other supplies / write a request manually",
  "구매 기준 재료를 하나 이상 등록해 주세요.":
      "Register at least one ingredient for purchasing.",
  "메뉴·레시피를 먼저 참조하기": "Start from a menu or recipe",
  "레시피에 수량·단위가 있는 구매 기준 재료를 먼저 등록해 주세요.":
      "First register recipe ingredients with quantities and units.",
  "시험 조리를 마친 레시피 버전의 출시 승인이 필요합니다.":
      "This tested recipe revision needs launch approval.",
  "사용 가능 재고·입고 예정량·포장 규격을 확인해 주세요.":
      "Confirm available stock, incoming quantities and pack sizes.",
  "현재 계산으로는 구매할 재료가 없습니다.":
      "No ingredients need purchasing with these quantities.",
  "이 레시피를 사용하는 메뉴의 판매를 먼저 중지해 주세요.":
      "Stop the menus using this recipe before archiving it.",
  "메뉴 상태나 참조 버전이 변경됐습니다. 최신 자료를 확인해 주세요.":
      "The menu state or source revision changed. Reload the latest records.",
  "이번 요청에서 제외": "Excluded from this request",
  "재고 / 입고 예정": "Stock / incoming",
  "포장 규격 / 구매 수량": "Pack size / purchase quantity",
};
