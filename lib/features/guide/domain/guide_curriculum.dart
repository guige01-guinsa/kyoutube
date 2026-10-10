part 'guide_workflows.dart';

typedef GuideText = ({String ko, String en});
typedef GuideStep = ({GuideText title, GuideText body});

enum GuideAudience { professional, home, supplier }

enum GuideTrack { purchasing, cooking, management }

enum GuidePractice { none, scale, yieldLoss, pricing }

enum GuideDestination {
  search,
  youtube,
  recipes,
  chef,
  sales,
  shopping,
  suppliers,
  directory,
  planner,
  purchases,
  ledger,
  business,
  ingredients
}

class GuideCourse {
  const GuideCourse(
      {required this.title,
      required this.hero,
      required this.intro,
      required this.flow});
  final GuideText title, hero, intro, flow;
}

class GuideLesson {
  const GuideLesson(
      {required this.id,
      required this.audience,
      required this.title,
      required this.goal,
      required this.outcome,
      required this.steps,
      required this.tip,
      required this.question,
      required this.answers,
      required this.correctAnswer,
      required this.explanation,
      required this.destination,
      required this.minutes,
      this.access = 'account',
      this.practice = GuidePractice.none});
  final String id, access;
  final GuideAudience audience;
  final GuideText title, goal, outcome, tip, question, explanation;
  final List<GuideStep> steps;
  final List<GuideText> answers;
  final int correctAnswer, minutes;
  final GuideDestination destination;
  final GuidePractice practice;
}

List<GuideLesson> guideLessonsFor(GuideAudience audience) => guideLessons
    .where((lesson) => lesson.audience == audience)
    .toList(growable: false);

const guideCourses = <GuideAudience, GuideCourse>{
  GuideAudience.supplier: GuideCourse(title: (
    ko: '공급업체',
    en: 'Food suppliers'
  ), hero: (
    ko: '내 상품을,\n구매자가 찾기 쉽게.',
    en: 'Your products.\nReady to be discovered.'
  ), intro: (
    ko: '업체 소개부터 상품과 사진, 구매 규격, 회원 공개까지 하나씩 준비하세요.',
    en: 'Prepare your business profile, products, photos and pack details, then publish for members.'
  ), flow: (
    ko: '업체 정보 → 상품과 규격 → 공개와 관리',
    en: 'Business → Products & packs → Publish & manage'
  )),
  GuideAudience.professional: GuideCourse(title: (
    ko: '업소·전문가',
    en: 'Chefs & business'
  ), hero: (
    ko: '메뉴 하나로,\n주방 운영의 기준을.',
    en: 'One menu.\nA standard for service.'
  ), intro: (
    ko: '표준 레시피에서 인분·수율·원가, 매출과 구매 요청까지. 지금 필요한 주방 업무를 골라 익혀보세요.',
    en: 'From a standard recipe to servings, yield, costs, sales and supplier requests. Choose the kitchen task you need today.'
  ), flow: (
    ko: '기준 만들기 → 원가와 매출 → 구매와 개선',
    en: 'Set a standard → Cost and sales → Purchase and improve'
  )),
  GuideAudience.home: GuideCourse(title: (
    ko: '일반 사용자',
    en: 'Everyday cooks'
  ), hero: (
    ko: '오늘의 한 끼를,\n내 레시피로.',
    en: 'Today’s meal.\nYour own recipe.'
  ), intro: (
    ko: '영상에서 요리를 찾고 초안을 검토해 저장하세요. 필요한 재료를 준비하고 다음 요리에 경험을 남깁니다.',
    en: 'Find a cooking video, review and save a draft, prepare ingredients and keep your experience for next time.'
  ), flow: (
    ko: '찾기 → 검토와 저장 → 장보기와 조리',
    en: 'Find → Review and save → Shop and cook'
  )),
};

