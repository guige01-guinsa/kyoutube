-- Time-limited, isolated business practice. Real workspaces and memberships are unchanged.
create table public.business_test_campaigns (
 id uuid primary key default gen_random_uuid(), name text not null check(length(btrim(name)) between 1 and 120),
 audience text not null check(audience in ('selected','members')), ends_at timestamptz not null,
 ended_at timestamptz, created_at timestamptz not null default now(),
 created_by uuid references auth.users(id) on delete set null,
 check(ends_at>created_at and ends_at<=created_at+interval '90 days')
);
create table public.business_test_participants (
 campaign_id uuid not null references public.business_test_campaigns on delete cascade,
 user_id uuid not null references auth.users on delete cascade, active boolean not null default true,
 primary key(campaign_id,user_id)
);
create table public.business_test_workspaces (
 workspace_id uuid primary key references public.business_workspaces on delete cascade,
 campaign_id uuid not null references public.business_test_campaigns,
 owner_id uuid not null references auth.users on delete cascade,
 language text not null check(language in ('ko','en')), generation integer not null default 1,
 created_at timestamptz not null default now(), unique(campaign_id,owner_id)
);
create table public.business_test_events (
 id bigint generated always as identity primary key, campaign_id uuid references public.business_test_campaigns,
 actor_id uuid references auth.users on delete set null, action text not null,
 details jsonb not null default '{}', created_at timestamptz not null default now()
);
alter table public.business_test_campaigns enable row level security;
alter table public.business_test_participants enable row level security;
alter table public.business_test_workspaces enable row level security;
alter table public.business_test_events enable row level security;
revoke all on public.business_test_campaigns,public.business_test_participants,public.business_test_workspaces,public.business_test_events from public,anon,authenticated;
grant all on public.business_test_campaigns,public.business_test_participants,public.business_test_workspaces,public.business_test_events to service_role;

create function public.business_test_eligible(p_campaign uuid,p_user uuid) returns boolean language sql stable security definer set search_path='' as $$
 select p_user is not null and exists(select 1 from auth.users u join public.business_test_campaigns c on c.id=p_campaign
 where u.id=p_user and u.email_confirmed_at is not null and c.ended_at is null and c.ends_at>now()
 and not exists(select 1 from public.business_test_participants t where t.campaign_id=c.id and t.user_id=u.id and not t.active)
 and (c.audience='members' or exists(select 1 from public.business_test_participants t where t.campaign_id=c.id and t.user_id=u.id and t.active)));
$$;
create function public.business_test_access(p_workspace uuid,p_user uuid) returns boolean language sql stable security definer set search_path='' as $$
 select not exists(select 1 from public.business_test_workspaces where workspace_id=p_workspace)
 or exists(select 1 from public.business_test_workspaces t where t.workspace_id=p_workspace
 and public.business_test_eligible(t.campaign_id,t.owner_id) and public.business_test_eligible(t.campaign_id,p_user));
$$;
create function public.business_test_write_guard() returns trigger language plpgsql security definer set search_path='' as $$
declare w uuid; target uuid;begin
 w:=new.workspace_id;
 if exists(select 1 from public.business_test_workspaces where workspace_id=w) then
  if not public.business_test_access(w,auth.uid()) then raise exception 'BUSINESS_TEST_CLOSED';end if;
  if tg_table_name='business_members' then
   if new.active and not public.business_test_access(w,new.user_id) then raise exception 'BUSINESS_TEST_PARTICIPANT';end if;
  elsif tg_table_name='business_invites' then
   select id into target from auth.users where lower(email)=lower(new.email) and email_confirmed_at is not null;
   if not new.revoked and not public.business_test_access(w,target) then raise exception 'BUSINESS_TEST_PARTICIPANT';end if;
  end if;
 end if;
 return new;
end;$$;
create trigger business_test_records_guard before insert or update on public.business_records for each row execute function public.business_test_write_guard();
create trigger business_test_members_guard before insert or update on public.business_members for each row execute function public.business_test_write_guard();
create trigger business_test_invites_guard before insert or update on public.business_invites for each row execute function public.business_test_write_guard();

create function public.business_test_options() returns jsonb language plpgsql stable security definer set search_path='' as $$
begin
 if auth.uid() is null or coalesce((auth.jwt()->>'is_anonymous')::boolean,false) then raise exception 'BUSINESS_AUTH';end if;
 return coalesce((select jsonb_agg(jsonb_build_object('id',c.id,'name',c.name,'ends_at',c.ends_at,
 'available',public.business_test_eligible(c.id,auth.uid()),'workspace_id',t.workspace_id,'generation',t.generation,
 'ended',c.ended_at is not null or c.ends_at<=now()) order by c.created_at desc)
 from public.business_test_campaigns c left join public.business_test_workspaces t on t.campaign_id=c.id and t.owner_id=auth.uid()
 where public.business_test_eligible(c.id,auth.uid()) or t.workspace_id is not null),'[]'::jsonb);
