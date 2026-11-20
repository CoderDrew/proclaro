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
  ('10000000-0000-0000-0000-000000000012', 'Granite Mesa Contractors', 'bidder'),
  ('10000000-0000-0000-0000-000000000013', 'Juniper Flats Paving',     'bidder'),
  ('10000000-0000-0000-0000-000000000014', 'Basalt Creek Builders',    'bidder');

-- Ridgeback claims Calder residency (slice 2b): the office verifies the certificate after close.
insert into public.bidder_companies (org_id, address, contact_name, contact_phone, contact_email,
                                     resident_claimed, resident_certificate) values
  ('10000000-0000-0000-0000-000000000011', '12 Quarry Lane, Calderton', 'Riley Ridgeback', '555-0111', 'bidder.ridgeback@example.test', true,  'CR-0042'),
  ('10000000-0000-0000-0000-000000000012', '90 Mesa Road, Calderton',   'Gale Granite',    '555-0112', 'bidder.granite@example.test',   false, null),
  ('10000000-0000-0000-0000-000000000013', '7 Juniper Flats Road, Calderton', 'Jo Juniper', '555-0113', 'bidder.juniper@example.test', false, null),
  ('10000000-0000-0000-0000-000000000014', '41 Basalt Creek Drive, Calderton', 'Bo Basalt', '555-0114', 'bidder.basalt@example.test',  false, null);

do $$
declare
  u record;
