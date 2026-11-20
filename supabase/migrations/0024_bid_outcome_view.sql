-- 0024: the bidder's own posted outcome (slice 2b, Task 11).
-- my_bid_outcome: the caller's own bid only (not_found otherwise). It returns no row until a recaps row (recap or
-- memo) exists for the bid's solicitation; then the bid's current app.bid_review_status. Outcomes can change until
-- send-to-check, so nothing is shown before posting.

create function public.my_bid_outcome(p_bid_id uuid)
returns table (status text, reason text)
language plpgsql stable security definer
set search_path = ''
as $$
declare
  v_bid public.bids;
begin
  perform app.require_bidder();
  select b.* into v_bid from public.bids b where b.id = p_bid_id and b.bidder_org_id = app.my_org();
  if not found then
    raise exception 'not_found' using errcode = 'P0001';
  end if;
  if not exists (select 1 from public.recaps r where r.solicitation_id = v_bid.solicitation_id) then
    return;
  end if;
  return query select s.status, s.reason from app.bid_review_status(v_bid.id, now()) s;
end;
$$;

revoke all on function public.my_bid_outcome(uuid) from public, anon, authenticated, service_role;
grant execute on function public.my_bid_outcome(uuid) to authenticated;