end;$$;
create function public.admin_business_test_list() returns jsonb language plpgsql stable security definer set search_path='' as $$
begin
 perform public.assert_admin_mfa();
 return coalesce((select jsonb_agg(x order by x->>'created_at' desc) from (select jsonb_build_object(
 'id',c.id,'name',c.name,'audience',c.audience,'ends_at',c.ends_at,'ended',c.ended_at is not null or c.ends_at<=now(),
 'closed',c.ended_at is not null,'created_at',c.created_at,
 'workspaces',(select count(*) from public.business_test_workspaces t where t.campaign_id=c.id),
 'records',(select count(*) from public.business_records r join public.business_test_workspaces t on t.workspace_id=r.workspace_id where t.campaign_id=c.id),
 'participants',coalesce((select jsonb_agg(jsonb_build_object('id',p.user_id,'email',u.email,'active',p.active) order by u.email)
 from public.business_test_participants p join auth.users u on u.id=p.user_id where p.campaign_id=c.id),'[]'::jsonb)
 ) as x from public.business_test_campaigns c order by c.created_at desc limit 30) rows),'[]'::jsonb);
end;$$;
create function public.admin_business_test_create(p_name text,p_days integer,p_audience text) returns uuid language plpgsql security definer set search_path='' as $$
declare c uuid;begin
 perform public.assert_admin_mfa();
 if p_days is null or p_days not between 1 and 90 or p_audience is null or p_audience not in ('selected','members') then raise exception 'BUSINESS_TEST_INVALID';end if;
 perform pg_advisory_xact_lock(hashtextextended('business-test-campaign',0));
 if exists(select 1 from public.business_test_campaigns where ended_at is null and ends_at>now()) then raise exception 'BUSINESS_TEST_ACTIVE';end if;
 insert into public.business_test_campaigns(name,audience,ends_at,created_by) values(btrim(p_name),p_audience,now()+make_interval(days=>p_days),auth.uid()) returning id into c;
 insert into public.business_test_participants(campaign_id,user_id) values(c,auth.uid());
 insert into public.business_test_events(campaign_id,actor_id,action,details) values(c,auth.uid(),'created',jsonb_build_object('days',p_days,'audience',p_audience));
 return c;
end;$$;
create function public.admin_business_test_participant(p_campaign uuid,p_email text,p_active boolean) returns void language plpgsql security definer set search_path='' as $$
declare u uuid;begin
 perform public.assert_admin_mfa();
 perform 1 from public.business_test_campaigns where id=p_campaign and ended_at is null and ends_at>now() for update;
 if not found or p_active is null then raise exception 'BUSINESS_TEST_CLOSED';end if;
 select id into u from auth.users where lower(email)=lower(btrim(p_email)) and email_confirmed_at is not null;
 if u is null then raise exception 'BUSINESS_TEST_ACCOUNT';end if;
 perform 1 from public.business_workspaces w join public.business_test_workspaces t on t.workspace_id=w.id where t.campaign_id=p_campaign order by w.id for update of w;
 insert into public.business_test_participants(campaign_id,user_id,active) values(p_campaign,u,p_active)
 on conflict(campaign_id,user_id) do update set active=excluded.active;
 insert into public.business_test_events(campaign_id,actor_id,action,details) values(p_campaign,auth.uid(),'participant',jsonb_build_object('user_id',u,'active',p_active));
end;$$;
create function public.admin_business_test_end(p_campaign uuid) returns void language plpgsql security definer set search_path='' as $$
begin
 perform public.assert_admin_mfa();
 perform 1 from public.business_test_campaigns where id=p_campaign for update;
 if not found then raise exception 'BUSINESS_TEST_NOT_FOUND';end if;
 perform 1 from public.business_workspaces w join public.business_test_workspaces t on t.workspace_id=w.id where t.campaign_id=p_campaign order by w.id for update of w;
 update public.business_test_campaigns set ended_at=now() where id=p_campaign and ended_at is null;
 if found then insert into public.business_test_events(campaign_id,actor_id,action) values(p_campaign,auth.uid(),'ended');end if;
end;$$;
create function public.admin_business_test_cleanup(p_campaign uuid) returns jsonb language plpgsql security definer set search_path='' as $$
declare ids uuid[]; removed integer; remaining integer;begin
 perform public.assert_admin_mfa();
 perform 1 from public.business_test_campaigns where id=p_campaign and ended_at is not null for update;
 if not found then raise exception 'BUSINESS_TEST_END_FIRST';end if;
 select array_agg(workspace_id) into ids from (select workspace_id from public.business_test_workspaces where campaign_id=p_campaign order by workspace_id limit 50) rows;
 delete from public.business_workspaces where id=any(coalesce(ids,'{}'::uuid[]));get diagnostics removed=row_count;
 select count(*) into remaining from public.business_test_workspaces where campaign_id=p_campaign;
 if removed>0 then insert into public.business_test_events(campaign_id,actor_id,action,details) values(p_campaign,auth.uid(),'deleted_samples',jsonb_build_object('workspaces',removed,'remaining',remaining));end if;
 return jsonb_build_object('deleted',removed,'remaining',remaining);
end;$$;