begin
  for u in
    select * from (values
      ('20000000-0000-0000-0000-000000000011'::uuid, 'bidder.ridgeback@example.test', 'Riley Ridgeback', '10000000-0000-0000-0000-000000000011'::uuid),
      ('20000000-0000-0000-0000-000000000012'::uuid, 'bidder.granite@example.test',   'Gale Granite',    '10000000-0000-0000-0000-000000000012'::uuid),
      ('20000000-0000-0000-0000-000000000013'::uuid, 'bidder.juniper@example.test',   'Jo Juniper',      '10000000-0000-0000-0000-000000000013'::uuid),
      ('20000000-0000-0000-0000-000000000014'::uuid, 'bidder.basalt@example.test',    'Bo Basalt',       '10000000-0000-0000-0000-000000000014'::uuid)
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

-- Seed-only helper (dropped at the end of this file): a submitted v1 bid inserted directly, with its signed original
-- and, optionally, its paper bid bond logged by Reviewer One at p_logged_at (as log_bid_original would record them).
create function app.seed_closed_bid(
  p_sol uuid, p_bidder uuid, p_items bigint[], p_alts bigint[], p_choice public.bid_bond_choice,
  p_apprentice boolean, p_submitted_at timestamptz, p_logged_at timestamptz, p_bond_logged boolean)
returns uuid
language plpgsql
set search_path = ''
as $$
declare
  v_org      uuid := (select p.org_id from public.profiles p where p.user_id = p_bidder);
  v_bid      uuid := gen_random_uuid();
  v_ref      text := app.new_bid_reference();
  v_reviewer uuid := '20000000-0000-0000-0000-000000000003';
begin
  insert into public.bids (id, solicitation_id, bidder_org_id, reference, created_by, created_at)
  values (v_bid, p_sol, v_org, v_ref, p_bidder, p_submitted_at - interval '1 day');
  insert into public.bid_versions (bid_id, version, submitted_at, submitted_by, item_cents, alternate_cents,
                                   bid_bond_choice, apprentice_commitment, bidder_legal_name)
  select v_bid, 1, p_submitted_at, p_bidder, p_items, p_alts, p_choice, p_apprentice, o.name
    from public.organizations o where o.id = v_org;
  insert into public.bid_original_log (solicitation_id, bid_id, reference, version, item, received_at, logged_by, logged_at)
  values (p_sol, v_bid, v_ref, 1, 'signed_form', p_logged_at, v_reviewer, p_logged_at);
  if p_bond_logged then
    insert into public.bid_original_log (solicitation_id, bid_id, reference, version, item, received_at, logged_by, logged_at)
    values (p_sol, v_bid, v_ref, 1, 'bid_bond', p_logged_at, v_reviewer, p_logged_at);
  end if;
  return v_bid;
end;
$$;

-- Published, released solicitations, inserted directly (slice 1 publishing cannot produce a released row in under
-- three days). Each row gets the rfb_path / bid_form_path publish would pin (solicitations/{id}/v1/...), so the public
-- page renders, but no PDF objects are uploaded: SQL cannot write file bytes, so the page lists the documents as
-- "(unavailable)". None has a solicitation_funding row except 27-0003 (the others use the estimate fallback).
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
  v_id      uuid;
  b         record;
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
  v_id := gen_random_uuid();
  insert into public.solicitations (id, agency_id, created_by, state, number, fiscal_year, data, version,
                                    published_at, release_date, bid_due_at, published_snapshot, rfb_path, bid_form_path)
  values (v_id, v_agency, v_author, 'published', '27-0001', 2027, v_data, 1, now(), app.today() - 3, v_due,
          jsonb_build_object('data', v_data, 'clauses', v_clauses, 'settings', v_settings, 'renderedAt', now()),
          format('solicitations/%s/v1/rfb.pdf', v_id), format('solicitations/%s/v1/bid-form.pdf', v_id));

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
  v_id := gen_random_uuid();
  insert into public.solicitations (id, agency_id, created_by, state, number, fiscal_year, data, version,
                                    published_at, release_date, bid_due_at, published_snapshot, rfb_path, bid_form_path)
  values (v_id, v_agency, v_author, 'published', '27-0002', 2027, v_data, 1, now(), app.today() - 3, v_due,
          jsonb_build_object('data', v_data, 'clauses', v_clauses, 'settings', v_settings, 'renderedAt', now()),
          format('solicitations/%s/v1/rfb.pdf', v_id), format('solicitations/%s/v1/bid-form.pdf', v_id));

  -- 27-0003 (slice 2b): closed one hour before the seed runs, four sealed bids, ready for bid review -> recap -> award.
  -- Funding $1,250,000.00 is frozen in solicitation_funding (confidential until the recap is posted), never in data.
  -- Expected recap once Basalt's bond is cured, every bid accepted and Ridgeback's certificate verified: alternate 1
  -- only; Ridgeback first by resident preference, then Granite (evaluated $1,207,800.00 with the apprentice credit),
  -- Juniper ($1,220,000.00) and Basalt ($1,232,000.00). Without the verification, Granite ranks first.
  v_due := date_trunc('minute', now()) - interval '1 hour';
  v_data := v_base || jsonb_build_object(
    'shortTitle', 'Maintenance Building Expansion', 'longTitle', 'Maintenance building expansion',
    'summary', 'Expand the maintenance building with two new service bays.',
    'projectDescription', 'Add two service bays and a parts room to the maintenance building at the Calder work yard.',
    'estimateCents', 120000000,
    'releaseDate', to_char(app.today() - 21, 'YYYY-MM-DD'),
    'adStart', to_char(app.today() - 21, 'YYYY-MM-DD'), 'adEnd', to_char(app.today() - 7, 'YYYY-MM-DD'),
    'questionsDue', jsonb_build_object('date', to_char(app.today() - 14, 'YYYY-MM-DD'), 'time', '13:00'),
    'answersDue', jsonb_build_object('date', to_char(app.today() - 10, 'YYYY-MM-DD'), 'time', '13:00'),
    'bidDueDate', to_char(v_due at time zone v_tz, 'YYYY-MM-DD'),
    'bidDueTime', to_char(v_due at time zone v_tz, 'HH24:MI'),
    'schedule', jsonb_build_object(
      'items', jsonb_build_array(
        jsonb_build_object('name', 'Base bid', 'description', 'Service bay addition'),
        jsonb_build_object('name', 'Item 2', 'description', 'Parts room')),
      'alternates', jsonb_build_array(
        jsonb_build_object('kind', 'additive', 'description', 'Add skylights'),
        jsonb_build_object('kind', 'additive', 'description', 'Add solar-ready conduit'))),
    'optionalSections', jsonb_build_array('references'));
  v_id := gen_random_uuid();
  insert into public.solicitations (id, agency_id, created_by, state, number, fiscal_year, data, version,
                                    published_at, release_date, bid_due_at, published_snapshot, rfb_path, bid_form_path)
  values (v_id, v_agency, v_author, 'published', '27-0003', 2027, v_data, 1, now() - interval '21 days',
          app.today() - 21, v_due,
          jsonb_build_object('data', v_data, 'clauses', v_clauses, 'settings', v_settings, 'renderedAt', now()),
          format('solicitations/%s/v1/rfb.pdf', v_id), format('solicitations/%s/v1/bid-form.pdf', v_id));
  insert into public.solicitation_funding (solicitation_id, funding_cents) values (v_id, 125000000);

  -- Its bids: v1 each, submitted two hours before the due time, each signed original logged an hour before it. The
  -- paper bid bonds of Ridgeback, Granite and Juniper are logged with the originals; Basalt's is not, so Basalt's bid
  -- is pending cure at close.
  for b in
    select * from (values
      ('20000000-0000-0000-0000-000000000011'::uuid, array[100000000, 20000000]::bigint[], array[4000000, 6000000]::bigint[], false, true),
      ('20000000-0000-0000-0000-000000000012'::uuid, array[ 98000000, 20000000]::bigint[], array[4000000, 5500000]::bigint[], true,  true),
      ('20000000-0000-0000-0000-000000000013'::uuid, array[ 97500000, 20000000]::bigint[], array[4500000, 5000000]::bigint[], false, true),
      ('20000000-0000-0000-0000-000000000014'::uuid, array[ 99000000, 20000000]::bigint[], array[4200000, 5800000]::bigint[], false, false)
    ) as t(bidder, items, alts, apprentice, bond_logged)
  loop
    perform app.seed_closed_bid(v_id, b.bidder, b.items, b.alts, 'paper', b.apprentice,
                                v_due - interval '2 hours', v_due - interval '1 hour', b.bond_logged);
  end loop;

  -- 27-0004 (slice 2b): open for 14 days, estimate $1.5M, so a bidder can answer the apprentice commitment.
  v_data := v_base || jsonb_build_object(
    'shortTitle', 'Kitchen Renovation', 'longTitle', 'Kitchen Renovation at Calder Central Facility',
    'summary', 'Renovate the central kitchen and replace its ventilation.',
    'projectDescription', 'Renovate the central kitchen, replace the ventilation hoods and upgrade the walk-in cooler.',
    'estimateCents', 150000000,
    'bidDueDate', to_char(app.today() + 14, 'YYYY-MM-DD'), 'bidDueTime', '13:00',
    'schedule', jsonb_build_object(
      'items', jsonb_build_array(
        jsonb_build_object('name', 'Base bid', 'description', 'Kitchen renovation'),
        jsonb_build_object('name', 'Item 2', 'description', 'Ventilation hoods')),
      'alternates', jsonb_build_array(
        jsonb_build_object('kind', 'additive', 'description', 'Replace walk-in cooler'))),
    'optionalSections', jsonb_build_array('references'));
  v_due := app.bid_due_at(v_data);
  v_id := gen_random_uuid();
  insert into public.solicitations (id, agency_id, created_by, state, number, fiscal_year, data, version,
                                    published_at, release_date, bid_due_at, published_snapshot, rfb_path, bid_form_path)
  values (v_id, v_agency, v_author, 'published', '27-0004', 2027, v_data, 1, now(), app.today() - 3, v_due,
          jsonb_build_object('data', v_data, 'clauses', v_clauses, 'settings', v_settings, 'renderedAt', now()),
          format('solicitations/%s/v1/rfb.pdf', v_id), format('solicitations/%s/v1/bid-form.pdf', v_id));

  -- 27-0005 (slice 2b): estimate $180,000 (bid bond required), closes about 20 minutes after the seed runs. Juniper
  -- has a paper-bond bid with its signed original logged but no bond original, so the cure starts live at close.
  v_due := date_trunc('minute', now()) + interval '20 minutes';
  v_data := v_base || jsonb_build_object(
    'shortTitle', 'Boiler Replacement', 'longTitle', 'Boiler Replacement at Calder Records Center',
    'summary', 'Replace the two boilers and their controls.',
    'projectDescription', 'Remove the two existing boilers and install new boilers and controls.',
    'estimateCents', 18000000,
    'bidDueDate', to_char(v_due at time zone v_tz, 'YYYY-MM-DD'),
    'bidDueTime', to_char(v_due at time zone v_tz, 'HH24:MI'),
    'schedule', jsonb_build_object(
      'items', jsonb_build_array(
        jsonb_build_object('name', 'Base bid', 'description', 'Boiler replacement'),
        jsonb_build_object('name', 'Item 2', 'description', 'Controls')),
      'alternates', '[]'::jsonb),
    'optionalSections', jsonb_build_array('references'));
  v_id := gen_random_uuid();
  insert into public.solicitations (id, agency_id, created_by, state, number, fiscal_year, data, version,
                                    published_at, release_date, bid_due_at, published_snapshot, rfb_path, bid_form_path)
  values (v_id, v_agency, v_author, 'published', '27-0005', 2027, v_data, 1, now(), app.today() - 3, v_due,
          jsonb_build_object('data', v_data, 'clauses', v_clauses, 'settings', v_settings, 'renderedAt', now()),
          format('solicitations/%s/v1/rfb.pdf', v_id), format('solicitations/%s/v1/bid-form.pdf', v_id));
  perform app.seed_closed_bid(v_id, '20000000-0000-0000-0000-000000000013', array[16000000, 1500000]::bigint[],
                              '{}'::bigint[], 'paper', null, now() - interval '10 minutes', now() - interval '5 minutes',
                              false);

  insert into public.number_sequences (fiscal_year, last_seq) values (2027, 5);
end;
$$;

drop function app.seed_closed_bid(uuid, uuid, bigint[], bigint[], public.bid_bond_choice, boolean, timestamptz,
                                  timestamptz, boolean);
