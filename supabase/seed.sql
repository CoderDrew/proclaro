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

-- ---------------------------------------------------------------------------
-- Bidders and open solicitations (slice 2a). All names are fictional.
-- Bidder users sign in with the same local-only password as the staff above.
-- ---------------------------------------------------------------------------
insert into public.organizations (id, name, kind) values
  ('10000000-0000-0000-0000-000000000011', 'Ridgeback Builders LLC',    'bidder'),
  ('10000000-0000-0000-0000-000000000012', 'Granite Mesa Contractors', 'bidder');

insert into public.bidder_companies (org_id, address, contact_name, contact_phone, contact_email) values
  ('10000000-0000-0000-0000-000000000011', '12 Quarry Lane, Calderton', 'Riley Ridgeback', '555-0111', 'bidder.ridgeback@example.test'),
  ('10000000-0000-0000-0000-000000000012', '90 Mesa Road, Calderton',   'Gale Granite',    '555-0112', 'bidder.granite@example.test');

do $$
declare
  u record;
begin
  for u in
    select * from (values
      ('20000000-0000-0000-0000-000000000011'::uuid, 'bidder.ridgeback@example.test', 'Riley Ridgeback', '10000000-0000-0000-0000-000000000011'::uuid),
      ('20000000-0000-0000-0000-000000000012'::uuid, 'bidder.granite@example.test',   'Gale Granite',    '10000000-0000-0000-0000-000000000012'::uuid)
    ) as t(id, email, display_name, org_id)
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

    -- Bidder-org profiles are guarded (0008): set the same transaction-local flag register_bidder sets.
    perform set_config('app.registering', u.org_id::text, true);
    insert into public.profiles (user_id, org_id, display_name, is_admin)
    values (u.id, u.org_id, u.display_name, false);
    perform set_config('app.registering', '', true);
  end loop;
end;
$$;

-- Two published, released solicitations, inserted directly (slice 1 publishing cannot produce a released row in
-- under three days). They have no RFB or bid-form files, so their public download links are absent.
--   27-0001: $185,000 (bid bond required), due in 14 days at 13:00 local.
--   27-0002: $120,000 (no bid bond), due about 20 minutes after the seed runs, for walking through close.
do $$
declare
  v_tz      text := (select timezone from public.settings where id = 1);
  v_agency  uuid := '10000000-0000-0000-0000-000000000002';
  v_author  uuid := '20000000-0000-0000-0000-000000000001';
  v_clauses jsonb := (select coalesce(jsonb_object_agg(c.key, c.body), '{}'::jsonb)
                        from (select distinct on (key) key, body from public.clauses order by key, version desc) c);
  v_settings jsonb := (select jsonb_build_object('stateName', s.state_name, 'officeName', s.office_name, 'timezone', s.timezone)
                         from public.settings s where s.id = 1);
  v_base    jsonb;
  v_data    jsonb;
  v_due     timestamptz;
begin
  v_base := jsonb_build_object(
    'category', 'construction', 'scopeNotes', '', 'specialProvisions', '', 'fundingOther', '', 'federalFunds', false,
    'fundingSource', 'capital_construction',
    'location', jsonb_build_object('address', '1 Example Way', 'city', 'Calderton', 'county', 'Calder'),
    'requester', jsonb_build_object('name', 'Pat Example', 'email', 'pat@example.test', 'phone', '555-0100'),
    'projectManager', jsonb_build_object('name', 'Sam Example', 'email', 'sam@example.test', 'phone', '555-0101'),
    'releaseDate', to_char(app.today() - 3, 'YYYY-MM-DD'),
    'adStart', to_char(app.today() - 3, 'YYYY-MM-DD'), 'adEnd', to_char(app.today() + 7, 'YYYY-MM-DD'),
    'newspapers', 'Calder Courier',
    'questionsDue', jsonb_build_object('date', to_char(app.today() + 2, 'YYYY-MM-DD'), 'time', '13:00'),
    'answersDue', jsonb_build_object('date', to_char(app.today() + 5, 'YYYY-MM-DD'), 'time', '13:00'),
    'tentativeAwardDate', null, 'estimatedStartDate', null, 'estimatedCompletionDate', null,
    'bidValidityDays', 90,
    'preBid', jsonb_build_object('kind', 'none', 'format', null, 'date', null, 'time', null, 'location', ''),
    'backgroundCheck', jsonb_build_object('required', false, 'contact', '', 'leadDays', null),
    'pageLimits', '{}'::jsonb, 'attachments', '[]'::jsonb);

  -- 27-0001
  v_data := v_base || jsonb_build_object(
    'shortTitle', 'Hall Roof Replacement', 'longTitle', 'Roof Replacement at Calder Training Hall',
    'summary', 'Replace the roof membranes and repair the canopy.',
    'projectDescription', 'Replace the roof membranes on the main hall and repair the entry canopy.',
    'estimateCents', 18500000,
    'bidDueDate', to_char(app.today() + 14, 'YYYY-MM-DD'), 'bidDueTime', '13:00',
    'schedule', jsonb_build_object(
      'items', jsonb_build_array(
        jsonb_build_object('name', 'Base bid', 'description', 'Roof membrane replacement'),
        jsonb_build_object('name', 'Item 2', 'description', 'Canopy repair')),
      'alternates', jsonb_build_array(
        jsonb_build_object('kind', 'deductive', 'description', 'Omit canopy repair'))),
    'optionalSections', jsonb_build_array('qualifications', 'references'));
  v_due := app.bid_due_at(v_data);
  insert into public.solicitations (agency_id, created_by, state, number, fiscal_year, data, version,
                                    published_at, release_date, bid_due_at, published_snapshot)
  values (v_agency, v_author, 'published', '27-0001', 2027, v_data, 1, now(), app.today() - 3, v_due,
          jsonb_build_object('data', v_data, 'clauses', v_clauses, 'settings', v_settings, 'renderedAt', now()));

  -- 27-0002
  v_due := date_trunc('minute', now()) + interval '20 minutes';
  v_data := v_base || jsonb_build_object(
    'shortTitle', 'Yard Fence Repair', 'longTitle', 'Perimeter Fence Repair at Calder Work Yard',
    'summary', 'Repair and repaint the perimeter fence.',
    'projectDescription', 'Repair damaged fence sections and repaint the perimeter fence.',
    'estimateCents', 12000000,
    'bidDueDate', to_char(v_due at time zone v_tz, 'YYYY-MM-DD'),
    'bidDueTime', to_char(v_due at time zone v_tz, 'HH24:MI'),
    'schedule', jsonb_build_object(
      'items', jsonb_build_array(
        jsonb_build_object('name', 'Base bid', 'description', 'Fence section repair'),
        jsonb_build_object('name', 'Item 2', 'description', 'Repaint')),
      'alternates', jsonb_build_array(
        jsonb_build_object('kind', 'additive', 'description', 'Add a gate'))),
    'optionalSections', jsonb_build_array('references'));
  insert into public.solicitations (agency_id, created_by, state, number, fiscal_year, data, version,
                                    published_at, release_date, bid_due_at, published_snapshot)
  values (v_agency, v_author, 'published', '27-0002', 2027, v_data, 1, now(), app.today() - 3, v_due,
          jsonb_build_object('data', v_data, 'clauses', v_clauses, 'settings', v_settings, 'renderedAt', now()));

  insert into public.number_sequences (fiscal_year, last_seq) values (2027, 2);
end;
$$;