create function public.business_test_seed(p_workspace uuid,p_language text) returns void language plpgsql security definer set search_path='' as $seed$
declare catalog jsonb:=$samples${
  "ko": [
    {
      "key": "recipe1",
      "kind": "recipe",
      "title": "[샘플] 닭고기 채소 덮밥",
      "data": {
        "ingredients": "닭다리살 800 g\n밥 1000 g\n양파 200 g\n당근 150 g\n간장 60 mL",
        "steps": "재료를 손질합니다.\n닭고기를 충분히 익힌 뒤 채소와 양념을 넣습니다.\n밥 위에 나누어 담고 맛과 배합을 기록합니다.",
        "notes": "교육용 가상 배합입니다. 실제 조리 시 업소 기준으로 검토하세요.",
        "servings": 5
      }
    },
    {
      "key": "recipe2",
      "kind": "recipe",
      "title": "[샘플] 두부 버섯 조림",
      "data": {
        "ingredients": "두부 1000 g\n버섯 300 g\n대파 80 g\n간장 50 mL\n물 400 mL",
        "steps": "두부와 버섯을 썹니다.\n양념과 물을 넣고 끓입니다.\n간과 수분량을 확인하고 개선점을 기록합니다.",
        "notes": "교육용 가상 배합입니다. 실제 조리 시 업소 기준으로 검토하세요.",
        "servings": 5
      }
    },
    {
      "key": "recipe3",
      "kind": "recipe",
      "title": "[샘플] 소고기 불고기",
      "data": {
        "ingredients": "소고기 800 g\n양파 250 g\n배즙 100 mL\n간장 60 mL\n대파 80 g",
        "steps": "고기와 채소를 준비합니다.\n양념한 고기를 충분히 익힙니다.\n채소를 넣고 조리한 뒤 5인분으로 나눕니다.",
        "notes": "교육용 가상 배합입니다. 실제 조리 시 업소 기준으로 검토하세요.",
        "servings": 5
      }
    },
    {
      "key": "recipe4",
      "kind": "recipe",
      "title": "[샘플] 버섯 비빔밥",
      "data": {
        "ingredients": "밥 1000 g\n버섯 400 g\n당근 200 g\n시금치 250 g\n참기름 25 mL",
        "steps": "채소를 종류별로 손질하고 익힙니다.\n밥 위에 재료를 배치합니다.\n양념은 별도로 제공하고 인분별 배합을 기록합니다.",
        "notes": "교육용 가상 배합입니다. 실제 조리 시 업소 기준으로 검토하세요.",
        "servings": 5
      }
    },
    {
      "key": "recipe5",
      "kind": "recipe",
      "title": "[샘플] 감자 된장국",
      "data": {
        "ingredients": "감자 500 g\n두부 300 g\n양파 150 g\n된장 80 g\n물 1500 mL",
        "steps": "감자와 채소를 썹니다.\n물에 된장을 풀고 감자를 익힙니다.\n두부와 채소를 넣어 끓인 뒤 간을 확인합니다.",
        "notes": "교육용 가상 배합입니다. 실제 조리 시 업소 기준으로 검토하세요.",
        "servings": 5
      }
    },
    {
      "key": "meal1",
      "kind": "meal",
      "title": "[샘플] 1일차 점심 식단",
      "data": {
        "date": "@day+0",
        "servings": 20,
        "recipe_ids": [
          "@recipe1",
          "@recipe5"
        ],
        "notes": "인분과 메뉴 조합을 바꿔 저장해 보세요. 구매량은 별도로 확정합니다."
      }
    },
    {
      "key": "meal2",
      "kind": "meal",
      "title": "[샘플] 2일차 점심 식단",
      "data": {
        "date": "@day+1",
        "servings": 30,
        "recipe_ids": [
          "@recipe2",
          "@recipe4"
        ],
        "notes": "인분과 메뉴 조합을 바꿔 저장해 보세요. 구매량은 별도로 확정합니다."
      }
    },
    {
      "key": "meal3",
      "kind": "meal",
      "title": "[샘플] 3일차 점심 식단",
      "data": {
        "date": "@day+2",
        "servings": 15,
        "recipe_ids": [
          "@recipe3",
          "@recipe5"
        ],
        "notes": "인분과 메뉴 조합을 바꿔 저장해 보세요. 구매량은 별도로 확정합니다."
      }
    },
    {
      "key": "purchase1",
      "kind": "purchase",
      "status": "draft",
      "title": "[샘플] 닭다리살 구매요청",
      "data": {
        "supplier": "[연습] 한곳 식자재",
        "buyer": "[연습] 한끼 업소",
        "phone": "",
        "address": "연습용 납품 장소 — 실제 주소 아님",
        "delivery_date": "@day+0",
        "currency": "KRW",
        "notes": "연습용 요청서입니다. 실제 구매나 납품 요청에 사용하지 마세요.",
        "lines": [
          {
            "id": "@line0",
            "name": "닭다리살",
            "quantity": 2,
            "unit": "kg",
            "spec": "구매 규격 확인 연습",
            "price": 9000
          }
        ]
      }
    },
    {
      "key": "purchase2",
      "kind": "purchase",
      "status": "draft",
      "title": "[샘플] 두부 구매요청",
      "data": {
        "supplier": "[연습] 한곳 식자재",
        "buyer": "[연습] 한끼 업소",
        "phone": "",
        "address": "연습용 납품 장소 — 실제 주소 아님",
        "delivery_date": "@day+1",
        "currency": "KRW",
        "notes": "연습용 요청서입니다. 실제 구매나 납품 요청에 사용하지 마세요.",
        "lines": [
          {
            "id": "@line1",
            "name": "두부",
            "quantity": 4,
            "unit": "pack",
            "spec": "구매 규격 확인 연습",
            "price": null
          }
        ]
      }
    },
    {
      "key": "purchase3",
      "kind": "purchase",
      "status": "review",
      "title": "[샘플] 소고기 구매요청",
      "data": {
        "supplier": "[연습] 한곳 식자재",
        "buyer": "[연습] 한끼 업소",
        "phone": "",
        "address": "연습용 납품 장소 — 실제 주소 아님",
        "delivery_date": "@day+2",
        "currency": "KRW",
        "notes": "연습용 요청서입니다. 실제 구매나 납품 요청에 사용하지 마세요.",
        "lines": [
          {
            "id": "@line2",
            "name": "소고기",
            "quantity": 1.5,
            "unit": "kg",
            "spec": "구매 규격 확인 연습",
            "price": 24000
          }
        ]
      }
    },
    {
      "key": "purchase4",
      "kind": "purchase",
      "status": "approved",
      "title": "[샘플] 버섯 구매요청",
      "data": {
        "supplier": "[연습] 한곳 식자재",
        "buyer": "[연습] 한끼 업소",
        "phone": "",
        "address": "연습용 납품 장소 — 실제 주소 아님",
        "delivery_date": "@day+0",
        "currency": "KRW",
        "notes": "연습용 요청서입니다. 실제 구매나 납품 요청에 사용하지 마세요.",
        "lines": [
          {
            "id": "@line3",
            "name": "버섯",
            "quantity": 3,
            "unit": "kg",
            "spec": "구매 규격 확인 연습",
            "price": 7000
          }
        ]
      }
    },
    {
      "key": "purchase5",
      "kind": "purchase",
      "status": "received",
      "title": "[샘플] 감자 구매요청",
      "data": {
        "supplier": "[연습] 한곳 식자재",
        "buyer": "[연습] 한끼 업소",
        "phone": "",
        "address": "연습용 납품 장소 — 실제 주소 아님",
        "delivery_date": "@day+1",
        "currency": "KRW",
        "notes": "연습용 요청서입니다. 실제 구매나 납품 요청에 사용하지 마세요.",
        "lines": [
          {
            "id": "@line4",
            "name": "감자",
            "quantity": 5,
            "unit": "kg",
            "spec": "구매 규격 확인 연습",
            "price": 3500
          }
        ]
      }
    },
    {
      "key": "cost1",
      "kind": "cost",
      "title": "[샘플] 닭고기 채소 덮밥 원가·판매가",
      "data": {
        "recipe_id": "@recipe1",
        "unit_cost": 3500,
        "unit_price": 7000,
        "currency": "KRW",
        "notes": "예시 금액이며 실제 시세가 아닙니다. 1인분 원가·판매가를 바꾸고 이후 판매 기록과 비교해 보세요."
      }
    },
    {
      "key": "cost2",
      "kind": "cost",
      "title": "[샘플] 두부 버섯 조림 원가·판매가",
      "data": {
        "recipe_id": "@recipe2",
        "unit_cost": 2500,
        "unit_price": 5000,
        "currency": "KRW",
        "notes": "예시 금액이며 실제 시세가 아닙니다. 1인분 원가·판매가를 바꾸고 이후 판매 기록과 비교해 보세요."
      }
    },
    {
      "key": "cost3",
      "kind": "cost",
      "title": "[샘플] 소고기 불고기 원가·판매가",
      "data": {
        "recipe_id": "@recipe3",
        "unit_cost": 6000,
        "unit_price": 11000,
        "currency": "KRW",
        "notes": "예시 금액이며 실제 시세가 아닙니다. 1인분 원가·판매가를 바꾸고 이후 판매 기록과 비교해 보세요."
      }
    },
    {
      "key": "sale1",
      "kind": "sale",
      "title": "[샘플] 판매 기록 1",
      "data": {
        "cost_id": "@cost1",
        "date": "@day+0",
        "quantity": 12,
        "unit_cost": 3500,
        "unit_price": 7000,
        "currency": "KRW"
      }
    },
    {
      "key": "sale2",
      "kind": "sale",
      "title": "[샘플] 판매 기록 2",
      "data": {
        "cost_id": "@cost2",
        "date": "@day-1",
        "quantity": 18,
        "unit_cost": 2500,
        "unit_price": 5000,
        "currency": "KRW"
      }
    },
    {
      "key": "sale3",
      "kind": "sale",
      "title": "[샘플] 판매 기록 3",
      "data": {
        "cost_id": "@cost3",
        "date": "@day-7",
        "quantity": 25,
        "unit_cost": 6000,
        "unit_price": 11000,
        "currency": "KRW"
      }
    },
    {
      "key": "sale4",
      "kind": "sale",
      "title": "[샘플] 판매 기록 4",
      "data": {
        "cost_id": "@cost1",
        "date": "@day-32",
        "quantity": 10,
        "unit_cost": 3500,
        "unit_price": 7000,
        "currency": "KRW"
      }
    }
  ],
  "en": [
    {
      "key": "recipe1",
      "kind": "recipe",
      "title": "[SAMPLE] Chicken vegetable rice bowl",
      "data": {
        "ingredients": "Chicken thigh 800 g\nCooked rice 1000 g\nOnion 200 g\nCarrot 150 g\nSoy sauce 60 mL",
        "steps": "Prepare the ingredients.\nCook the chicken thoroughly, then add vegetables and seasoning.\nServe over rice and record seasoning adjustments.",
        "notes": "Fictional training recipe. Review against your kitchen standards before real use.",
        "servings": 5
      }
    },
    {
      "key": "recipe2",
      "kind": "recipe",
      "title": "[SAMPLE] Braised tofu and mushrooms",
      "data": {
        "ingredients": "Tofu 1000 g\nMushrooms 300 g\nSpring onion 80 g\nSoy sauce 50 mL\nWater 400 mL",
        "steps": "Slice tofu and mushrooms.\nSimmer with seasoning and water.\nCheck seasoning and sauce volume; record improvements.",
        "notes": "Fictional training recipe. Review against your kitchen standards before real use.",
        "servings": 5
      }
    },
    {
      "key": "recipe3",
      "kind": "recipe",
      "title": "[SAMPLE] Beef bulgogi",
      "data": {
        "ingredients": "Beef 800 g\nOnion 250 g\nPear juice 100 mL\nSoy sauce 60 mL\nSpring onion 80 g",
        "steps": "Prepare the beef and vegetables.\nSeason and cook the beef thoroughly.\nAdd vegetables and divide into five portions.",
        "notes": "Fictional training recipe. Review against your kitchen standards before real use.",
        "servings": 5
      }
    },
    {
      "key": "recipe4",
      "kind": "recipe",
      "title": "[SAMPLE] Mushroom bibimbap",
      "data": {
        "ingredients": "Cooked rice 1000 g\nMushrooms 400 g\nCarrot 200 g\nSpinach 250 g\nSesame oil 25 mL",
        "steps": "Prepare and cook each vegetable separately.\nArrange over rice.\nServe seasoning separately and record per-portion ratios.",
        "notes": "Fictional training recipe. Review against your kitchen standards before real use.",
        "servings": 5
      }
    },
    {
      "key": "recipe5",
      "kind": "recipe",
      "title": "[SAMPLE] Potato soybean-paste soup",
      "data": {
        "ingredients": "Potatoes 500 g\nTofu 300 g\nOnion 150 g\nSoybean paste 80 g\nWater 1500 mL",
        "steps": "Cut potatoes and vegetables.\nDissolve soybean paste in water and cook the potatoes.\nAdd tofu and vegetables, simmer and check seasoning.",
        "notes": "Fictional training recipe. Review against your kitchen standards before real use.",
        "servings": 5
      }
    },
    {
      "key": "meal1",
      "kind": "meal",
      "title": "[SAMPLE] Lunch plan 1",
      "data": {
        "date": "@day+0",
        "servings": 20,
        "recipe_ids": [
          "@recipe1",
          "@recipe5"
        ],
        "notes": "Edit the servings and menu combination. Confirm purchase quantities separately."
      }
    },
    {
      "key": "meal2",
      "kind": "meal",
      "title": "[SAMPLE] Lunch plan 2",
      "data": {
        "date": "@day+1",
        "servings": 30,
        "recipe_ids": [
          "@recipe2",
          "@recipe4"
        ],
        "notes": "Edit the servings and menu combination. Confirm purchase quantities separately."
      }
    },
    {
      "key": "meal3",
      "kind": "meal",
      "title": "[SAMPLE] Lunch plan 3",
      "data": {
        "date": "@day+2",
        "servings": 15,
        "recipe_ids": [
          "@recipe3",
          "@recipe5"
        ],
        "notes": "Edit the servings and menu combination. Confirm purchase quantities separately."
      }
    },
    {
      "key": "purchase1",
      "kind": "purchase",
      "status": "draft",
      "title": "[SAMPLE] Chicken thigh request",
      "data": {
        "supplier": "[PRACTICE] One-stop Foods",
        "buyer": "[PRACTICE] One Meal Kitchen",
        "phone": "",
        "address": "Practice delivery location — not a real address",
        "delivery_date": "@day+0",
        "currency": "KRW",
        "notes": "Practice request only. Do not use for a real purchase or delivery.",
        "lines": [
          {
            "id": "@line0",
            "name": "Chicken thigh",
            "quantity": 2,
            "unit": "kg",
            "spec": "Practice reviewing purchase specifications",
            "price": 9000
          }
        ]
      }
    },
    {
      "key": "purchase2",
      "kind": "purchase",
      "status": "draft",
      "title": "[SAMPLE] Tofu request",
      "data": {
        "supplier": "[PRACTICE] One-stop Foods",
        "buyer": "[PRACTICE] One Meal Kitchen",
        "phone": "",
        "address": "Practice delivery location — not a real address",
        "delivery_date": "@day+1",
        "currency": "KRW",
        "notes": "Practice request only. Do not use for a real purchase or delivery.",
        "lines": [
          {
            "id": "@line1",
            "name": "Tofu",
            "quantity": 4,
            "unit": "pack",
            "spec": "Practice reviewing purchase specifications",
            "price": null
          }
        ]
      }
    },
    {
      "key": "purchase3",
      "kind": "purchase",
      "status": "review",
      "title": "[SAMPLE] Beef request",
      "data": {
        "supplier": "[PRACTICE] One-stop Foods",
        "buyer": "[PRACTICE] One Meal Kitchen",
        "phone": "",
        "address": "Practice delivery location — not a real address",
        "delivery_date": "@day+2",
        "currency": "KRW",
        "notes": "Practice request only. Do not use for a real purchase or delivery.",
        "lines": [
          {
            "id": "@line2",
            "name": "Beef",
            "quantity": 1.5,
            "unit": "kg",
            "spec": "Practice reviewing purchase specifications",
            "price": 24000
          }
        ]
      }
    },
    {
      "key": "purchase4",
      "kind": "purchase",
      "status": "approved",
      "title": "[SAMPLE] Mushrooms request",
      "data": {
        "supplier": "[PRACTICE] One-stop Foods",
        "buyer": "[PRACTICE] One Meal Kitchen",
        "phone": "",
        "address": "Practice delivery location — not a real address",
        "delivery_date": "@day+0",
        "currency": "KRW",
        "notes": "Practice request only. Do not use for a real purchase or delivery.",
        "lines": [
          {
            "id": "@line3",
            "name": "Mushrooms",
            "quantity": 3,
            "unit": "kg",
            "spec": "Practice reviewing purchase specifications",
            "price": 7000
          }
        ]
      }
    },
    {
      "key": "purchase5",
      "kind": "purchase",
      "status": "received",
      "title": "[SAMPLE] Potatoes request",
      "data": {
        "supplier": "[PRACTICE] One-stop Foods",
        "buyer": "[PRACTICE] One Meal Kitchen",
        "phone": "",
        "address": "Practice delivery location — not a real address",
        "delivery_date": "@day+1",
        "currency": "KRW",
        "notes": "Practice request only. Do not use for a real purchase or delivery.",
        "lines": [
          {
            "id": "@line4",
            "name": "Potatoes",
            "quantity": 5,
            "unit": "kg",
            "spec": "Practice reviewing purchase specifications",
            "price": 3500
          }
        ]
      }
    },
    {
      "key": "cost1",
      "kind": "cost",
      "title": "[SAMPLE] Chicken vegetable rice bowl cost & price",
      "data": {
        "recipe_id": "@recipe1",
        "unit_cost": 3500,
        "unit_price": 7000,
        "currency": "KRW",
        "notes": "Illustrative amounts, not market prices. Edit per-portion cost and price, then compare future sales records."
      }
    },
    {
      "key": "cost2",
      "kind": "cost",
      "title": "[SAMPLE] Braised tofu and mushrooms cost & price",
      "data": {
        "recipe_id": "@recipe2",
        "unit_cost": 2500,
        "unit_price": 5000,
        "currency": "KRW",
        "notes": "Illustrative amounts, not market prices. Edit per-portion cost and price, then compare future sales records."
      }
    },
    {
      "key": "cost3",
      "kind": "cost",
      "title": "[SAMPLE] Beef bulgogi cost & price",
      "data": {
        "recipe_id": "@recipe3",
        "unit_cost": 6000,
        "unit_price": 11000,
        "currency": "KRW",
        "notes": "Illustrative amounts, not market prices. Edit per-portion cost and price, then compare future sales records."
      }
    },
    {
      "key": "sale1",
      "kind": "sale",
      "title": "[SAMPLE] Sale 1",
      "data": {
        "cost_id": "@cost1",
        "date": "@day+0",
        "quantity": 12,
        "unit_cost": 3500,
        "unit_price": 7000,
        "currency": "KRW"
      }
    },
    {
      "key": "sale2",
      "kind": "sale",
      "title": "[SAMPLE] Sale 2",
      "data": {
        "cost_id": "@cost2",
        "date": "@day-1",
        "quantity": 18,
        "unit_cost": 2500,
        "unit_price": 5000,
        "currency": "KRW"
      }
    },
    {
      "key": "sale3",
      "kind": "sale",
      "title": "[SAMPLE] Sale 3",
      "data": {
        "cost_id": "@cost3",
        "date": "@day-7",
        "quantity": 25,
        "unit_cost": 6000,
        "unit_price": 11000,
        "currency": "KRW"
      }
    },
    {
      "key": "sale4",
      "kind": "sale",
      "title": "[SAMPLE] Sale 4",
      "data": {
        "cost_id": "@cost1",
        "date": "@day-32",
        "quantity": 10,
        "unit_cost": 3500,
        "unit_price": 7000,
        "currency": "KRW"
      }
    }
  ]
}
$samples$::jsonb; item jsonb; doc jsonb; map jsonb:='{}'; ids text; k text; w public.business_records; day date:=(now() at time zone 'Asia/Seoul')::date;begin
 -- Private helper: never callable by clients. Called only while campaign/workspace locks are held.
 for item in select value from jsonb_array_elements(catalog->p_language) loop map:=map||jsonb_build_object(item->>'key',gen_random_uuid());end loop;
 for i in 0..4 loop map:=map||jsonb_build_object('line'||i,gen_random_uuid());end loop;
 for i in -32..2 loop map:=map||jsonb_build_object('day'||case when i>=0 then '+' else '' end||i,(day+i)::text);end loop;
 for item in select value from jsonb_array_elements(catalog->p_language) loop
  ids:=(item->'data')::text;
  for k in select jsonb_object_keys(map) loop ids:=replace(ids,to_jsonb('@'||k)::text,to_jsonb(map->>k)::text);end loop;
  doc:=ids::jsonb;
  if not coalesce(public.business_data_valid(item->>'kind',doc),false) then raise exception 'BUSINESS_TEST_SEED_INVALID';end if;
  insert into public.business_records(id,workspace_id,kind,title,data,status,updated_by)
  values((map->>(item->>'key'))::uuid,p_workspace,item->>'kind',item->>'title',doc,coalesce(item->>'status','draft'),auth.uid()) returning * into w;
  insert into public.business_record_versions(record_id,revision,title,data,status,actor_id) values(w.id,w.revision,w.title,w.data,w.status,auth.uid());
 end loop;
