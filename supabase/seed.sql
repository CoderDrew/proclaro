-- Local development seed. All names are fictional.
-- Password `proclaro-dev` is for the local stack only; never use it anywhere else.

insert into public.settings (id, state_name, office_name, timezone, fiscal_year_start_month)
values (1, 'State of Calder', 'Calder State Construction Office', 'America/Denver', 7)
on conflict (id) do update set
  state_name = excluded.state_name,
  office_name = excluded.office_name,
  timezone = excluded.timezone,
  fiscal_year_start_month = excluded.fiscal_year_start_month;

insert into public.holidays (day, name) values
  ('2026-11-26', 'Thanksgiving Day'),
  ('2026-12-25', 'Christmas Day');

insert into public.organizations (id, name, kind) values
  ('10000000-0000-0000-0000-000000000001', 'Calder State Construction Office', 'office'),
  ('10000000-0000-0000-0000-000000000002', 'Calder Department of Corrections', 'agency'),
  ('10000000-0000-0000-0000-000000000003', 'Calder Parks Division',            'agency');

do $$
declare
  u record;
begin
  for u in
    select * from (values
      ('20000000-0000-0000-0000-000000000001'::uuid, 'author.corrections@example.test', 'Corrections Author', '10000000-0000-0000-0000-000000000002'::uuid, false),
      ('20000000-0000-0000-0000-000000000002'::uuid, 'author.parks@example.test',       'Parks Author',       '10000000-0000-0000-0000-000000000003'::uuid, false),
      ('20000000-0000-0000-0000-000000000003'::uuid, 'reviewer1@example.test',          'Reviewer One',       '10000000-0000-0000-0000-000000000001'::uuid, false),
      ('20000000-0000-0000-0000-000000000004'::uuid, 'reviewer2@example.test',          'Reviewer Two',       '10000000-0000-0000-0000-000000000001'::uuid, false),
      ('20000000-0000-0000-0000-000000000005'::uuid, 'admin@example.test',              'Office Admin',       '10000000-0000-0000-0000-000000000001'::uuid, true)
    ) as t(id, email, display_name, org_id, is_admin)
  loop
    insert into auth.users (
      instance_id, id, aud, role, email, encrypted_password, email_confirmed_at,
      raw_app_meta_data, raw_user_meta_data, created_at, updated_at,
      confirmation_token, recovery_token, email_change, email_change_token_new
    ) values (
      '00000000-0000-0000-0000-000000000000', u.id, 'authenticated', 'authenticated', u.email,
      extensions.crypt('proclaro-dev', extensions.gen_salt('bf')), now(),
      '{"provider":"email","providers":["email"]}', jsonb_build_object('display_name', u.display_name),
      now(), now(), '', '', '', ''
    );

    insert into auth.identities (
      id, user_id, provider_id, provider, identity_data, last_sign_in_at, created_at, updated_at
    ) values (
      gen_random_uuid(), u.id, u.id::text, 'email',
      jsonb_build_object('sub', u.id::text, 'email', u.email, 'email_verified', true),
      now(), now(), now()
    );

    insert into public.profiles (user_id, org_id, display_name, is_admin)
    values (u.id, u.org_id, u.display_name, u.is_admin);
  end loop;
end;
$$;
