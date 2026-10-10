part of 'guide_curriculum.dart';

GuideLesson? guideLessonById(String? id) =>
    guideLessons.where((l) => l.id == id).firstOrNull;
GuideTrack guideTrackFor(GuideLesson lesson) => lesson.id.startsWith('buy-')
    ? GuideTrack.purchasing
    : {'pro-cost', 'pro-pricing', 'pro-sales'}.contains(lesson.id)
        ? GuideTrack.management
        : GuideTrack.cooking;
List<GuideLesson> guideTrackLessons(GuideAudience audience, GuideTrack track) =>
    guideLessonsFor(audience)
        .where((l) =>
            audience != GuideAudience.professional || guideTrackFor(l) == track)
        .toList();
String guideLessonPath(String id) =>
    Uri(path: '/guide', queryParameters: {'lesson': id}).toString();

const workflowGuideLessons = <GuideLesson>[
  GuideLesson(
      id: "buy-quantity",
      audience: GuideAudience.professional,
      title: (ko: "구매량부터 준비하기", en: "Prepare purchase quantities"),
      goal: (
        ko: "장보기에서 이번에 살 재료만 고릅니다.",
        en: "Select only the ingredients you need to buy."
      ),
      outcome: (
        ko: "구매 수량·단위를 확인한 목록",
        en: "A list with confirmed purchase quantities and units"
      ),
      steps: [
        (
          title: (ko: "재료 고르기", en: "Choose ingredients"),
          body: (
            ko: "구매 → 새 구매요청 → 장보기 재료에서 시작하세요. 새 목록이 필요하면 장보기에서 먼저 준비합니다.",
            en: "Start at Purchasing → New request → From shopping ingredients. Prepare a shopping list first if needed."
          )
        ),
        (
          title: (ko: "구매량 입력하기", en: "Enter purchase quantities"),
          body: (
            ko: "조리 원문은 그대로 두고 구매 수량과 단위를 입력합니다. 조리 200g과 구매 1팩은 다른 정보입니다.",
            en: "Leave recipe quantities unchanged and enter purchase quantities and units. Cooking with 200 g and buying one pack are different."
          )
        ),
        (
          title: (ko: "환산 기준 확인하기", en: "Check conversions"),
          body: (
            ko: "g↔kg, mL↔L 같은 구매 단위는 환산합니다. 한 팩의 무게처럼 기준이 없으면 상품 규격을 확인해 직접 입력하세요.",
            en: "Purchase units such as g/kg and mL/L can be converted. For a pack weight without a conversion, check the product specification and enter the basis."
          )
        )
      ],
      tip: (
        ko: "조리량 환산은 인분 계산에서 다룹니다. 이 과정은 구매 이력을 관리하며 조리에 따른 재고 차감은 하지 않습니다.",
        en: "Cooking quantities are scaled with servings. This workflow records purchases and does not deduct stock as food is cooked."
      ),
      question: (
        ko: "조리에 200g을 써도 1kg 포장을 사려면?",
        en: "How do you buy a 1 kg pack when the recipe uses 200 g?"
      ),
      answers: [
        (ko: "구매량만 1kg으로 입력합니다.", en: "Enter 1 kg as the purchase quantity."),
        (
          ko: "조리 원문도 1kg으로 바꿉니다.",
          en: "Change the recipe quantity to 1 kg too."
        )
      ],
      correctAnswer: 0,
      explanation: (
        ko: "조리량 환산은 인분 계산에서 다룹니다. 이 과정은 구매 이력을 관리하며 조리에 따른 재고 차감은 하지 않습니다.",
        en: "Cooking quantities are scaled with servings. This workflow records purchases and does not deduct stock as food is cooked."
      ),
      destination: GuideDestination.shopping,
      minutes: 3),
  GuideLesson(
      id: "buy-suppliers",
      audience: GuideAudience.professional,
      title: (ko: "내 거래처 만들기", en: "Build your supplier list"),
      goal: (
        ko: "검색 조건을 좁혀 필요한 업체를 찾습니다.",
        en: "Narrow the search to suitable suppliers."
      ),
      outcome: (ko: "다시 찾기 쉬운 내 거래처", en: "Your own reusable supplier list"),
      steps: [
        (
          title: (ko: "공개 업체 찾기", en: "Find public suppliers"),
          body: (
            ko: "거래처에서 공급업체 찾기를 열고 재료·상품·업체 이름으로 검색합니다.",
            en: "Open Find suppliers from Suppliers and search by ingredient, product or business name."
          )
        ),
        (
          title: (ko: "조건과 출처 확인하기", en: "Review conditions and source"),
          body: (
            ko: "분류·배송 지역·원산지·브랜드를 선택하세요. 공개 정보 업체인지 직접 등록 업체인지, 연락처와 상품 조건이 현재도 유효한지 확인합니다.",
            en: "Filter by category, delivery region, origin and brand. Review whether information is public-source or supplier-managed, and confirm current contact and product terms."
          )
        ),
        (
          title: (ko: "내 거래처로 선택하기", en: "Select your supplier"),
          body: (
            ko: "업체를 선택하면 내 거래처에 등록되고 다음 선택에서 우선 표시됩니다. 기존 협력업체는 직접 등록할 수도 있습니다.",
            en: "Selecting a business adds it to your suppliers and prioritizes it next time. You can also register an existing partner yourself."
          )
        )
      ],
      tip: (
        ko: "공개 등록이나 사업자 확인 표시는 품질·납품·최저가 보증이 아닙니다. 필요한 조건은 거래처와 확인하세요.",
        en: "A public listing or business verification is not a quality, delivery or lowest-price guarantee. Confirm your terms with the supplier."
      ),
      question: (
        ko: "공개 업체를 내 거래처로 선택하면?",
        en: "What happens when you select a public business as your supplier?"
      ),
      answers: [
        (
          ko: "공개 업체의 원본 정보가 내 이름으로 바뀝니다.",
          en: "The original public listing is changed to my name."
        ),
        (
          ko: "내 거래처에 연결되어 선택할 때 먼저 표시됩니다.",
          en: "It becomes one of your suppliers and is shown first."
        )
      ],
      correctAnswer: 1,
      explanation: (
        ko: "공개 등록이나 사업자 확인 표시는 품질·납품·최저가 보증이 아닙니다. 필요한 조건은 거래처와 확인하세요.",
        en: "A public listing or business verification is not a quality, delivery or lowest-price guarantee. Confirm your terms with the supplier."
      ),
      destination: GuideDestination.suppliers,
      minutes: 3),
  GuideLesson(
      id: "buy-candidates",
      audience: GuideAudience.professional,
      title: (ko: "재료별 업체 후보 고르기", en: "Choose suppliers per ingredient"),
      goal: (
        ko: "각 재료를 취급하는 업체를 최대 3곳 고릅니다.",
        en: "Choose up to three suppliers for each ingredient."
      ),
      outcome: (
        ko: "모든 선택 재료에 후보가 있는 비교 목록",
        en: "A comparison list with candidates for every selected ingredient"
      ),
      steps: [
        (
          title: (ko: "구매 재료 선택하기", en: "Choose items to purchase"),
          body: (
            ko: "구매요청 도우미에서 재료와 구매 수량·단위를 확인하고 다음으로 이동합니다.",
            en: "Confirm ingredients, purchase quantities and units in the planner, then continue."
          )
        ),
        (
          title: (ko: "재료마다 후보 선택하기", en: "Choose candidates for each item"),
          body: (
            ko: "각 재료의 업체 후보 버튼을 누르고 1~3곳을 선택하세요. 전체 요청에 업체가 총 3곳만 들어갈 수 있다는 뜻은 아닙니다.",
            en: "Open the supplier candidates for each ingredient and choose one to three. This is not a limit of three suppliers for the entire request."
          )
        ),
        (
          title: (ko: "상품 규격 맞추기", en: "Match product pack sizes"),
          body: (
            ko: "같은 업체의 다른 상품을 고르면 그 업체의 후보 상품이 바뀝니다. 구매 단위와 상품 내용량이 다르면 환산 기준도 확인하세요.",
            en: "Choosing another product from the same supplier replaces that candidate. Check conversion when your purchase unit differs from the product content unit."
          )
        )
      ],
      tip: (
        ko: "이전 단계로 돌아가도 같은 앱 실행 중 선택은 유지됩니다. 앱 종료나 웹 새로고침 전에는 요청서를 저장하세요.",
        en: "Selections remain when moving back in the same app session. Save requests before closing the app or refreshing the browser."
      ),
      question: (
        ko: "당근과 두부를 살 때 후보는 몇 곳까지인가요?",
        en: "How many candidates can you choose for carrot and tofu?"
      ),
      answers: [
        (
          ko: "당근 최대 3곳, 두부 최대 3곳입니다.",
          en: "Up to three for carrot and three for tofu."
        ),
        (ko: "모든 재료를 합쳐 3곳뿐입니다.", en: "Only three across all ingredients.")
      ],
      correctAnswer: 0,
      explanation: (
        ko: "이전 단계로 돌아가도 같은 앱 실행 중 선택은 유지됩니다. 앱 종료나 웹 새로고침 전에는 요청서를 저장하세요.",
        en: "Selections remain when moving back in the same app session. Save requests before closing the app or refreshing the browser."
      ),
      destination: GuideDestination.planner,
      minutes: 3),
  GuideLesson(
      id: "buy-compare",
      audience: GuideAudience.professional,
      title: (ko: "세 가지 기준 비교하기", en: "Compare three purchasing priorities"),
      goal: (
        ko: "후보 선택을 마친 뒤 구매 기준 하나를 고릅니다.",
        en: "After selecting candidates, choose one purchasing priority."
      ),
      outcome: (
        ko: "선택한 기준으로 묶인 업체별 초안",
        en: "Supplier drafts grouped by your chosen priority"
      ),
      steps: [
        (
          title: (ko: "최소 거래처 수", en: "Fewest suppliers"),
          body: (
            ko: "같은 업체에서 함께 살 수 있는 재료를 묶어 요청서 수를 줄입니다.",
            en: "Group ingredients available from the same supplier to reduce the number of requests."
          )
        ),
        (
          title: (ko: "최저 구매가격", en: "Lowest purchase price"),
          body: (
            ko: "상품의 판매 포장 수와 업체별 배송비를 포함한 등록 견적을 비교합니다. 가격 유효기간·세금·최소 주문 조건을 함께 확인하세요.",
            en: "Compare registered estimates including selling pack counts and delivery fees per supplier. Check price validity, tax and minimum-order terms."
          )
        ),
        (
          title: (ko: "평점 우선", en: "Highest rating first"),
          body: (
            ko: "구매자 평점을 우선합니다. 평가가 없는 업체와 평가가 있는 업체를 구분하고, 초안의 업체·품목 배정을 확인하세요.",
            en: "Prioritize buyer ratings, distinguish unrated suppliers and review which items each supplier receives."
          )
        )
      ],
      tip: (
        ko: "비교 범위는 선택한 후보입니다. 가격이나 배송비가 없으면 견적 필요로 표시하며 실제 최종 거래 가격은 업체 확인이 필요합니다.",
        en: "Comparison covers your chosen candidates. Missing prices or shipping require a quote; confirm final trading prices with the supplier."
      ),
      question: (
        ko: "최저 구매가격은 어느 범위를 비교하나요?",
        en: "What does Lowest purchase price compare?"
      ),
      answers: [
        (
          ko: "전국 모든 업체의 최종 결제액을 보장합니다.",
          en: "It guarantees the final price across every supplier nationwide."
        ),
        (
          ko: "내가 고른 후보의 규격·가격·배송 조건을 비교합니다.",
          en: "Pack sizes, prices and shipping among your selected candidates."
        )
      ],
      correctAnswer: 1,
      explanation: (
        ko: "비교 범위는 선택한 후보입니다. 가격이나 배송비가 없으면 견적 필요로 표시하며 실제 최종 거래 가격은 업체 확인이 필요합니다.",
        en: "Comparison covers your chosen candidates. Missing prices or shipping require a quote; confirm final trading prices with the supplier."
      ),
      destination: GuideDestination.planner,
      minutes: 3),
  GuideLesson(
      id: "buy-request",
      audience: GuideAudience.professional,
      title: (ko: "요청서 검토와 PDF 준비", en: "Review requests and prepare a PDF"),
      goal: (
        ko: "업체별 초안을 수정하고 미리 확인합니다.",
        en: "Edit and preview each supplier draft."
      ),
      outcome: (
        ko: "보낼 내용을 검토한 구매요청서",
        en: "A purchase request reviewed before sharing"
      ),
      steps: [
        (
          title: (ko: "초안 수정하기", en: "Edit the draft"),
          body: (
            ko: "요청자·거래처·구매 수량·단가·희망 납품일과 장소를 확인합니다. 조건이 미확정이면 요청사항에 남기세요.",
            en: "Check buyer, supplier, quantities, unit prices, desired delivery date and address. Record any unconfirmed conditions in the notes."
          )
        ),
        (
          title: (ko: "양쪽 사업자 정보", en: "Both parties’ business details"),
          body: (
            ko: "요청 업소와 공급업체의 사업자등록번호와 등록증을 필요한 경우 추가합니다. 번호를 눌러 연결된 등록증을 확인할 수 있습니다.",
            en: "Add buyer and supplier registration numbers and certificates when needed. Select a number to view its linked certificate."
          )
        ),
        (
          title: (ko: "미리보기·저장·출력", en: "Preview, save and print"),
          body: (
            ko: "저장 전 PDF 미리보기로 내용을 확인하고 요청서를 저장합니다. PDF 저장 또는 인쇄에서는 기기나 브라우저의 출력 대상을 선택하세요.",
            en: "Review the PDF preview before saving the request. For PDF export or printing, choose the output destination provided by your device or browser."
          )
        )
      ],
      tip: (
        ko: "이어쓰기는 현재 앱 실행 중 임시 보관입니다. 다른 기기나 새로고침 후에도 필요하면 요청서를 서버에 저장하세요. 등록증은 공개 상품 사진과 다르게 다룹니다.",
        en: "Continue later keeps work only in the current app session. Save the request for other devices or after a refresh. Registration certificates are handled separately from public product photos."
      ),
      question: (
        ko: "새로고침 후에도 요청서를 보려면?",
        en: "How do you keep a request after a refresh?"
      ),
      answers: [
        (ko: "검토한 요청서를 저장합니다.", en: "Save the reviewed request."),
        (
          ko: "현재 실행 중인 이어쓰기만 사용합니다.",
          en: "Rely only on Continue later in the current session."
        )
      ],
      correctAnswer: 0,
      explanation: (
        ko: "이어쓰기는 현재 앱 실행 중 임시 보관입니다. 다른 기기나 새로고침 후에도 필요하면 요청서를 서버에 저장하세요. 등록증은 공개 상품 사진과 다르게 다룹니다.",
        en: "Continue later keeps work only in the current app session. Save the request for other devices or after a refresh. Registration certificates are handled separately from public product photos."
      ),
      destination: GuideDestination.purchases,
      minutes: 3),
  GuideLesson(
      id: "buy-ledger",
      audience: GuideAudience.professional,
      title: (ko: "전달 후 대장과 재주문", en: "Track, search and request again"),
      goal: (
        ko: "전달 사실을 기록하고 이전 요청을 재사용합니다.",
        en: "Record confirmed delivery of the request and reuse past items."
      ),
      outcome: (
        ko: "상태가 정리된 요청 이력과 다음 초안",
        en: "An organized request history and a new draft"
      ),
      steps: [
        (
          title: (ko: "수신자 확인 후 공유", en: "Check the recipient before sharing"),
          body: (
            ko: "저장한 요청서를 열어 카카오톡 등 공유 대상을 고르고 수신자·내용을 확인한 뒤 직접 발송합니다.",
            en: "Open a saved request, choose a sharing destination such as KakaoTalk, confirm recipient and content, then send yourself."
          )
        ),
        (
          title: (ko: "확인한 상태 기록하기", en: "Record confirmed status"),
          body: (
            ko: "준비 중·진행 중·완료에서 요청을 찾고 실제 전달·수락 확인·입고 사실을 기록합니다. 공유창을 열었다고 전달이 완료되지는 않습니다.",
            en: "Find requests under Preparing, In progress or Completed and record actual sharing, acceptance and receipt. Opening a share sheet does not confirm sending."
          )
        ),
        (
          title: (
            ko: "대장 조회와 이전 요청 재사용",
            en: "Search the ledger and reuse requests"
          ),
          body: (
            ko: "대장에서 기간·상태·거래처로 찾고 PDF/CSV로 출력합니다. 이전 요청을 복제할 때는 현재 가격·수량·납품일을 다시 확인하세요.",
            en: "Filter the ledger by date, status and supplier, then export PDF/CSV. When copying a request, recheck current prices, quantities and delivery date."
          )
        )
      ],
      tip: (
        ko: "수락·입고 상태는 구매자가 확인해 기록합니다. 자동 주문·결제·배송 추적·조리 재고 관리는 제공하지 않습니다.",
        en: "Acceptance and receipt are recorded by the buyer after confirmation. This is not automatic ordering, payment, delivery tracking or cooking-stock management."
      ),
      question: (
        ko: "공유창을 열었으면 발송 완료인가요?",
        en: "Does opening the share sheet mean the request was sent?"
      ),
      answers: [
        (
          ko: "공유창을 여는 순간 자동 완료됩니다.",
          en: "It is completed automatically when the share sheet opens."
        ),
        (
          ko: "실제 수신자와 전달을 확인한 뒤 상태를 기록합니다.",
          en: "Confirm the recipient and actual sending, then record the status."
        )
      ],
      correctAnswer: 1,
      explanation: (
        ko: "수락·입고 상태는 구매자가 확인해 기록합니다. 자동 주문·결제·배송 추적·조리 재고 관리는 제공하지 않습니다.",
        en: "Acceptance and receipt are recorded by the buyer after confirmation. This is not automatic ordering, payment, delivery tracking or cooking-stock management."
      ),
      destination: GuideDestination.ledger,
      minutes: 3),
  GuideLesson(
      id: "supplier-profile",
      audience: GuideAudience.supplier,
      title: (ko: "업체 정보부터 등록하기", en: "Register your business profile"),
      goal: (
        ko: "필수 정보만으로 첫 등록을 시작합니다.",
        en: "Begin with the required business information."
      ),
      outcome: (ko: "비공개로 저장한 업체 소개", en: "A privately saved business profile"),
      steps: [
        (
          title: (ko: "필수 정보 입력", en: "Enter required details"),
          body: (
            ko: "로그인 후 업체·상품에서 업체명·담당자·공개 연락처·소재 지역·배송 지역을 입력합니다.",
            en: "Sign in and open Business & products. Enter business name, contact name, public phone, business region and delivery regions."
          )
        ),
        (
          title: (ko: "선택 정보 보완", en: "Add optional details"),
          body: (
            ko: "주소·홈페이지나 카카오 채널·업체 소개를 추가하면 구매자가 조건을 확인하기 쉽습니다.",
            en: "Add an address, website or Kakao channel and a business introduction to help buyers evaluate your terms."
          )
        ),
        (
          title: (ko: "비공개 저장", en: "Save privately"),
          body: (
            ko: "입력 내용을 저장하고 다음 상품 등록으로 이동합니다. 공개하기를 완료하기 전에는 공개 목록에 노출하지 않습니다.",
            en: "Save the profile, then register products. It will not appear in the public directory until you publish it."
          )
        )
      ],
      tip: (
        ko: "공개 연락처에는 실제 업무용으로 공개해도 되는 정보를 입력하세요. 예제에는 실제 연락처를 쓰지 않아도 됩니다.",
        en: "Use a business contact that you intend to make public. You do not need real contact details for the training example."
      ),
      question: (
        ko: "처음 등록하는 업체 정보는 어떻게 준비하나요?",
        en: "How do you prepare your first business listing?"
      ),
      answers: [
        (
          ko: "필수 연락·지역 정보를 입력하고 비공개로 저장합니다.",
          en: "Enter required contact and region details, then save privately."
        ),
        (
          ko: "상품이나 연락처 없이 바로 공개합니다.",
          en: "Publish immediately without products or contact details."
        )
      ],
      correctAnswer: 0,
      explanation: (
        ko: "공개 연락처에는 실제 업무용으로 공개해도 되는 정보를 입력하세요. 예제에는 실제 연락처를 쓰지 않아도 됩니다.",
        en: "Use a business contact that you intend to make public. You do not need real contact details for the training example."
      ),
      destination: GuideDestination.business,
      minutes: 3),
  GuideLesson(
      id: "supplier-product",
      audience: GuideAudience.supplier,
      title: (ko: "상품과 사진 등록하기", en: "Add products and photos"),
      goal: (
        ko: "대표 취급상품 하나를 등록해 봅니다.",
        en: "Start with one representative product."
      ),
      outcome: (
        ko: "사진·분류·설명이 갖춰진 상품",
        en: "A product with photo, categories and description"
      ),
      steps: [
        (
          title: (ko: "찾기 쉬운 상품 이름", en: "Use a searchable product name"),
          body: (
            ko: "상품명과 대분류·소분류를 선택하고 필요한 별칭·브랜드를 입력합니다.",
            en: "Enter a product name and select its category and subcategory. Add useful aliases and a brand if needed."
          )
        ),
        (
          title: (ko: "실제 상품 사진", en: "Add a product photo"),
          body: (
            ko: "상품을 알아볼 수 있는 사진을 선택하고 업로드 완료를 확인합니다. 사업자등록증을 상품 사진으로 올리지 마세요.",
            en: "Select a recognizable product photo and confirm the upload. Do not use a business registration certificate as a product photo."
          )
        ),
        (
          title: (ko: "원산지와 보관 조건", en: "Record origin and storage"),
          body: (
            ko: "원산지·수입 국가·보관 방식·상품 설명을 실제 취급 조건에 맞게 기록합니다.",
            en: "Record origin, import country, storage method and description according to the product you supply."
          )
        )
      ],
      tip: (
        ko: "연습 화면의 이미지 표시는 가상 예시입니다. 실제 상품은 사용 권한이 있는 정확한 사진으로 등록하세요.",
        en: "Training images are simulated examples. Use accurate photos that you have permission to publish for real products."
      ),
      question: (
        ko: "상품 사진에는 무엇을 올리나요?",
        en: "What should a product photo show?"
      ),
      answers: [
        (
          ko: "상품 대신 사업자등록증 사진을 올립니다.",
          en: "A business certificate instead of the product."
        ),
        (
          ko: "구매자가 품목과 상태를 알 수 있는 상품 사진입니다.",
          en: "The product, so buyers can identify the item and its condition."
        )
      ],
      correctAnswer: 1,
      explanation: (
        ko: "연습 화면의 이미지 표시는 가상 예시입니다. 실제 상품은 사용 권한이 있는 정확한 사진으로 등록하세요.",
        en: "Training images are simulated examples. Use accurate photos that you have permission to publish for real products."
      ),
      destination: GuideDestination.business,
      minutes: 3),
  GuideLesson(
      id: "supplier-pack",
      audience: GuideAudience.supplier,
      title: (ko: "규격·단위·가격 정하기", en: "Set pack sizes and prices"),
      goal: (
        ko: "구매자가 비교할 수 있게 판매 기준을 명확히 합니다.",
        en: "Make selling terms clear enough for buyers to compare."
      ),
      outcome: (
        ko: "판매 단위와 내용량이 분리된 상품 규격",
        en: "A product with separate selling unit and content amount"
      ),
      steps: [
        (
          title: (ko: "판매 단위와 내용량", en: "Selling unit and contents"),
          body: (
            ko: "한 상자에 5kg이면 판매 단위는 상자, 내용량은 5, 내용 단위는 kg로 입력합니다.",
            en: "For a five-kilogram box, set selling unit to box, content amount to five and content unit to kg."
          )
        ),
        (
          title: (ko: "최소 포장 수와 가격", en: "Minimum packs and price"),
          body: (
            ko: "최소 구매 포장 수와 판매 단위 1개당 가격을 입력합니다. 가격 유효기간과 세금 포함 여부도 확인하세요.",
            en: "Enter minimum pack count and the price per one selling unit. Check price validity and whether tax is included."
          )
        ),
        (
          title: (ko: "배송 조건 확인", en: "Check delivery terms"),
          body: (
            ko: "업체의 배송비·무료배송 기준·최소 주문금액을 확인합니다. 알 수 없는 금액을 0원으로 입력하지 마세요.",
            en: "Check shipping fee, free-shipping threshold and minimum order value. Do not enter zero when a cost is unknown."
          )
        )
      ],
      tip: (
        ko: "가격이 미등록이거나 유효기간이 지났으면 확정 가격처럼 안내하지 않습니다. 조리 단위는 구매자의 레시피에서 관리합니다.",
        en: "An absent or expired price is not a confirmed quote. Cooking units are managed in the buyer’s recipe."
      ),
      question: (
        ko: "한 상자에 5kg이면 어떻게 입력하나요?",
        en: "How do you describe a box containing 5 kg?"
      ),
      answers: [
        (
          ko: "판매 단위 상자, 내용량 5, 내용 단위 kg입니다.",
          en: "Selling unit box, content quantity 5, content unit kg."
        ),
        (
          ko: "상자와 kg는 같은 단위이므로 내용량은 생략합니다.",
          en: "Box and kg are equivalent, so contents can be omitted."
        )
      ],
      correctAnswer: 0,
      explanation: (
        ko: "가격이 미등록이거나 유효기간이 지났으면 확정 가격처럼 안내하지 않습니다. 조리 단위는 구매자의 레시피에서 관리합니다.",
        en: "An absent or expired price is not a confirmed quote. Cooking units are managed in the buyer’s recipe."
      ),
      destination: GuideDestination.business,
      minutes: 3),
  GuideLesson(
      id: "supplier-publish",
      audience: GuideAudience.supplier,
      title: (ko: "확인하고 회원에게 공개하기", en: "Review and publish for members"),
      goal: (
        ko: "업체·상품·사진을 확인한 후 공개합니다.",
        en: "Review your profile, products and photos before publishing."
      ),
      outcome: (
        ko: "로그인한 회원이 찾을 수 있는 업체",
        en: "A business discoverable by signed-in members"
      ),
      steps: [
        (
          title: (ko: "공개 내용 검토", en: "Review public information"),
          body: (
            ko: "연락처·배송 지역과 판매할 상품의 사진·규격·활성 상태를 점검합니다.",
            en: "Check public contact details, delivery regions, product photos, pack sizes and active status."
          )
        ),
        (
          title: (ko: "공개하기 실행", en: "Publish your listing"),
          body: (
            ko: "업체 화면에서 공개하기를 눌러 서버의 필수 조건 검사를 통과하면 회원 목록에 표시됩니다.",
            en: "Choose Publish on the business page. Once required server checks pass, the listing is shown to members."
          )
        ),
        (
          title: (ko: "검색 결과 확인", en: "Check the directory"),
          body: (
            ko: "공급업체 찾기에서 상품명·분류·배송 지역으로 찾아 실제 노출 내용을 확인하세요.",
            en: "Use Find suppliers to search by product, category and delivery region, and review your listing."
          )
        )
      ],
      tip: (
        ko: "공개 범위는 로그인한 무료·유료 모든 회원입니다. 공개 등록이 관리자 검증이나 거래 보증을 뜻하지는 않습니다.",
        en: "Published information is visible to all signed-in free and paid members. Publication is not administrator verification or a trading guarantee."
      ),
      question: (
        ko: "공개한 업체·상품은 누가 볼 수 있나요?",
        en: "Who can see a published business and its products?"
      ),
      answers: [
        (ko: "등록한 업체 본인만 볼 수 있습니다.", en: "Only the business owner."),
        (ko: "로그인한 무료·유료 회원 모두입니다.", en: "All signed-in free and paid members.")
      ],
      correctAnswer: 1,
      explanation: (
        ko: "공개 범위는 로그인한 무료·유료 모든 회원입니다. 공개 등록이 관리자 검증이나 거래 보증을 뜻하지는 않습니다.",
        en: "Published information is visible to all signed-in free and paid members. Publication is not administrator verification or a trading guarantee."
      ),
      destination: GuideDestination.business,
      minutes: 3),
  GuideLesson(
      id: "supplier-update",
      audience: GuideAudience.supplier,
      title: (ko: "가격과 공개 정보 관리하기", en: "Maintain prices and listings"),
      goal: (
        ko: "거래 조건이 바뀌면 최신 정보로 수정합니다.",
        en: "Update listings when your trading terms change."
      ),
      outcome: (
        ko: "현재 조건이 반영된 업체·상품 정보",
        en: "Business and product details matching current terms"
      ),
      steps: [
        (
          title: (ko: "가격·규격 수정", en: "Update prices and pack sizes"),
          body: (
            ko: "업체·상품에서 해당 상품을 열어 가격·유효기간·내용량을 수정하고 저장합니다.",
            en: "Open the product under Business & products, update price, validity and content amount, then save."
          )
        ),
        (
          title: (ko: "판매 중단 상품 관리", en: "Manage unavailable products"),
          body: (
            ko: "더 이상 취급하지 않는 상품은 활성 상태를 해제하세요. 업체 전체를 숨길 때는 공개 상태를 변경합니다.",
            en: "Deactivate products you no longer supply. Change the business publication status to hide the entire listing."
          )
        ),
        (
          title: (ko: "수정 결과 확인", en: "Check the updated listing"),
          body: (
            ko: "공개 목록에 반영됐는지 확인하고 기존 협의 건은 구매자와 별도로 확인합니다. 과거 요청서 내용이 자동 변경되는 것으로 안내하지 마세요.",
            en: "Confirm the directory is updated and check existing agreements with buyers separately. Do not assume historical requests change automatically."
          )
        )
      ],
      tip: (
        ko: "현재 공급업체 기능은 업체·상품 공개 관리입니다. 주문 수신함·배송·정산을 자동 처리하는 기능은 아닙니다.",
        en: "Current supplier tools manage business and product listings. They do not automatically handle an order inbox, delivery or settlement."
      ),
      question: (
        ko: "판매를 중지하면 과거 요청서는 어떻게 되나요?",
        en: "What happens to past requests when you stop selling a product?"
      ),
      answers: [
        (
          ko: "과거 요청은 유지하고 현재 판매 상태를 바꿉니다.",
          en: "Past requests are retained while the current sale status changes."
        ),
        (
          ko: "기존 요청서도 모두 새 가격으로 바뀝니다.",
          en: "Every past request is rewritten at the new price."
        )
      ],
      correctAnswer: 0,
      explanation: (
        ko: "현재 공급업체 기능은 업체·상품 공개 관리입니다. 주문 수신함·배송·정산을 자동 처리하는 기능은 아닙니다.",
        en: "Current supplier tools manage business and product listings. They do not automatically handle an order inbox, delivery or settlement."
      ),
      destination: GuideDestination.business,
      minutes: 3),
];