end;$seed$;
create function public.business_test_start(p_campaign uuid,p_language text,p_display_name text) returns uuid language plpgsql security definer set search_path='' as $$
declare w uuid;begin
 if auth.uid() is null or coalesce((auth.jwt()->>'is_anonymous')::boolean,false) then raise exception 'BUSINESS_AUTH';end if;
 perform 1 from public.business_test_campaigns where id=p_campaign for update;
 if not public.business_test_eligible(p_campaign,auth.uid()) then raise exception 'BUSINESS_TEST_CLOSED';end if;
 if p_language is null or p_language not in ('ko','en') or p_display_name is null or length(btrim(p_display_name)) not between 1 and 120 then raise exception 'BUSINESS_TEST_INVALID';end if;
 select workspace_id into w from public.business_test_workspaces where campaign_id=p_campaign and owner_id=auth.uid();
 if found then return w;end if;
 if (select count(*) from public.business_test_workspaces where campaign_id=p_campaign)>=1000 then raise exception 'BUSINESS_LIMIT';end if;
 insert into public.business_workspaces(owner_id,name) values(auth.uid(),case when p_language='en' then '[PRACTICE] Business workspace' else '[연습] 업소 업무 테스트' end) returning id into w;
 insert into public.business_test_workspaces(workspace_id,campaign_id,owner_id,language) values(w,p_campaign,auth.uid(),p_language);
 insert into public.business_members(workspace_id,user_id,display_name,permissions) values(w,auth.uid(),btrim(p_display_name),array['recipes.read','recipes.write','purchasing.read','purchasing.write','finance.read','finance.write','purchases.approve']);
 perform public.business_test_seed(w,p_language);
 insert into public.business_test_events(campaign_id,actor_id,action) values(p_campaign,auth.uid(),'samples_started');
 return w;
