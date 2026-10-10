\set ON_ERROR_STOP on
DO $$ BEGIN
  IF has_function_privilege('anon','public.consume_youtube_search_rate_limit()','execute') OR
     has_function_privilege('anon','public.promote_subscriber_recipe_to_creator(uuid,boolean,boolean,boolean,boolean,boolean)','execute') THEN
    RAISE EXCEPTION 'ANON_RPC_STILL_EXECUTABLE';
  END IF;
END $$;
INSERT INTO auth.users(id,email) VALUES
 ('58a00000-0000-4000-8000-000000000001','audit-a@example.invalid'),
 ('58a00000-0000-4000-8000-000000000002','audit-b@example.invalid');
INSERT INTO public.profiles(id,role) VALUES
 ('58a00000-0000-4000-8000-000000000001','user'),
 ('58a00000-0000-4000-8000-000000000002','user') ON CONFLICT(id) DO NOTHING;
INSERT INTO public.recipes_creator(id,author_id,title) VALUES
 ('58a00000-0000-4000-8000-000000000010','58a00000-0000-4000-8000-000000000002','Private default audit');
DO $$ BEGIN
 IF (SELECT is_published FROM public.recipes_creator WHERE id='58a00000-0000-4000-8000-000000000010') THEN RAISE EXCEPTION 'DEFAULT_PUBLIC'; END IF;
END $$;
SELECT set_config('request.jwt.claim.sub','58a00000-0000-4000-8000-000000000001',true);
SELECT set_config('request.jwt.claims','{"sub":"58a00000-0000-4000-8000-000000000001","role":"authenticated"}',true);
SET LOCAL ROLE authenticated;
DO $$ DECLARE denied boolean:=false; BEGIN
 IF EXISTS(SELECT 1 FROM public.recipes_creator WHERE id='58a00000-0000-4000-8000-000000000010') THEN RAISE EXCEPTION 'OTHER_PRIVATE_VISIBLE'; END IF;
 BEGIN UPDATE public.profiles SET role='admin' WHERE id=auth.uid(); EXCEPTION WHEN OTHERS THEN denied:=true; END;
 IF NOT denied THEN RAISE EXCEPTION 'ROLE_ESCALATION_ALLOWED'; END IF;
 denied:=false;
 BEGIN PERFORM public.admin_list_memberships(); EXCEPTION WHEN OTHERS THEN denied:=true; END;
 IF NOT denied THEN RAISE EXCEPTION 'ADMIN_READ_ALLOWED'; END IF;
END $$;
INSERT INTO public.recipes_user(id,owner_id,title,ingredients,steps) VALUES
 ('58a00000-0000-4000-8000-000000000020',auth.uid(),'Copy audit','[]','[]');
DO $$ DECLARE copied public.recipes_creator; BEGIN
 copied:=public.promote_subscriber_recipe_to_creator('58a00000-0000-4000-8000-000000000020');
 IF copied.is_published THEN RAISE EXCEPTION 'COPY_BECAME_PUBLIC'; END IF;
END $$;
RESET ROLE;
SELECT set_config('request.jwt.claim.sub','',true);
SELECT set_config('request.jwt.claims','{"role":"anon"}',true);
GRANT SELECT ON public.recipes_creator TO anon;
SET LOCAL ROLE anon;
DO $$ BEGIN
 IF EXISTS(SELECT 1 FROM public.recipes_creator WHERE id='58a00000-0000-4000-8000-000000000010') THEN RAISE EXCEPTION 'ANON_PRIVATE_VISIBLE'; END IF;
END $$;
RESET ROLE;
SELECT 'PASS private default, anonymous RPC denial, cross-account isolation, role escalation and admin denial' AS result;
