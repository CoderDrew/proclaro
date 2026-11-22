-- Local development seed. All names are fictional.
-- Password `proclaro-dev` is for the local stack only; never use it anywhere else. The hosted reset
-- (scripts/hosted-reset.mjs) seeds from a temporary copy with DEMO_PASSWORD in its place.

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

  -- 27-0004 (slice 2b): open for 14 days, estimate $1.5M, so a bidder can answer the apprentice commitment. Published
  -- three days ago (its release date), so its slice 2c history below (bids, questions, Addendum 1) comes after it.
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
  values (v_id, v_agency, v_author, 'published', '27-0004', 2027, v_data, 1, now() - interval '3 days', app.today() - 3, v_due,
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

-- Version history (0026): every seeded published solicitation gets its version 1, exactly as the 0026 backfill does
-- for rows published before the migration (db reset runs migrations before this seed).
insert into public.solicitation_versions (solicitation_id, version, snapshot, rfb_path, bid_form_path, bid_due_at,
                                          published_at, published_by)
select s.id, 1, s.published_snapshot, s.rfb_path, s.bid_form_path, s.bid_due_at, coalesce(s.published_at, now()), null
  from public.solicitations s
 where s.state = 'published'
on conflict (solicitation_id, version) do nothing;

-- ---------------------------------------------------------------------------
-- Addenda, acknowledgments and questions (slice 2c). Inserted directly, as publish_addendum and the other definer
-- functions would have written them, and after the version 1 backfill above, since Addendum 1 moves the current
-- pointer. No addendum PDF is uploaded (SQL cannot write file bytes), so the v2 documents show as unavailable.
--   27-0004: Addendum 1, published a day ago, adds Item 3 (version 2, schedule changed). Granite submitted at version
--            1, so its bid needs resubmitting. Ridgeback has a draft priced against version 2 and has not acknowledged
--            Addendum 1. Questions in every status: one answered by Addendum 1, one open, one closed as a duplicate.
--   27-0001: Addendum 1 in draft by the Corrections author, moving the bid due date 7 days later, for walking review
--            and publish.
-- ---------------------------------------------------------------------------
do $$
declare
  v_author    uuid := '20000000-0000-0000-0000-000000000001';  -- Corrections Author (owns 27-0001 and 27-0004)
  v_reviewer1 uuid := '20000000-0000-0000-0000-000000000003';
  v_reviewer2 uuid := '20000000-0000-0000-0000-000000000004';
  v_ridgeback uuid := '20000000-0000-0000-0000-000000000011';
  v_granite   uuid := '20000000-0000-0000-0000-000000000012';
  v_sol       public.solicitations;
  v_data      jsonb;
  v_snapshot  jsonb;
  v_due       timestamptz;
  v_add       uuid := gen_random_uuid();
  v_q1        uuid := gen_random_uuid();
  v_q2        uuid := gen_random_uuid();
  v_q3        uuid := gen_random_uuid();
  v_bid       uuid;
  v_published timestamptz := now() - interval '1 day';
  v_funding   bigint;
  v_base      text;
begin
  -- 27-0004 ------------------------------------------------------------------
  select * into v_sol from public.solicitations s where s.number = '27-0004';
  v_funding := app.funding_cents(v_sol.id);  -- the estimate, as start_addendum copies it into the addendum
  v_base := format('solicitations/%s/v2', v_sol.id);

  -- Granite's bid, submitted at version 1 two days ago (before the addendum), so resubmit is required.
  v_bid := gen_random_uuid();
  insert into public.bids (id, solicitation_id, bidder_org_id, reference, created_by, created_at)
  values (v_bid, v_sol.id, '10000000-0000-0000-0000-000000000012', app.new_bid_reference(), v_granite,
          now() - interval '2 days 2 hours');
  insert into public.bid_versions (bid_id, version, submitted_at, submitted_by, item_cents, alternate_cents,
                                   bid_bond_choice, apprentice_commitment, bidder_legal_name, solicitation_version)
  values (v_bid, 1, now() - interval '2 days', v_granite, array[132000000, 14500000]::bigint[],
          array[3800000]::bigint[], 'paper', true, 'Granite Mesa Contractors', 1);

  -- Questions: Ridgeback's (answered by Addendum 1), Granite's duplicate of it (closed), Granite's open one. Each
  -- ask writes an audit row with no actor, as ask_question does.
  insert into public.questions (id, solicitation_id, asked_by, org_id, body, reference, asked_at) values
    (v_q1, v_sol.id, v_ridgeback, '10000000-0000-0000-0000-000000000011',
     'Does the base bid include the grease interceptor shown on the plumbing sheets?', 'Plumbing sheets',
     now() - interval '2 days 4 hours'),
    (v_q3, v_sol.id, v_granite, '10000000-0000-0000-0000-000000000012',
     'Is the grease interceptor part of the base bid or priced separately?', '',
     now() - interval '2 days 3 hours'),
    (v_q2, v_sol.id, v_granite, '10000000-0000-0000-0000-000000000012',
     'Can the existing walk-in cooler stay in service until the replacement is delivered?', 'Alternate 1',
     now() - interval '6 hours');
  insert into public.audit_log (solicitation_id, actor_id, action, detail, created_at) values
    (v_sol.id, null, 'ask_question', jsonb_build_object('question_id', v_q1), now() - interval '2 days 4 hours'),
    (v_sol.id, null, 'ask_question', jsonb_build_object('question_id', v_q3), now() - interval '2 days 3 hours'),
    (v_sol.id, null, 'ask_question', jsonb_build_object('question_id', v_q2), now() - interval '6 hours');

  update public.questions q
     set status = 'closed', close_reason = 'duplicate', closed_by = v_reviewer1,
         closed_at = now() - interval '2 days 1 hour'
   where q.id = v_q3;
  insert into public.audit_log (solicitation_id, actor_id, action, detail, created_at)
  values (v_sol.id, v_reviewer1, 'close_question', jsonb_build_object('question_id', v_q3, 'reason', 'duplicate'),
          now() - interval '2 days 1 hour');

  -- Addendum 1 adds Item 3 (the interceptor). Only the schedule changes; the bid due time stays.
  v_data := jsonb_set(v_sol.data, '{schedule,items}', (v_sol.data -> 'schedule' -> 'items')
              || jsonb_build_array(jsonb_build_object('name', 'Item 3', 'description', 'Grease interceptor')));
  v_due := app.bid_due_at(v_data);
  insert into public.addenda (id, solicitation_id, number, state, data, narrative, created_by, created_at,
                              latest_submitted_at, reviewer_id, checker_id, single_reviewer, published_version)
  values (v_add, v_sol.id, 1, 'published', v_data || jsonb_build_object('fundingAmountCents', v_funding),
          'Adds Item 3, the grease interceptor, to the bid schedule and answers a question about it.',
          v_author, now() - interval '2 days', now() - interval '1 day 6 hours', v_reviewer1, v_reviewer2, false, 2);
  insert into public.addendum_answers (addendum_id, question_id, published_question, answer)
  values (v_add, v_q1, 'Is the grease interceptor shown on the plumbing sheets part of the base bid?',
          'No. This addendum adds it to the bid schedule as Item 3, priced separately.');
  insert into public.audit_log (solicitation_id, actor_id, action, detail, created_at) values
    (v_sol.id, v_author, 'start_addendum', jsonb_build_object('addendum_id', v_add, 'number', 1, 'to', 'draft'),
     now() - interval '2 days'),
    (v_sol.id, v_author, 'save_addendum_answer',
     jsonb_build_object('addendum_id', v_add, 'number', 1, 'question_id', v_q1), now() - interval '1 day 7 hours'),
    (v_sol.id, v_author, 'submit_addendum',
     jsonb_build_object('addendum_id', v_add, 'number', 1, 'from', 'draft', 'to', 'submitted'),
     now() - interval '1 day 6 hours'),
    (v_sol.id, v_reviewer1, 'start_addendum_review',
     jsonb_build_object('addendum_id', v_add, 'number', 1, 'from', 'submitted', 'to', 'in_review',
                        'reviewer_id', v_reviewer1), now() - interval '1 day 5 hours'),
    (v_sol.id, v_reviewer1, 'send_addendum_to_check',
     jsonb_build_object('addendum_id', v_add, 'number', 1, 'from', 'in_review', 'to', 'in_check'),
     now() - interval '1 day 4 hours'),
    (v_sol.id, v_reviewer2, 'approve_addendum_check',
     jsonb_build_object('addendum_id', v_add, 'number', 1, 'from', 'in_check', 'to', 'approved',
                        'checker_id', v_reviewer2), now() - interval '1 day 2 hours');

  -- Publish, as publish_addendum steps 10 to 14 write it: version 2 with the v2 paths, the funding frozen for version
  -- 2, the pointer moved under the freeze exception, the answered question marked, and the audit row.
  v_snapshot := jsonb_build_object('data', v_data, 'clauses', v_sol.published_snapshot -> 'clauses',
                                   'settings', v_sol.published_snapshot -> 'settings', 'renderedAt', v_published);
  insert into public.solicitation_versions (solicitation_id, version, snapshot, rfb_path, bid_form_path,
                                            addendum_path, bid_due_at, published_at, published_by, schedule_changed)
  values (v_sol.id, 2, v_snapshot, v_base || '/rfb.pdf', v_base || '/bid-form.pdf', v_base || '/addendum.pdf',
          v_due, v_published, v_reviewer2, true);
  insert into public.solicitation_funding_changes (solicitation_id, version, funding_cents, frozen_at)
  values (v_sol.id, 2, v_funding, v_published);
  perform set_config('app.publishing_addendum', v_sol.id::text, true);
  update public.solicitations s
     set version = 2, published_snapshot = v_snapshot, data = v_data, bid_due_at = v_due,
         rfb_path = v_base || '/rfb.pdf', bid_form_path = v_base || '/bid-form.pdf'
   where s.id = v_sol.id;
  perform set_config('app.publishing_addendum', '', true);
  update public.questions q set status = 'answered', answered_in = v_add where q.id = v_q1;
  insert into public.audit_log (solicitation_id, actor_id, action, detail, created_at)
  values (v_sol.id, v_reviewer2, 'publish_addendum', jsonb_build_object(
            'addendum_id', v_add, 'number', 1, 'from', 'approved', 'to', 'published', 'version', 2,
            'schedule_changed', true, 'bid_due_at', v_due, 'after_answers_due', false,
            'rfb_path', v_base || '/rfb.pdf', 'bid_form_path', v_base || '/bid-form.pdf',
            'addendum_path', v_base || '/addendum.pdf', 'funding_cents', v_funding),
          v_published);

  -- Ridgeback's draft, started after the addendum, so it is priced against version 2 (three items). It has not
  -- acknowledged Addendum 1.
  v_bid := gen_random_uuid();
  insert into public.bids (id, solicitation_id, bidder_org_id, reference, created_by, created_at)
  values (v_bid, v_sol.id, '10000000-0000-0000-0000-000000000011', app.new_bid_reference(), v_ridgeback,
          now() - interval '12 hours');
  insert into public.bid_drafts (bid_id, version, item_cents, alternate_cents, bid_bond_choice, apprentice_commitment,
                                 solicitation_version, updated_at)
  values (v_bid, 1, array[129500000, 15000000, 2400000]::bigint[], array[3600000]::bigint[], 'paper', false, 2,
          now() - interval '11 hours');

  -- 27-0001 ------------------------------------------------------------------
  -- Addendum 1 in draft: the bid due date 7 days later (well past the 5-day rule), with a narrative.
  select * into v_sol from public.solicitations s where s.number = '27-0001';
  v_add := gen_random_uuid();
  insert into public.addenda (id, solicitation_id, number, state, data, narrative, created_by, created_at)
  values (v_add, v_sol.id, 1, 'draft',
          v_sol.data || jsonb_build_object(
            'bidDueDate', to_char((v_sol.data ->> 'bidDueDate')::date + 7, 'YYYY-MM-DD'),
            'fundingAmountCents', app.funding_cents(v_sol.id)),
          'Moves the bid due date one week later to allow time for a second site visit.',
          v_author, now() - interval '2 hours');
  insert into public.audit_log (solicitation_id, actor_id, action, detail, created_at)
  values (v_sol.id, v_author, 'start_addendum', jsonb_build_object('addendum_id', v_add, 'number', 1, 'to', 'draft'),
          now() - interval '2 hours');
end;
$$;

-- ---------------------------------------------------------------------------
-- Slice 3: the AI document check on 27-0003, with recorded results (no live AI call).
--   Each of the four bids gets an uploaded insurance certificate, a scan of its signed original and (where its paper
--   bond was logged) a scan of the bond, plus one recorded check run whose items match fixtures/aicheck/manifest.json.
--   Planted findings: Granite's insurance ends before the due date; Juniper's amount in words differs from its total;
--   Basalt lists an addendum 27-0003 doesn't have. Basalt's bond was never logged (it is pending cure), so its bond
--   scan reads "Scan not attached".
--   SQL can't upload file bytes: `npm run seed:files` uploads the fixture PDFs to these paths after `db:reset`. The
--   insurance rows carry each fixture's real size and MD5 eTag (pinned by a test), so the upload doesn't trip the
--   opening's tamper check. Without the upload, the recorded results still show and the document links say so.
-- ---------------------------------------------------------------------------
do $$
declare
  v_sol      public.solicitations;
  v_reviewer uuid := '20000000-0000-0000-0000-000000000003';
  v_bid      uuid;
  v_ver      uuid;
  v_entry    uuid;
  v_bond     uuid;
  v_obj      uuid;
  v_run      uuid;
  v_path     text;
  v_scan     text;
  v_bond_scan text;
  v_at       timestamptz;
  b          record;
begin
  select * into v_sol from public.solicitations s where s.number = '27-0003';
  v_at := v_sol.bid_due_at + interval '46 minutes';
  for b in
    select * from (values
      ('ridgeback', '10000000-0000-0000-0000-000000000011'::uuid, 37542, 'b732b6dcd92f1f92719af048218ed154',
       'Ridgeback Builders LLC', 'One Million Two Hundred Thousand and 00/100 Dollars', 'None', 'CR-0042',
       'Ridgeback Builders, L.L.C.', '01/01/2026 to 12/31/2027', 'met', null::text,
       'met', 'met', null::text),
      ('granite', '10000000-0000-0000-0000-000000000012'::uuid, 37725, '2f2d6b8b59591caafda25f61555d84af',
       'Granite Mesa Contractors', 'One Million One Hundred Eighty Thousand Dollars and 00/100', 'None', null,
       'Granite Mesa Contractors', '07/01/2025 to 06/30/2026', 'not_met', 'Coverage is not in force on the bid due date.',
       'met', 'met', null),
      ('juniper', '10000000-0000-0000-0000-000000000013'::uuid, 37052, '46d2f3dddae9033cc73277bc13fd96bc',
       'Juniper Flats Paving', 'One Million One Hundred Fifty-Seven Thousand Five Hundred Dollars', 'None', null,
       'Juniper Flats Paving', '2026-03-01 to 2027-03-01', 'met', null,
       'not_met', 'met', 'The amount in words differs from the portal total.'),
      ('basalt', '10000000-0000-0000-0000-000000000014'::uuid, 37245, '5c5839fe23b49396d0a598b441e29bec',
       'Basalt Creek Builders', 'One Million One Hundred Ninety Thousand Dollars', '1', null,
       'Basalt Creek Builders', '2026-01-15 to 2027-01-15', 'met', null,
       'met', 'not_met', 'The addenda listed differ from the published addenda.')
    ) as t(key, org, ins_size, ins_md5, legal, words, addenda, cert, insured, coverage, coverage_result, coverage_detail,
           amount_result, addenda_result, form_detail)
  loop
    select bb.id into v_bid from public.bids bb where bb.solicitation_id = v_sol.id and bb.bidder_org_id = b.org;
    select v.id into v_ver from public.bid_versions v where v.bid_id = v_bid and v.version = 1;
    select l.id into v_entry from public.bid_original_log l where l.bid_id = v_bid and l.item = 'signed_form';
    v_bond := null;
    select l.id into v_bond from public.bid_original_log l where l.bid_id = v_bid and l.item = 'bid_bond';

    -- The uploaded insurance certificate (an object row with the fixture's real size and eTag).
    v_path := format('bids/%s/%s/seed-%s-insurance.pdf', v_bid, gen_random_uuid(), b.key);
    insert into storage.objects (bucket_id, name, metadata)
    values ('bid-files', v_path, jsonb_build_object('size', b.ins_size, 'eTag', format('"%s"', b.ins_md5),
                                                     'mimetype', 'application/pdf'))
    returning id into v_obj;
    insert into public.bid_version_files (version_id, slot, path, file_name, object_id, object_size, object_etag)
    values (v_ver, 'insurance', v_path, 'insurance.pdf', v_obj, b.ins_size, format('"%s"', b.ins_md5));

    -- Scans of the signed original and, where logged, the paper bond (attached half an hour after close).
    v_scan := format('bids/%s/%s/scan-seed-%s-signed-form.pdf', v_bid, v_entry, b.key);
    insert into storage.objects (bucket_id, name, metadata)
    values ('bid-files', v_scan, '{"size": 120000, "mimetype": "application/pdf"}');
    insert into public.bid_original_scans (log_entry_id, bid_id, path, attached_by, attached_at)
    values (v_entry, v_bid, v_scan, v_reviewer, v_sol.bid_due_at + interval '30 minutes');
    v_bond_scan := null;
    if v_bond is not null then
      v_bond_scan := format('bids/%s/%s/scan-seed-%s-bond.pdf', v_bid, v_bond, b.key);
      insert into storage.objects (bucket_id, name, metadata)
      values ('bid-files', v_bond_scan, '{"size": 40000, "mimetype": "application/pdf"}');
      insert into public.bid_original_scans (log_entry_id, bid_id, path, attached_by, attached_at)
      values (v_bond, v_bid, v_bond_scan, v_reviewer, v_sol.bid_due_at + interval '31 minutes');
    end if;

    -- The recorded run.
    insert into public.ai_check_runs (bid_id, started_by, started_at, finished_at, status, model, bid_version,
                                      solicitation_version, recorded)
    values (v_bid, null, v_sol.bid_due_at + interval '45 minutes', v_at, 'done', 'recorded', 1, 1, true)
    returning id into v_run;

    insert into public.ai_check_items (run_id, document_kind, document_path, item_code, method, result, page, excerpt,
                                       extracted, detail, created_at)
    select v_run, x.kind, x.path, x.code, x.method, x.result, x.page, x.excerpt, x.extracted, x.detail, v_at
      from (values
        ('signed_form', v_scan, 'signature_present', 'ai', 'met', 3, 'Signature: [signed]', null::text, null::text),
        ('signed_form', v_scan, 'amount_in_words', 'rule', b.amount_result, 1, b.words, b.words,
           case when b.amount_result = 'not_met' then b.form_detail end),
        ('signed_form', v_scan, 'addenda_listed', 'rule', b.addenda_result, 2,
           'Addenda acknowledged (list numbers): ' || b.addenda, b.addenda,
           case when b.addenda_result = 'not_met' then b.form_detail end),
        ('signed_form', v_scan, 'form_version', 'rule', 'met', 1, 'Solicitation 27-0003 · Version 1 · Page 1 of 3',
           'Version 1', null),
        ('insurance', v_path, 'insured_name', 'rule', 'met', 1, 'Insured: ' || b.insured, b.insured, null),
        ('insurance', v_path, 'coverage_dates', 'rule', b.coverage_result, 1,
           'Commercial general liability, CGL-55120, ' || b.coverage, b.coverage, b.coverage_detail)
      ) as x(kind, path, code, method, result, page, excerpt, extracted, detail);

    if b.cert is not null then
      insert into public.ai_check_items (run_id, document_kind, document_path, item_code, method, result, page, excerpt,
                                         extracted, created_at)
      values (v_run, 'signed_form', v_scan, 'resident_certificate', 'rule', 'met', 2,
              'Resident bidder certificate number (if claimed): ' || b.cert, b.cert, v_at);
    end if;

    if v_bond_scan is not null then
      insert into public.ai_check_items (run_id, document_kind, document_path, item_code, method, result, page, excerpt,
                                         extracted, created_at)
      select v_run, 'bid_bond_scan', v_bond_scan, x.code, x.method, 'met', 1, x.excerpt, x.extracted, v_at
        from (values
          ('principal_name', 'rule', 'Know all persons by these presents that ' || b.legal || ', as Principal', b.legal),
          ('obligee', 'rule', 'unto State of Calder, Calder Department of Corrections, as Obligee',
             'State of Calder, Calder Department of Corrections'),
          ('surety_signature', 'ai', 'Surety (attorney-in-fact) signature: [signed]', null)
        ) as x(code, method, excerpt, extracted);
    else
      insert into public.ai_check_items (run_id, document_kind, document_path, item_code, method, result, detail,
                                         created_at)
      select v_run, 'bid_bond_scan', null, c, case when c = 'surety_signature' then 'ai' else 'rule' end, 'unclear',
             'Scan not attached', v_at
        from unnest(array['principal_name', 'obligee', 'surety_signature']) c;
    end if;
  end loop;
end;
$$;