end;$$;
create function public.business_test_reset(p_workspace uuid,p_generation integer) returns integer language plpgsql security definer set search_path='' as $$
declare t public.business_test_workspaces;begin
 if auth.uid() is null or coalesce((auth.jwt()->>'is_anonymous')::boolean,false) then raise exception 'BUSINESS_AUTH';end if;
 select * into t from public.business_test_workspaces where workspace_id=p_workspace;
 perform 1 from public.business_test_campaigns where id=t.campaign_id for update;
 perform 1 from public.business_workspaces where id=p_workspace for update;
 select * into t from public.business_test_workspaces where workspace_id=p_workspace for update;
 if auth.uid() is null or t.owner_id is distinct from auth.uid() or not public.business_test_eligible(t.campaign_id,auth.uid()) then raise exception 'BUSINESS_TEST_CLOSED';end if;
 if p_generation is distinct from t.generation then raise exception 'BUSINESS_STALE';end if;
 delete from public.business_records where workspace_id=p_workspace;
 perform public.business_test_seed(p_workspace,t.language);
 update public.business_test_workspaces set generation=generation+1 where workspace_id=p_workspace;
 insert into public.business_test_events(campaign_id,actor_id,action) values(t.campaign_id,auth.uid(),'samples_reset');
 return t.generation+1;