const guideLabels = <String, GuideText>{
  'title': (ko: '체험 튜토리얼', en: 'Hands-on tutorials'),
  'choose': (ko: '나에게 맞는 과정', en: 'Choose your course'),
  'progress': (ko: '이 과정의 학습 진도', en: 'Your course progress'),
  'lessons': (ko: '개 실습', en: 'lessons'),
  'saved': (
    ko: '과정 선택과 학습 진도는 이 기기에 저장됩니다.',
    en: 'Your course choice and progress are saved on this device.'
  ),
  'saveError': (
    ko: '진도를 저장하지 못했습니다. 현재 화면에서는 계속 학습할 수 있습니다.',
    en: 'Progress could not be saved. You can keep learning in this session.'
  ),
  'start': (ko: '첫 실습 시작', en: 'Start the first lesson'),
  'continue': (ko: '이어서 배우기', en: 'Continue learning'),
  'review': (ko: '다시 둘러보기', en: 'Review the course'),
  'complete': (ko: '실습 완료', en: 'Complete lesson'),
  'done': (ko: '완료', en: 'Completed'),
  'steps': (ko: '실제 화면에서 따라 하기', en: 'Follow the steps in the app'),
  'stepHint': (
    ko: '직접 해본 항목을 체크하세요. 체크만으로 레시피·매출·장보기 데이터가 바뀌지는 않습니다.',
    en: 'Check what you have tried. Checkboxes do not change recipes, sales or shopping data.'
  ),
  'tip': (ko: '실무에서 확인할 점', en: 'Check in practice'),
  'quiz': (ko: '핵심 확인 · 선택', en: 'Knowledge check · optional'),
  'retry': (ko: '정답을 다시 확인해 보세요.', en: 'Review your answer and try again.'),
  'correct': (ko: '핵심을 이해했습니다.', en: 'You have the key idea.'),
  'return': (
    ko: '실습 후 뒤로 가기로 이 수업에 돌아올 수 있습니다.',
    en: 'Use Back after practicing to return to this lesson.'
  ),
  'unlock': (
    ko: '예제를 체험하거나 직접 해본 항목을 모두 체크하면 완료할 수 있습니다. 확인 문제는 선택입니다.',
    en: 'Try the example or check every step you have practiced to complete. The knowledge check is optional.'
  ),
  'next': (ko: '다음 실습', en: 'Next lesson'),
  'overview': (ko: '과정 목록으로', en: 'Back to the course'),
  'outcome': (ko: '이번 실습의 결과물', en: 'What you will prepare'),
  'finished': (
    ko: '이 과정을 마쳤습니다. 필요한 실습을 언제든 다시 확인하세요.',
    en: 'You have finished this course. Revisit any lesson when you need it.'
  ),
  'previewNote': (
    ko: '예제로 먼저 배우세요. 실제 저장·AI 이용·원가와 매출 관리는 로그인과 현재 요금제 권한을 따릅니다.',
    en: 'Learn with examples first. Saving, AI, cost and sales tools follow sign-in and current plan access.'
  ),
  'example': (ko: '숫자를 바꿔 보는 연습', en: 'Try changing the numbers'),
  'exampleNote': (
    ko: '연습용 KRW 예제 · 실제 레시피나 매출에 저장되지 않습니다.',
    en: 'Training example in KRW. Nothing is saved to recipes or sales.'
  ),
  'sampleMenu': (ko: '연습 메뉴 · 닭고기 덮밥', en: 'Practice menu · Chicken rice bowl'),
  'scaleIntro': (
    ko: '기준 4인분 · 손질 후 닭고기 800g. 목표 인분을 골라 사용량 변화를 확인하세요.',
    en: 'Base: four servings and 800 g edible chicken. Choose target servings to see the scaled usage.'
  ),
  'yieldIntro': (
    ko: '손질 후 필요한 양은 800g입니다. 수율을 바꿔 구매 필요량을 확인하세요.',
    en: 'You need 800 g after trimming. Change edible yield to see purchase needs.'
  ),
  'pricingIntro': (
    ko: '1인분 원가 3,000원입니다. 가산율을 바꿔 계산 판매가와 10개 판매 예시를 확인하세요.',
    en: 'Cost is KRW 3,000 per serving. Change markup to see the price and an example of ten sales.'
  ),
  'servings': (ko: '인분', en: 'servings'),
  'usage': (ko: '환산 사용량', en: 'Scaled usage'),
  'purchase': (ko: '원가 계산용 손질 전 분량', en: 'Pre-trim quantity for costing'),
  'yield': (ko: '손질 수율', en: 'Edible yield'),
  'markup': (ko: '원가 가산율', en: 'Cost markup'),
  'price': (ko: '계산 판매가', en: 'Calculated price'),
  'revenue': (ko: '10개 판매 매출', en: 'Revenue for 10'),
  'difference': (ko: '기록 원가 차감 후 차액', en: 'Difference after recorded cost'),
  'marginNote': (
    ko: '차액은 미포함 비용을 차감하기 전이며 순이익이 아닙니다.',
    en: 'The difference is before unentered costs; it is not net profit.'
  ),
  'account': (ko: '실제 저장은 로그인 후', en: 'Sign in to save real work'),
  'open': (ko: '로그인 없이 둘러보기', en: 'Explore without signing in'),
  'plan': (
    ko: '실제 원가·매출은 요금제 권한 필요',
    en: 'Cost and sales tools need plan access'
  ),
  'ai': (ko: 'AI 이용 조건·남은 횟수 확인', en: 'Check AI access and remaining uses'),
  'route-search': (ko: '검색 화면 열기', en: 'Open Search'),
  'route-youtube': (ko: '영상 검색 열기', en: 'Open video search'),
  'route-recipes': (ko: '내 레시피 열기', en: 'Open My recipes'),
  'route-chef': (ko: '셰프 작업실 열기', en: 'Open Chef'),
  'route-sales': (ko: '매출 현황 열기', en: 'Open Sales'),
  'route-shopping': (ko: '장보기 열기', en: 'Open Shopping'),
  'route-suppliers': (ko: '구매 요청서 열기', en: 'Open supplier requests'),
  'route-directory': (ko: '공급업체 찾기', en: 'Find suppliers'),
  'route-planner': (ko: '업체 비교 시작', en: 'Compare suppliers'),
  'route-purchases': (ko: '구매 열기', en: 'Open Purchasing'),
  'route-ledger': (ko: '구매요청 대장 열기', en: 'Open request ledger'),
  'route-business': (ko: '업체·상품 열기', en: 'Open Business & products'),
  'route-ingredients': (ko: '재료 검색 열기', en: 'Open ingredient search'),
};

