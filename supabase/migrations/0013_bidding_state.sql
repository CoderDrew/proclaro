-- 0013_bidding_state: lets the bidder UI ask the database whether bidding is open, closed or not open, so the
-- screen never decides "closed" from the web server's clock. Same rules as the write functions: closed is
-- `now() >= bid_due_at` on a published solicitation (app.bids_closed); open is app.bidding_open; anything else
-- (unknown id, unpublished, unreleased) is 'not_open' and reveals nothing about which ids exist.
create function public.bidding_state(p_solicitation_id uuid)
returns text
language plpgsql stable security definer
set search_path = ''
as $$
begin
  perform app.require_bidder();
  if app.bids_closed(p_solicitation_id) then
    return 'closed';
  elsif app.bidding_open(p_solicitation_id) then
    return 'open';
  end if;
  return 'not_open';
end;
$$;

revoke all on function public.bidding_state(uuid) from public, anon, authenticated, service_role;
grant execute on function public.bidding_state(uuid) to authenticated;