end;$$;

create or replace function public.business_owner(p_workspace uuid) returns boolean language sql stable security definer set search_path='' as $$
 select auth.uid() is not null and not coalesce((auth.jwt()->>'is_anonymous')::boolean,false)
 and public.business_test_access(p_workspace,auth.uid())
 and exists(select 1 from public.business_workspaces where id=p_workspace and owner_id=auth.uid());
$$;

create or replace function public.business_paid(p_workspace uuid) returns boolean language sql stable security definer set search_path='' as $$
 select case when exists(select 1 from public.business_test_workspaces where workspace_id=p_workspace)
 then public.business_test_access(p_workspace,owner_id)
 else coalesce((public.member_feature_snapshot(owner_id)->>'can_manage_costs')::boolean,false) end
 from public.business_workspaces where id=p_workspace;
$$;

create or replace function public.business_can(p_workspace uuid,p_permission text) returns boolean language sql stable security definer set search_path='' as $$
 select auth.uid() is not null and not coalesce((auth.jwt()->>'is_anonymous')::boolean,false)
 and public.business_test_access(p_workspace,auth.uid())
 and exists(select 1 from public.business_workspaces w join public.business_members m on m.workspace_id=w.id
 where w.id=p_workspace and m.user_id=auth.uid() and m.active
 and (w.owner_id=auth.uid() or p_permission=any(m.permissions))
 and (p_permission not in ('finance.read','finance.write','recipes.write','purchasing.write','purchases.approve') or public.business_paid(w.id)));
