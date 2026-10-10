-- Confirmed 2026-10 membership price policy.
-- Google Play remains the purchase-time authority; these values keep the
-- server catalog, administration data, and app fallback copy aligned.

update public.membership_plans
set price_krw = case code
  when 'plus_monthly' then 9900
  when 'plus_annual' then 99000
  when 'business_monthly' then 19000
  when 'business_annual' then 189000
  else price_krw
end
where code in (
  'plus_monthly',
  'plus_annual',
  'business_monthly',
  'business_annual'
);

update public.membership_offer_drafts
set proposed_price_krw = case code
  when 'plus_monthly' then 9900
  when 'plus_annual' then 99000
  when 'business_monthly' then 19000
  when 'business_annual' then 189000
  else proposed_price_krw
end
where code in (
  'plus_monthly',
  'plus_annual',
  'business_monthly',
  'business_annual'
);

do $$
begin
  if (
    select count(*)
    from public.membership_plans
    where (code = 'plus_monthly' and price_krw = 9900)
       or (code = 'plus_annual' and price_krw = 99000)
       or (code = 'business_monthly' and price_krw = 19000)
       or (code = 'business_annual' and price_krw = 189000)
  ) <> 4 then
    raise exception 'CONFIRMED_MEMBERSHIP_PRICE_UPDATE_INCOMPLETE';
  end if;

  if (
    select count(*)
    from public.membership_offer_drafts
    where (code = 'plus_monthly' and proposed_price_krw = 9900)
       or (code = 'plus_annual' and proposed_price_krw = 99000)
       or (code = 'business_monthly' and proposed_price_krw = 19000)
       or (code = 'business_annual' and proposed_price_krw = 189000)
  ) <> 4 then
    raise exception 'CONFIRMED_MEMBERSHIP_DRAFT_PRICE_UPDATE_INCOMPLETE';
  end if;
end;
$$;