const guideLessons = <GuideLesson>[
  GuideLesson(
      id: 'pro-standard',
      audience: GuideAudience.professional,
      title: (ko: '표준 레시피부터 만들기', en: 'Build your standard recipe'),
      goal: (
        ko: '자주 판매하는 메뉴 하나로 시작합니다.',
        en: 'Start with one dish you serve often.'
      ),
      outcome: (
        ko: '4인분 기준의 재료·조리 순서가 담긴 내 레시피 1개',
        en: 'One saved recipe with ingredients and steps for four servings'
      ),
      tip: (
        ko: '실제 업장의 기준값을 사용하세요. 이 과정의 수치와 예제는 연습용이며 완성된 조리법이나 권장 판매가가 아닙니다.',
        en: 'Use your own kitchen standards. Numbers in this course are training examples, not a complete cooking method or a recommended price.'
      ),
      question: (
        ko: '표준 레시피의 재료량은 어떤 기준으로 맞추나요?',
        en: 'What should every ingredient amount refer to?'
      ),
      explanation: (
        ko: '기준 인분이 같아야 이후 환산과 원가 비교가 의미를 갖습니다.',
        en: 'A shared baseline makes later scaling and cost comparisons meaningful.'
      ),
      steps: [
        (
          title: (ko: '기준 메뉴 고르기', en: 'Choose your reference dish'),
          body: (
            ko: '처음에는 자주 만드는 메뉴 하나를 고릅니다. 예: 닭고기 덮밥. 완성 인분과 1인분 제공량을 먼저 정하세요.',
            en: 'Choose a familiar dish, such as a chicken rice bowl. Define the batch size and the amount served in one portion.'
          )
        ),
        (
          title: (ko: '내 레시피 준비', en: 'Prepare a personal recipe'),
          body: (
            ko: '내 레시피에서 새 레시피를 만들거나 검토한 영상 초안을 저장하세요. 제목·설명에 기준 4인분을 기록하고 모든 재료를 같은 기준으로 맞춥니다.',
            en: 'Create a recipe in My recipes or save a reviewed video draft. Record a four-serving baseline in its title or summary and use that basis for every ingredient.'
          )
        ),
        (
          title: (ko: '재현할 수 있게 기록', en: 'Record a repeatable method'),
          body: (
            ko: '손질 상태, 사용량과 단위, 가열 순서, 완성 판단 기준을 적습니다. 편집을 잘못했다면 실행 취소·다시 실행 아이콘으로 복구하세요.',
            en: 'Record preparation state, amounts, units, heating order and finishing cues. Use the undo and redo icons to recover an editing mistake.'
          )
        ),
        (
          title: (ko: '저장하고 다시 확인', en: 'Save and check again'),
          body: (
            ko: '저장한 레시피를 다시 열어 누락을 확인합니다. 셰프 메뉴에서 이 레시피를 선택하면 인분·수율·원가 작업을 이어갈 수 있습니다.',
            en: 'Reopen the saved recipe and check for omissions. Select it in Chef to continue with servings, yield and costing.'
          )
        ),
      ],
      answers: [
        (
          ko: '같은 기준 인분과 제공량',
          en: 'The same baseline servings and portion size'
        ),
        (ko: '재료마다 다른 조리 분량', en: 'A different batch size for each ingredient')
      ],
      correctAnswer: 0,
      destination: GuideDestination.recipes,
      minutes: 4,
      access: 'account',
      practice: GuidePractice.none),
  GuideLesson(
      id: 'pro-scale',
      audience: GuideAudience.professional,
      title: (ko: '인분을 바꾸고 배합 확인', en: 'Scale servings and review quantities'),
      goal: (
        ko: '4인분 기준을 20인분 준비로 바꿉니다.',
        en: 'Turn a four-serving recipe into prep for twenty.'
      ),
      outcome: (
        ko: '목표 인분과 환산 사용량을 확인한 작업본',
        en: 'A working recipe with checked target servings and quantities'
      ),
      tip: (
        ko: '기준 인분은 재료량이 작성된 기준입니다. 목표만 바꿀 때 기준 인분까지 함께 바꾸면 원하는 환산 배수가 달라집니다.',
        en: 'Base servings describe the original ingredient list. Changing both base and target can unintentionally change your scaling ratio.'
      ),
      question: (
        ko: '4인분에 800g이면 20인분의 사용량은?',
        en: 'If four servings use 800 g, how much do twenty use?'
      ),
      explanation: (
        ko: '20 ÷ 4 = 5배이므로 800 × 5 = 4,000g입니다.',
        en: '20 ÷ 4 = 5, so 800 × 5 = 4,000 g.'
      ),
      steps: [
        (
          title: (ko: '셰프 작업실 열기', en: 'Open Chef'),
          body: (
            ko: '셰프에서 작업할 레시피를 선택합니다. 기준 인분에는 원본 레시피 분량인 4를 입력하세요.',
            en: 'Choose your recipe in Chef. Set base servings to 4, matching the original ingredient quantities.'
          )
        ),
        (
          title: (ko: '목표 인분 입력', en: 'Set target servings'),
          body: (
            ko: '목표 인분을 20으로 바꿉니다. 기준 4인분에 닭고기 800g이면 환산 사용량은 4,000g입니다. 위 예제로 먼저 확인해 보세요.',
            en: 'Change target servings to 20. Chicken at 800 g for four servings scales to 4,000 g. Try the example above first.'
          )
        ),
        (
          title: (ko: '배합과 가열을 구분', en: 'Separate scaling from cooking'),
          body: (
            ko: '환산 사용량과 필요한 구매량을 구분해 봅니다. 시간·온도·불 세기·팬 크기는 인분에 비례해 자동 결정되는 값이 아니므로 실제 조리로 검토하세요.',
            en: 'Distinguish scaled usage from purchase needs. Time, temperature, heat and pan size need a separate cooking review; they are not automatically multiplied by servings.'
          )
        ),
        (
          title: (ko: '작업 저장', en: 'Save your work'),
          body: (
            ko: '목표 인분과 재료 단위를 확인한 뒤 작업 저장을 누릅니다. 다시 열어 값이 반영됐는지 확인하세요.',
            en: 'Check servings and units, then save your work. Reopen it to confirm the values.'
          )
        ),
      ],
      answers: [(ko: '4,000g', en: '4,000 g'), (ko: '800g', en: '800 g')],
      correctAnswer: 0,
      destination: GuideDestination.chef,
      minutes: 3,
      access: 'account',
      practice: GuidePractice.scale),
  GuideLesson(
      id: 'pro-yield',
      audience: GuideAudience.professional,
      title: (ko: '사용 단위·구매 단위·수율', en: 'Connect units and edible yield'),
      goal: (
        ko: '손질 후 사용량을 실제 구매량으로 연결합니다.',
        en: 'Connect edible quantity to the amount you must buy.'
      ),
      outcome: (
        ko: '단위와 환산 기준이 정리된 재료 1개',
        en: 'One ingredient with verified units and conversion'
      ),
      tip: (
        ko: '부피와 무게를 임의로 1:1로 바꾸지 마세요. 손질 수율과 완성 중량 수율은 다른 값입니다. 포장 크기와 실제 재료 상태를 기준으로 기록합니다.',
        en: 'Do not assume volume and weight are interchangeable. Edible yield and finished production yield are different measures. Use the actual package size and ingredient condition.'
      ),
      question: (
        ko: '사용 800g, 손질 수율 80%의 구매 필요량은?',
        en: 'What purchase quantity gives 800 g at 80% edible yield?'
      ),
      explanation: (
        ko: '800 ÷ 0.8 = 1,000g입니다. 손실을 사용량에서 한 번 더 빼지 않습니다.',
        en: '800 ÷ 0.8 = 1,000 g. Do not subtract trimming loss from the edible amount again.'
      ),
      steps: [
        (
          title: (ko: '사용 단위 선택', en: 'Choose the usage unit'),
          body: (
            ko: '재료 수정에서 기준 사용량과 사용 단위를 맞춥니다. 무게·부피·개수·포장 분류를 선택하고, 필요한 단위가 없다면 직접 입력하세요.',
            en: 'In Edit ingredient, set the base quantity and usage unit. Choose weight, volume, count or packaging, or enter a custom unit.'
          )
        ),
        (
          title: (ko: '손질 수율 입력', en: 'Enter edible yield'),
          body: (
            ko: '손질 후 쓸 양이 800g이고 수율이 80%라면 필요한 구매량은 1,000g입니다. 사용량에는 손질 후 분량을 입력합니다.',
            en: 'For 800 g of edible ingredient at 80% yield, purchase needs are 1,000 g. Usage quantity means the amount after trimming.'
          )
        ),
        (
          title: (ko: '없는 환산 기준 직접 등록', en: 'Supply missing conversions'),
          body: (
            ko: 'g과 kg처럼 같은 종류는 자동 환산됩니다. 팩과 g처럼 기준이 없으면 안내에 따라 구매 1팩 = 사용량 400g과 같이 실제 포장 기준을 입력하세요.',
            en: 'Compatible units such as g and kg convert automatically. For a pack-to-g conversion, follow the prompt and enter the actual size, for example one pack = 400 g.'
          )
        ),
        (
          title: (ko: '바꾼 단위 다시 검토', en: 'Review changed units'),
          body: (
            ko: '구매·사용 단위를 바꾸면 직접 입력한 환산 기준을 다시 확인합니다. 환산 기준이 없으면 원가가 완성되지 않으므로 저장 전 누락 표시를 해결하세요.',
            en: 'Recheck the manual conversion after changing either unit. Missing conversion leaves costing incomplete, so resolve the missing information before saving.'
          )
        ),
      ],
      answers: [(ko: '640g', en: '640 g'), (ko: '1,000g', en: '1,000 g')],
      correctAnswer: 1,
      destination: GuideDestination.chef,
      minutes: 4,
      access: 'account',
      practice: GuidePractice.yieldLoss),
  GuideLesson(
      id: 'pro-cost',
      audience: GuideAudience.professional,
      title: (ko: '단가와 추가 비용 반영', en: 'Update prices and additional costs'),
      goal: (
        ko: '입력한 비용의 범위를 분명하게 만듭니다.',
        en: 'Make the scope of your recipe cost explicit.'
      ),
      outcome: (
        ko: '누락 항목을 확인한 1인분 원가',
        en: 'A per-serving cost with missing inputs reviewed'
      ),
      tip: (
        ko: '원가·매출 관리에는 해당 요금제 권한이 필요합니다. 통화 표기를 바꾸는 것만으로 환율이 적용되지는 않습니다. 세금 처리나 손익 판단은 실제 업장 기준을 따르세요.',
        en: 'Cost and sales management require the relevant plan access. Changing the currency label does not perform foreign-exchange conversion. Use your actual business basis for tax and profit calculations.'
      ),
      question: (
        ko: '재료 원가가 대시로 표시된다면?',
        en: 'What should you do when ingredient cost shows a dash?'
      ),
      explanation: (
        ko: '누락된 원가를 0으로 취급하면 메뉴 원가가 낮게 계산됩니다.',
        en: 'Treating missing costs as zero understates the recipe cost.'
      ),
      steps: [
        (
          title: (ko: '구매 포장과 단가 입력', en: 'Enter the purchased pack'),
          body: (
            ko: '단가 바로 수정에서 구매 포장량·구매 단위·포장 구매가를 입력합니다. 1kg에 12,000원이면 포장량 1, 단위 kg, 구매가 12,000으로 기록하세요.',
            en: 'Use Quick price edit for pack quantity, purchase unit and pack price. For 1 kg costing KRW 12,000, enter 1, kg and 12,000.'
          )
        ),
        (
          title: (ko: '원가 누락부터 해결', en: 'Resolve missing costs'),
          body: (
            ko: '재료마다 단가·수율·환산 기준을 검토합니다. 값이 없어서 표시되는 대시는 무료 재료나 0원이라는 뜻이 아닙니다.',
            en: 'Review price, yield and conversion for every ingredient. A dash caused by missing information does not mean the ingredient is free.'
          )
        ),
        (
          title: (ko: '추가 비용을 항목으로 기록', en: 'Name each extra cost'),
          body: (
            ko: '추가 비용에 포장비·소스 등 필요한 항목을 직접 추가하거나 수정합니다. 기준 인분에 대한 금액을 입력하며 목표 인분에 맞춰 함께 환산됩니다.',
            en: 'Add or edit named costs such as packaging or sauce. Enter costs for the base batch; these scale with the target servings.'
          )
        ),
        (
          title: (ko: '원가 기준 저장', en: 'Save the cost basis'),
          body: (
            ko: '통화와 1인분 원가를 확인한 뒤 작업 저장을 누릅니다. 인건비·임대료·세금 등 어떤 비용을 포함했는지 작업 메모에도 남기세요.',
            en: 'Check the currency and cost per serving, then save. Record which labor, rent, tax or other costs you have included in your notes.'
          )
        ),
      ],
      answers: [
        (ko: '단가·환산 기준 등 누락을 확인', en: 'Check missing prices and conversions'),
        (ko: '원가 0원으로 간주', en: 'Treat it as a cost of zero')
      ],
      correctAnswer: 0,
      destination: GuideDestination.chef,
      minutes: 4,
      access: 'plan',
      practice: GuidePractice.none),
  GuideLesson(
      id: 'pro-pricing',
      audience: GuideAudience.professional,
      title: (ko: '원가 가산율로 판매가 계산', en: 'Calculate a price with markup'),
      goal: (
        ko: '원가 가산율과 실제 이익을 구분합니다.',
        en: 'Distinguish markup from actual business profit.'
      ),
      outcome: (
        ko: '선택한 가산율과 계산 판매가',
        en: 'A selected markup and calculated selling price'
      ),
      tip: (
        ko: '50% 원가 가산율은 매출 대비 50% 이익률이 아닙니다. 이 예제의 매출 대비 차액 비율은 약 33.3%이며, 원가에 포함하지 않은 비용은 별도입니다.',
        en: 'A 50% cost markup is not a 50% profit margin on sales. This example has a difference of about 33.3% of revenue, before any costs you have not included.'
      ),
      question: (
        ko: '원가 3,000원에 50%를 가산한 판매가는?',
        en: 'What price adds 50% to a cost of KRW 3,000?'
      ),
      explanation: (
        ko: '3,000 × 1.5 = 4,500원입니다.',
        en: '3,000 × 1.5 = KRW 4,500.'
      ),
      steps: [
        (
          title: (ko: '1인분 원가 확인', en: 'Check cost per serving'),
          body: (
            ko: '모든 재료 원가와 추가 비용을 입력한 뒤 1인분 원가를 확인합니다. 아래 실습은 원가 3,000원을 기준으로 합니다.',
            en: 'Complete ingredient and additional costs before checking cost per serving. The example above uses KRW 3,000.'
          )
        ),
        (
          title: (ko: '가산율 선택', en: 'Choose a markup'),
          body: (
            ko: '원가 가산율을 0~100%에서 선택합니다. 원가 3,000원에 50%를 더하면 계산 판매가는 4,500원입니다.',
            en: 'Select a markup from 0 to 100%. Adding 50% to a KRW 3,000 cost gives a calculated price of KRW 4,500.'
          )
        ),
        (
          title: (ko: '판매 조건 검토 후 저장', en: 'Review and save'),
          body: (
            ko: '계산 판매가와 업장의 실제 판매 조건을 비교하고 작업을 저장합니다. 포함하지 않은 비용이나 할인까지 계산에 반영됐다고 가정하지 마세요.',
            en: 'Compare the calculated price with how your business actually sells, then save. Do not assume unentered costs or discounts are included.'
          )
        ),
      ],
      answers: [
        (ko: '6,000원', en: 'KRW 6,000'),
        (ko: '4,500원', en: 'KRW 4,500')
      ],
      correctAnswer: 1,
      destination: GuideDestination.chef,
      minutes: 3,
      access: 'plan',
      practice: GuidePractice.pricing),
  GuideLesson(
      id: 'pro-sales',
      audience: GuideAudience.professional,
      title: (ko: '일·주·월 매출 기록 읽기', en: 'Read daily, weekly and monthly sales'),
      goal: (
        ko: '판매 수량과 기록 당시 원가로 결과를 봅니다.',
        en: 'Review sales against the cost recorded at the time.'
      ),
      outcome: (
        ko: '판매 기록 1건과 기간별 매출·예상이익 확인',
        en: 'One sales entry and reviewed period totals'
      ),
      tip: (
        ko: '예상이익은 기록된 매출액에서 기록된 원가를 뺀 값입니다. 회계상 순이익이나 POS 자동 집계가 아닙니다. 누락된 매출·비용은 사용자가 확인해야 합니다.',
        en: 'Estimated profit subtracts recorded costs from recorded revenue. It is not accounting net profit or an automatic POS feed. Review missing sales and costs yourself.'
      ),
      question: (
        ko: '원가 3,000원·판매가 4,500원으로 10개 판매하면 차액은?',
        en: 'At cost 3,000 and price 4,500 KRW, what is the difference for ten portions?'
      ),
      explanation: (
        ko: '(4,500 − 3,000) × 10 = 15,000원입니다.',
        en: '(4,500 − 3,000) × 10 = KRW 15,000.'
      ),
      steps: [
        (
          title: (ko: '판매 기준 저장', en: 'Save the selling basis'),
          body: (
            ko: '셰프 작업실에서 원가와 계산 판매가를 저장한 뒤 매출 현황을 엽니다. 실제 판매한 날짜와 메뉴를 선택하세요.',
            en: 'Save cost and calculated price in Chef, then open Sales. Select the actual sale date and menu.'
          )
        ),
        (
          title: (ko: '실제 판매 수량 기록', en: 'Record actual sales quantity'),
          body: (
            ko: '판매 수량과 적용된 판매가·원가를 확인해 기록합니다. 예: 4,500원 메뉴 10개는 매출 45,000원입니다.',
            en: 'Check quantity and the applied price and cost before recording. Ten portions sold at KRW 4,500 give revenue of KRW 45,000.'
          )
        ),
        (
          title: (
            ko: '기간과 통화를 맞춰 비교',
            en: 'Compare matching periods and currency'
          ),
          body: (
            ko: '일·주·월을 바꿔 판매 수량·매출액·예상이익을 살펴봅니다. 주간은 월요일부터이며 선택한 날짜와 통화를 함께 확인하세요.',
            en: 'Switch day, week and month to review quantity, revenue and estimated profit. Weeks begin on Monday; check the selected date and currency.'
          )
        ),
        (
          title: (ko: '오기 수정과 누락 검토', en: 'Correct entry errors'),
          body: (
            ko: '잘못 기록한 수량은 해당 판매 기록에서 수정합니다. 이후 레시피 단가를 바꾸더라도 과거 판매 기록의 원가가 자동 재작성되는 것으로 생각하지 마세요.',
            en: 'Edit an incorrect quantity in its sales entry. A later recipe price change does not automatically rewrite the cost stored in past sales.'
          )
        ),
      ],
      answers: [
        (ko: '15,000원, 미포함 비용은 별도', en: 'KRW 15,000, before unentered costs'),
        (ko: '45,000원 전부가 이익', en: 'All KRW 45,000 is profit')
      ],
      correctAnswer: 0,
      destination: GuideDestination.sales,
      minutes: 4,
      access: 'plan',
      practice: GuidePractice.none),
  GuideLesson(
      id: 'pro-versions',
      audience: GuideAudience.professional,
      title: (ko: '시험 배합과 버전 비교', en: 'Compare trials and recipe versions'),
      goal: (
        ko: '변경 이유를 남기고 기준을 비교합니다.',
        en: 'Record why a recipe changed and compare versions.'
      ),
      outcome: (
        ko: '이름과 변경 메모가 있는 두 버전 비교',
        en: 'Two named versions with a clear change note'
      ),
      tip: (
        ko: '버전 이름은 변경 내용을 알려주는 표식입니다. 원본 내 레시피의 설명과 셰프 작업본의 변경이 언제나 자동으로 일치한다고 가정하지 말고 필요한 내용을 각각 확인하세요.',
        en: 'A version name should explain the change. Check the original recipe and Chef work separately rather than assuming their descriptions are always synchronized.'
      ),
      question: (
        ko: '비교할 기준을 남기려면 어떤 기능을 쓰나요?',
        en: 'How do you preserve a comparison point?'
      ),
      explanation: (
        ko: '작업 저장과 비교용 버전 생성은 역할이 다릅니다.',
        en: 'Saving current work and creating a comparison snapshot serve different purposes.'
      ),
      steps: [
        (
          title: (ko: '현재 기준을 버전으로 남기기', en: 'Snapshot the current standard'),
          body: (
            ko: '작업 저장은 현재 작업본을 저장합니다. 비교 기준을 남기려면 새 버전 저장을 누르고 기준 배합처럼 알아보기 쉬운 이름을 입력하세요.',
            en: 'Save work updates the current working recipe. To preserve a comparison point, use Save new version and give it a recognizable name.'
          )
        ),
        (
          title: (ko: '한 번에 한 변수 조정', en: 'Change one variable at a time'),
          body: (
            ko: '시험할 재료량·수율·공정 중 한 가지를 바꾸고 실제 결과를 메모합니다. 다른 작업자의 동시 변경 경고가 뜨면 최신 작업을 먼저 확인하세요.',
            en: 'Change one ingredient amount, yield or method and note the result. If another edit causes a conflict warning, review the latest work first.'
          )
        ),
        (
          title: (ko: '시험 결과를 새 버전으로 저장', en: 'Save the trial as a version'),
          body: (
            ko: '새 버전 저장에서 시험 날짜나 변경 이유를 적습니다. 예: 2차 시험, 소스 사용량 조정. 아직 검토하지 않은 수치를 확정 기준처럼 기록하지 마세요.',
            en: 'Save another version with a trial date or reason, such as second trial: adjusted sauce amount. Distinguish tentative values from approved standards.'
          )
        ),
        (
          title: (ko: '두 버전 비교', en: 'Compare two versions'),
          body: (
            ko: '버전 관리에서 비교할 두 버전을 선택해 재료·인분·메모 등의 차이를 확인합니다. 단순히 비교 대상을 고르는 것만으로 작업본이 복원되는 것은 아닙니다.',
            en: 'In Version management, select two versions and review ingredient, serving and note differences. Selecting a comparison does not restore that version into your current work.'
          )
        ),
      ],
      answers: [
        (ko: '새 버전 저장', en: 'Save new version'),
        (ko: '비교할 버전만 선택', en: 'Only select a version to compare')
      ],
      correctAnswer: 0,
      destination: GuideDestination.chef,
      minutes: 4,
      access: 'account',
      practice: GuidePractice.none),
  GuideLesson(
      id: 'pro-ai',
      audience: GuideAudience.professional,
      title: (
        ko: '영상 아이디어를 검토한 초안으로',
        en: 'Turn video ideas into reviewed drafts'
      ),
      goal: (
        ko: 'AI를 메뉴 개발의 초안 도구로 사용합니다.',
        en: 'Use AI as a drafting tool for menu development.'
      ),
      outcome: (
        ko: '원본 근거와 사용자 수정을 구분한 초안',
        en: 'A draft that distinguishes source evidence from your changes'
      ),
      tip: (
        ko: '초안 생성 성공은 조리 정확도 보증이 아닙니다. 재생성 전에 직접 수정으로 해결할 수 있는지 살펴보고 현재 이용량을 확인하세요.',
        en: 'A successful draft is not a guarantee of cooking accuracy. Consider a manual edit before regenerating and check current usage.'
      ),
      question: (
        ko: 'YouTube 요약을 읽은 다음 앱에서 확인할 것은?',
        en: 'After reading a YouTube summary, what should you check in the app?'
      ),
      explanation: (
        ko: '외부에서 읽은 정보와 앱에 입력된 정보는 구분해야 합니다.',
        en: 'Information you read elsewhere is different from evidence supplied to the app.'
      ),
      steps: [
        (
          title: (ko: '설명이 자세한 영상 선택', en: 'Choose a well-described video'),
          body: (
            ko: '검색에서 요리명과 주재료를 함께 찾고 원본 설명을 확인합니다. 제목만 비슷한 영상보다 재료와 순서가 명확한 영상을 고르세요.',
            en: 'Search with a dish and main ingredient and inspect the original description. Prefer clear ingredients and methods over a matching title alone.'
          )
        ),
        (
          title: (ko: '기존 자동 초안부터 시도', en: 'Start with the standard draft'),
          body: (
            ko: '선택한 영상의 설명으로 자동 초안을 만듭니다. 부족하면 같은 영상의 자막이나 직접 확인한 요약 정보를 보완할 수 있습니다.',
            en: 'Generate a standard draft from the selected description. If needed, add a transcript or reviewed summary from that same video.'
          )
        ),
        (
          title: (ko: '영상 분석은 제공 조건 확인', en: 'Check video analysis access'),
          body: (
            ko: '영상 분석을 선택할 때는 현재 요금제와 남은 횟수·영상 길이 제한을 확인합니다. YouTube에서 본 요약이 앱으로 자동 전달되는 것은 아닙니다.',
            en: 'Before video analysis, check current plan access, remaining uses and duration limits. A summary viewed on YouTube is not automatically transferred into this app.'
          )
        ),
        (
          title: (ko: '검토 후 내 기준으로 저장', en: 'Review before saving'),
          body: (
            ko: '재료량·단위·조리 순서·시간의 근거를 확인하고 불명확한 부분을 수정합니다. 실제 조리 시험 후 내 레시피와 셰프 기준으로 정리하세요.',
            en: 'Verify quantities, units, sequence and timing, then correct unclear details. Test the dish before treating it as a recipe and Chef standard.'
          )
        ),
      ],
      answers: [
        (
          ko: '요약이 실제 입력됐는지와 원본 근거',
          en: 'Whether the summary was actually supplied and matches the source'
        ),
        (ko: '자동 전달됐다고 가정', en: 'Assume it was transferred automatically')
      ],
      correctAnswer: 0,
      destination: GuideDestination.youtube,
      minutes: 4,
      access: 'ai',
      practice: GuidePractice.none),
  GuideLesson(
      id: 'home-search',
      audience: GuideAudience.home,
      title: (ko: '먹고 싶은 요리 찾기', en: 'Find a dish you want to cook'),
      goal: (
        ko: '검색과 한식 분류로 후보를 좁혀 봅니다.',
        en: 'Use search and Korean categories to narrow your choices.'
      ),
      outcome: (
        ko: '원본 영상을 확인한 요리 하나',
        en: 'One dish with its original video reviewed'
      ),
      tip: (
        ko: '홈의 대표 한식 영상은 로그인 없이 볼 수 있습니다. 레시피 저장과 AI 생성은 해당 화면의 로그인·이용 조건을 따릅니다.',
        en: 'The featured Korean videos can be viewed without signing in. Saving recipes and AI generation follow the access conditions shown in the app.'
      ),
      question: (
        ko: '처음 고를 영상에서 먼저 볼 것은?',
        en: 'What matters when choosing your first video?'
      ),
      explanation: (
        ko: '설명이 자세할수록 실제 준비와 초안 검토가 쉬워집니다.',
        en: 'Detailed evidence makes preparation and draft review easier.'
      ),
      steps: [
        (
          title: (ko: '검색에서 시작', en: 'Start in Search'),
          body: (
            ko: '하단 검색을 누르고 요리명이나 주재료를 입력하세요. 한식 분류의 전체·밥·면·국·찌개·고기 요리·분식·전으로 둘러볼 수도 있습니다.',
            en: 'Open Search and enter a dish or main ingredient. You can also browse All, Rice & noodles, Soups & stews, Meat, or Snacks & pancakes.'
          )
        ),
        (
          title: (ko: '원본 영상 확인', en: 'Check the original'),
          body: (
            ko: '카드의 영상 버튼으로 요리를 확인합니다. 재료와 만드는 순서가 설명돼 있는지 먼저 살펴보세요.',
            en: 'Open the original video from its card. Look for ingredients and cooking steps in the description.'
          )
        ),
        (
          title: (ko: '한 가지 요리 선택', en: 'Choose one dish'),
          body: (
            ko: '오늘 준비할 시간과 재료에 맞는 요리를 고릅니다. 영상을 더 찾으려면 영상 레시피 검색으로 이동하세요.',
            en: 'Choose a dish that fits your time and ingredients. Use video recipe search to look for more options.'
          )
        ),
      ],
      answers: [
        (ko: '재료와 만드는 순서', en: 'Ingredients and cooking steps'),
        (ko: '조회 수만', en: 'Only the view count')
      ],
      correctAnswer: 0,
      destination: GuideDestination.search,
      minutes: 3,
      access: 'open',
      practice: GuidePractice.none),
  GuideLesson(
      id: 'home-draft',
      audience: GuideAudience.home,
      title: (ko: 'AI 초안의 빈칸 확인', en: 'Review what an AI draft is missing'),
      goal: (
        ko: '원본과 비교하고 모르는 양은 확인합니다.',
        en: 'Compare the draft with the source and verify missing quantities.'
      ),
      outcome: (
        ko: '재료·양·순서를 직접 검토한 초안',
        en: 'A draft with ingredients, amounts and steps reviewed'
      ),
      tip: (
        ko: 'YouTube의 요약을 본 것만으로 앱에 정보가 자동 입력되지는 않습니다. 영상 분석은 현재 제공되는 요금제와 제한을 먼저 확인하세요.',
        en: 'Viewing a summary on YouTube does not automatically fill the app. Check current plan access and limits before using video analysis.'
      ),
      question: (
        ko: '초안에 재료량이 없으면 어떻게 하나요?',
        en: 'What should you do if an amount is missing?'
      ),
      explanation: (
        ko: '확인한 정보로 수정한 뒤 실제 조리에 사용하세요.',
        en: 'Use verified information before cooking.'
      ),
      steps: [
        (
          title: (ko: '영상에서 초안 만들기', en: 'Create a draft from a video'),
          body: (
            ko: '로그인 후 원하는 영상에서 AI 초안 만들기를 시작합니다. 생성 전에 표시된 이용 조건과 남은 횟수를 확인하세요.',
            en: 'Sign in and start an AI draft from your chosen video. Check the displayed access conditions and remaining uses first.'
          )
        ),
        (
          title: (ko: '재료와 순서 비교', en: 'Compare ingredients and steps'),
          body: (
            ko: '재료 이름·수량·단위와 조리 순서를 원본 설명이나 영상에서 확인합니다. 확인 필요 항목과 빠진 분량부터 살펴보세요.',
            en: 'Compare names, quantities, units and steps with the original description or video. Review unverified items and missing amounts first.'
          )
        ),
        (
          title: (ko: '정보를 보완해 수정', en: 'Fill gaps with evidence'),
          body: (
            ko: '초안이 부족하면 같은 영상의 자막·요약을 직접 넣거나 요리명·재료 힌트를 보완합니다. 모르는 숫자를 사실처럼 채우지 마세요.',
            en: 'Supply a transcript, reviewed summary or dish and ingredient hints from the same video. Do not treat an unknown number as a fact.'
          )
        ),
      ],
      answers: [
        (ko: '아무 양이나 입력', en: 'Enter any amount'),
        (ko: '원본에서 확인하고 수정', en: 'Verify it in the source and edit it')
      ],
      correctAnswer: 1,
      destination: GuideDestination.youtube,
      minutes: 4,
      access: 'ai',
      practice: GuidePractice.none),
  GuideLesson(
      id: 'home-save',
      audience: GuideAudience.home,
      title: (ko: '내 레시피로 저장', en: 'Save your personal recipe'),
      goal: (
        ko: '다음에도 다시 찾을 수 있게 정리합니다.',
        en: 'Make the recipe easy to find and use again.'
      ),
      outcome: (
        ko: '이름·재료·조리 단계가 정리된 내 레시피',
        en: 'A personal recipe with a clear name, ingredients and steps'
      ),
      tip: (
        ko: '텍스트 편집의 실행 취소와 서버에 저장된 레시피 버전 관리는 서로 다릅니다. 전문적인 배합 비교는 전문가 과정의 버전 관리에서 배울 수 있습니다.',
        en: 'Text editing undo and saved recipe version management are different. Learn structured batch comparisons in the professional course.'
      ),
      question: (
        ko: '다음 조리에 도움이 되는 메모는?',
        en: 'Which note helps you cook it again?'
      ),
      explanation: (
        ko: '무엇을 얼마나 바꿨는지 적으면 다음에 재현하기 쉽습니다.',
        en: 'Specific amounts and changes are easier to repeat.'
      ),
      steps: [
        (
          title: (ko: '이름과 메모 정리', en: 'Edit the name and notes'),
          body: (
            ko: '요리 이름을 알기 쉽게 쓰고 기준 인분을 설명에 남깁니다. 원본에서 확인한 내용과 내가 바꾼 내용을 구분하세요.',
            en: 'Use a recognizable name and note baseline servings in the summary. Distinguish source details from your own changes.'
          )
        ),
        (
          title: (ko: '편집 실수 되돌리기', en: 'Recover an editing mistake'),
          body: (
            ko: '입력 중 실수하면 실행 취소 아이콘을 누릅니다. 되돌린 편집을 다시 적용하려면 다시 실행 아이콘을 사용하세요.',
            en: 'Use the undo icon after an editing mistake. Use redo to reapply an edit you have undone.'
          )
        ),
        (
          title: (ko: '저장 후 다시 열기', en: 'Save and reopen'),
          body: (
            ko: '저장을 누르고 내 레시피에서 다시 열어 내용을 확인합니다. 다음 요리에서 바꿀 점은 팁이나 메모로 남겨 보세요.',
            en: 'Save, then reopen the recipe in My recipes to check it. Record what you want to adjust next time in tips or notes.'
          )
        ),
      ],
      answers: [
        (
          ko: '소금 1g 줄임, 덜 짜게 조정',
          en: 'Reduced salt by 1 g for a less salty result'
        ),
        (ko: '좋음만 기록', en: 'Only write good')
      ],
      correctAnswer: 0,
      destination: GuideDestination.recipes,
      minutes: 3,
      access: 'account',
      practice: GuidePractice.none),
  GuideLesson(
      id: 'home-shopping',
      audience: GuideAudience.home,
      title: (ko: '필요한 재료만 장보기', en: 'Shop for what you actually need'),
      goal: (
        ko: '보유 재료와 구매할 양을 구분합니다.',
        en: 'Separate what you have from what you need to buy.'
      ),
      outcome: (
        ko: '구매 수량과 단위를 확인한 장보기 목록',
        en: 'A shopping list with reviewed quantities and units'
      ),
      tip: (
        ko: '구매 완료 표시는 실제 결제나 배송 완료를 대신하지 않습니다. 포장 크기가 다르면 조리량과 구매 수량을 따로 확인하세요.',
        en: 'Marking a purchase does not perform payment or confirm delivery. Check recipe amounts and purchase quantities separately when pack sizes differ.'
      ),
      question: (
        ko: '우유 한 팩을 샀다면 어떻게 기록하나요?',
        en: 'How should you record buying one carton of milk?'
      ),
      explanation: (
        ko: '구매 단위와 조리 분량을 구분하면 과다 구매와 혼동을 줄일 수 있습니다.',
        en: 'Separating purchase units from recipe quantities reduces confusion and overbuying.'
      ),
      steps: [
        (
          title: (ko: '레시피에서 목록 만들기', en: 'Create a list from the recipe'),
          body: (
            ko: '레시피 상세에서 장보기 준비를 누릅니다. 이미 가진 재료와 실제로 부족한 재료를 살펴보세요.',
            en: 'Use Shopping prep in recipe details. Check what you already have and what is actually missing.'
          )
        ),
        (
          title: (ko: '구매 단위 맞추기', en: 'Choose purchase units'),
          body: (
            ko: '구매 수량·단위 버튼에서 구매량을 입력합니다. 조리에 우유 200mL를 써도 구매는 한 팩일 수 있으며, 조리 원문은 바뀌지 않습니다.',
            en: 'Use Purchase quantity and unit to enter what you will buy. Cooking may use 200 mL of milk while you buy one carton. The original cooking ingredient stays unchanged.'
          )
        ),
        (
          title: (ko: '구매처 확인', en: 'Review where to buy'),
          body: (
            ko: '장보기 도우미에서 구매처를 확인하고 필요한 경우 연결합니다. 외부 구매처의 가격·배송 조건·최종 결제는 직접 확인하세요.',
            en: 'Use the shopping assistant to review purchase options. Check prices, delivery and final payment directly with the external seller.'
          )
        ),
        (
          title: (ko: '실제 구매 후 완료', en: 'Complete after buying'),
          body: (
            ko: '실제로 산 재료만 구매함으로 표시하고 장보기를 완료합니다. 구매 이력에 반영된 내용도 확인하세요.',
            en: 'Mark only what you actually bought as purchased, then complete shopping. Check the resulting purchase history.'
          )
        ),
      ],
      answers: [
        (ko: '조리량도 무조건 한 팩', en: 'Always change recipe usage to one carton'),
        (
          ko: '구매는 한 팩, 조리량은 별도 확인',
          en: 'One carton purchased; verify recipe usage separately'
        )
      ],
      correctAnswer: 1,
      destination: GuideDestination.shopping,
      minutes: 4,
      access: 'account',
      practice: GuidePractice.none),
  GuideLesson(
      id: 'home-repeat',
      audience: GuideAudience.home,
      title: (ko: '요리하고 다음 한 끼 계획', en: 'Cook and plan your next meal'),
      goal: (
        ko: '실제 결과를 남기고 보유 재료를 활용합니다.',
        en: 'Record the result and plan around what remains.'
      ),
      outcome: (
        ko: '다음 조리에 반영할 메모와 재료 확인',
        en: 'A note for next time and a check of remaining ingredients'
      ),
      tip: (
        ko: '인분 환산이나 표준 배합이 필요해지면 업소·전문가 과정으로 전환하세요. 일반 과정의 학습 진도는 별도로 남아 있습니다.',
        en: 'Switch to the professional course when you need serving conversion or standard batches. Your everyday-course progress stays separate.'
      ),
      question: (
        ko: '재료 이름이 일치하면 충분한가요?',
        en: 'Does an ingredient-name match mean you have enough?'
      ),
      explanation: (
        ko: '실제 양과 상태를 확인해야 준비를 마칠 수 있습니다.',
        en: 'Check actual quantity and condition before preparing.'
      ),
      steps: [
        (
          title: (ko: '조리 전 전체 흐름 읽기', en: 'Read the full method first'),
          body: (
            ko: '재료와 도구를 준비하고 조리 단계를 끝까지 읽습니다. 화면 진행 상태와 실제 음식의 익힘은 별도로 확인하세요.',
            en: 'Prepare ingredients and tools and read every step. Check actual doneness separately from progress shown on screen.'
          )
        ),
        (
          title: (ko: '실제 조리 결과 기록', en: 'Record what happened'),
          body: (
            ko: '조리 후 실제 사용한 양·걸린 시간·다음에 바꿀 점을 내 레시피에 남깁니다. 한 번에 한 가지씩 바꾸면 비교하기 쉽습니다.',
            en: 'Record amounts used, actual time and what to change in your recipe. Adjusting one thing at a time makes comparisons easier.'
          )
        ),
        (
          title: (ko: '남은 재료로 다음 요리 찾기', en: 'Find a use for what remains'),
          body: (
            ko: '보유 재료와 실제 남은 양을 확인하고 재료 검색으로 다음 요리를 찾아보세요. 이름이 일치하더라도 필요한 양과 상태는 직접 확인합니다.',
            en: 'Check your pantry and actual remaining quantities, then use ingredient search. A name match does not guarantee enough quantity or the right condition.'
          )
        ),
      ],
      answers: [
        (
          ko: '필요량과 실제 남은 양도 확인',
          en: 'Also compare required and remaining quantities'
        ),
        (ko: '이름만 같으면 충분', en: 'The same name is enough')
      ],
      correctAnswer: 0,
      destination: GuideDestination.ingredients,
      minutes: 3,
      access: 'account',
      practice: GuidePractice.none),
  ...workflowGuideLessons,
];