$$;

create or replace function public.business_create(p_name text,p_display_name text) returns uuid language plpgsql security definer set search_path='' as $$
declare u uuid:=auth.uid(); w uuid; p text[]:=array['recipes.read','recipes.write','purchasing.read','purchasing.write','finance.read','finance.write','purchases.approve'];begin
 if u is null or coalesce((auth.jwt()->>'is_anonymous')::boolean,false) then raise exception 'BUSINESS_AUTH';end if;
 if not coalesce((public.member_feature_snapshot(u)->>'can_manage_costs')::boolean,false) then raise exception 'BUSINESS_PLAN';end if;
 perform pg_advisory_xact_lock(hashtextextended('business-create:'||u::text,0));
 if (select count(*) from public.business_workspaces where owner_id=u and not exists(select 1 from public.business_test_workspaces t where t.workspace_id=business_workspaces.id))>=3 then raise exception 'BUSINESS_LIMIT';end if;
 insert into public.business_workspaces(owner_id,name) values(u,btrim(p_name)) returning id into w;
 insert into public.business_members(workspace_id,user_id,display_name,permissions) values(w,u,btrim(p_display_name),p);
 return w;
end;$$;

create or replace function public.business_context(p_workspace uuid) returns jsonb language plpgsql stable security definer set search_path='' as $$
declare w public.business_workspaces; m public.business_members;begin
 if auth.uid() is null or coalesce((auth.jwt()->>'is_anonymous')::boolean,false) then raise exception 'BUSINESS_AUTH';end if;
 select * into w from public.business_workspaces where id=p_workspace;
 select * into m from public.business_members where workspace_id=p_workspace and user_id=auth.uid() and active;
 if not public.business_test_access(p_workspace,auth.uid()) then raise exception 'BUSINESS_TEST_CLOSED';end if;
 if w.id is null or m.user_id is null then raise exception 'BUSINESS_DENIED';end if;
 return jsonb_build_object('id',w.id,'name',w.name,'owner',w.owner_id=auth.uid(),'paid',coalesce(public.business_paid(w.id),false),'require_approval',w.require_purchase_approval,'permissions',to_jsonb(m.permissions),'display_name',m.display_name,'is_test',exists(select 1 from public.business_test_workspaces where workspace_id=w.id));
