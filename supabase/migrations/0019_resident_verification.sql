-- 0019_resident_verification: office verification of resident certificates (slice 2b, Task 5).
--
-- The recap (Task 8) applies the 5% resident preference only to bids whose resident claim the office verified here.
-- resident_verifications is append-only: the latest row per bid (verified_at, id) is current, so a later row may
-- overturn an earlier one and every decision stays on record. The certificate is copied from the bidder's company row
-- at verification time, so the record shows what was actually checked. Verification happens only in stage bid_review,
-- so it cannot change once the recap is sent to check.

create table public.resident_verifications (
  id              uuid primary key default gen_random_uuid(),
  solicitation_id uuid not null references public.solicitations (id),
  bid_id          uuid not null references public.bids (id),
  certificate     text not null check (btrim(certificate) <> ''),
  verified        boolean not null,
  note            text not null check (btrim(note) <> ''),
  verified_by     uuid not null references public.profiles (user_id),
  verified_at     timestamptz not null default now()
);
create index resident_verifications_bid_idx on public.resident_verifications (bid_id, verified_at desc, id desc);
create index resident_verifications_solicitation_idx on public.resident_verifications (solicitation_id);

create trigger resident_verifications_append_only
  before update or delete on public.resident_verifications for each row execute function app.reject_change();
create trigger resident_verifications_no_truncate
  before truncate on public.resident_verifications for each statement execute function app.reject_change();

revoke all on public.resident_verifications from anon, authenticated, service_role;
alter table public.resident_verifications enable row level security;

-- ---------------------------------------------------------------------------
-- Helpers (schema `app`, no API role executes them)
-- ---------------------------------------------------------------------------

-- The latest verification's verdict for the bid; false when there is none.
create function app.resident_verified(p_bid_id uuid)
returns boolean
language sql stable security definer
set search_path = ''
as $$
  select coalesce(
    (select v.verified from public.resident_verifications v
      where v.bid_id = p_bid_id
      order by v.verified_at desc, v.id desc limit 1),
    false);
$$;

-- The bidder claims residency and the office has recorded no verification row yet.
create function app.resident_unverified(p_bid_id uuid)
returns boolean
language sql stable security definer
set search_path = ''
as $$
  select coalesce(
    (select c.resident_claimed
       from public.bids b
       join public.bidder_companies c on c.org_id = b.bidder_org_id
      where b.id = p_bid_id)
    and not exists (select 1 from public.resident_verifications v where v.bid_id = p_bid_id),
    false);
$$;

revoke all on function app.resident_verified(uuid), app.resident_unverified(uuid)
  from public, anon, authenticated, service_role;

-- ---------------------------------------------------------------------------
-- verify_resident: the office records its finding on a bid's resident claim. Error order:
-- not_authorized -> not_found (no bid, or no opened version) -> sealed (before close) -> invalid_state (stage) ->
-- invalid_state (no claim) -> invalid_data (null verdict) -> reason_required (blank note).
-- ---------------------------------------------------------------------------
create function public.verify_resident(p_bid_id uuid, p_verified boolean, p_note text)
returns uuid
language plpgsql volatile security definer
set search_path = ''
as $$
declare
  v_bid     public.bids;
  v_eval    public.evaluations;
  v_version int;
  v_cert    text;
  v_claimed boolean;
  v_id      uuid;
begin
  perform app.require_office();
  select b.* into v_bid from public.bids b where b.id = p_bid_id;
  if not found then
    raise exception 'not_found' using errcode = 'P0001';
  end if;
  v_eval := app.lock_evaluation(v_bid.solicitation_id);
  v_version := app.latest_version(v_bid.id);
  if v_version is null or app.is_withdrawn(v_bid.id, v_version) then
    raise exception 'not_found' using errcode = 'P0001';
  end if;
  perform app.require_stage(v_eval, 'bid_review');

  select c.resident_claimed, c.resident_certificate into v_claimed, v_cert
    from public.bidder_companies c where c.org_id = v_bid.bidder_org_id;
  if not coalesce(v_claimed, false) then
    raise exception 'invalid_state' using errcode = 'P0001';
  end if;
  if p_verified is null then
    raise exception 'invalid_data' using errcode = 'P0001';
  end if;
  if btrim(coalesce(p_note, '')) = '' then
    raise exception 'reason_required' using errcode = 'P0001';
  end if;

  insert into public.resident_verifications (solicitation_id, bid_id, certificate, verified, note, verified_by, verified_at)
  values (v_bid.solicitation_id, v_bid.id, btrim(v_cert), p_verified, btrim(p_note), auth.uid(), clock_timestamp())
  returning id into v_id;
  perform app.bid_audit(v_bid, 'verify_resident', jsonb_build_object(
    'verified', p_verified, 'certificate', btrim(v_cert), 'note', btrim(p_note)));
  return v_id;
end;
$$;

-- ---------------------------------------------------------------------------
-- resident_claims: the office's list of resident claims to check. One row per opened bid whose bidder claims
-- residency; verified is null until a row exists (then the latest row's verdict, note and time).
-- ---------------------------------------------------------------------------
create function public.resident_claims(p_solicitation_id uuid)
returns table (bid_id uuid, reference text, certificate text, verified boolean, note text, verified_at timestamptz)
language plpgsql volatile security definer
set search_path = ''
as $$
#variable_conflict use_column
begin
  perform app.open_bids_gate(p_solicitation_id);
  return query
    select o.bid_id, o.reference,
           coalesce(lv.certificate, c.resident_certificate),
           lv.verified, lv.note, lv.verified_at
      from public.opened_bids(p_solicitation_id) o
      join public.bidder_companies c on c.org_id = o.bidder_org_id
      left join lateral (
        select v.certificate, v.verified, v.note, v.verified_at
          from public.resident_verifications v
         where v.bid_id = o.bid_id
         order by v.verified_at desc, v.id desc limit 1) lv on true
     where c.resident_claimed
     order by o.reference;
end;
$$;

revoke all on function public.verify_resident(uuid, boolean, text), public.resident_claims(uuid)
  from public, anon, authenticated, service_role;
grant execute on function public.verify_resident(uuid, boolean, text), public.resident_claims(uuid)
  to authenticated;
