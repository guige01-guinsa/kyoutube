insert into public.recipes_public (source_id, title, summary, ingredients, steps, calories, image_url)
values
  (
    'seed-public-001',
    '김치볶음밥',
    '남은 밥으로 빠르게 만드는 매콤한 한 끼',
    '["밥 1공기", "김치 1컵", "대파 1/2대", "달걀 1개"]'::jsonb,
    '["재료를 썰어 준비한다", "김치를 먼저 볶아 수분을 날린다", "밥을 넣고 고루 볶는다", "달걀 프라이와 함께 담아낸다"]'::jsonb,
    620,
    null
  ),
  (
    'seed-public-002',
    '닭가슴살 샐러드',
    '가볍고 단백질 중심의 식사',
    '["닭가슴살 150g", "양상추", "방울토마토", "올리브오일"]'::jsonb,
    '["닭가슴살을 구워 식힌다", "채소를 씻어 손질한다", "모든 재료를 섞고 드레싱을 더한다"]'::jsonb,
    420,
    null
  )
on conflict (source_id) do nothing;