end;$$;

create or replace function public.business_document(p_workspace uuid,p_id uuid,p_revision bigint) returns jsonb language plpgsql stable security definer set search_path='' as $$
declare r public.business_records;begin
 if not public.business_can(p_workspace,'purchasing.read') or not coalesce(public.business_paid(p_workspace),false) then raise exception 'BUSINESS_DENIED';end if;
 select * into r from public.business_records where id=p_id and workspace_id=p_workspace and kind='purchase' and status<>'cancelled';
 if r.id is null then raise exception 'BUSINESS_NOT_FOUND';end if;
 if r.revision is distinct from p_revision then raise exception 'BUSINESS_STALE';end if;
 if not public.business_purchase_ready(r.data) then raise exception 'BUSINESS_PURCHASE_INCOMPLETE';end if;
 if exists(select 1 from public.business_test_workspaces where workspace_id=p_workspace) then
  return jsonb_set(to_jsonb(r),'{data,notes}',to_jsonb(E'[연습용 / PRACTICE ONLY] 실제 발주 금지 · Not a real order.\n'||coalesce(r.data->>'notes','')))||jsonb_build_object('is_test',true);
 end if;
 return to_jsonb(r);
end;$$;

revoke all on function public.business_test_eligible(uuid,uuid),public.business_test_access(uuid,uuid),public.business_test_write_guard(),public.business_test_seed(uuid,text) from public,anon,authenticated;
revoke all on function public.business_test_options(),public.business_test_start(uuid,text,text),public.business_test_reset(uuid,integer),public.admin_business_test_list(),public.admin_business_test_create(text,integer,text),public.admin_business_test_participant(uuid,text,boolean),public.admin_business_test_end(uuid),public.admin_business_test_cleanup(uuid) from public,anon;
grant execute on function public.business_test_options(),public.business_test_start(uuid,text,text),public.business_test_reset(uuid,integer),public.admin_business_test_list(),public.admin_business_test_create(text,integer,text),public.admin_business_test_participant(uuid,text,boolean),public.admin_business_test_end(uuid),public.admin_business_test_cleanup(uuid) to authenticated;
notify pgrst,'reload schema';
