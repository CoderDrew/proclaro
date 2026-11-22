-- 0033_solicitation_addenda: the staff list of a solicitation's addenda (slice 2c, Task 9; controller rulings R8/R20).
--
-- app.addendum_effective_state is not callable by API roles, so the agency and office screens read the effective
-- state (after close an unpublished addendum counts as withdrawn) through this definer function instead.
-- Owning agency or office staff only (app.can_see_solicitation); anyone else, or an unknown solicitation, gets
-- not_authorized. published_at is the published_at of the version the addendum produced.

create function public.solicitation_addenda(p_solicitation_id uuid)
returns table (id uuid, number int, state public.addendum_state, effective_state public.addendum_state,
               published_version int, published_at timestamptz)
language plpgsql stable security definer
set search_path = ''
as $$
begin
  if auth.uid() is null or not app.can_see_solicitation(p_solicitation_id) then
    raise exception 'not_authorized' using errcode = 'P0001';
  end if;
  return query
    select a.id, a.number, a.state, app.addendum_effective_state(a), a.published_version, v.published_at
      from public.addenda a
      left join public.solicitation_versions v
        on v.solicitation_id = a.solicitation_id and v.version = a.published_version
     where a.solicitation_id = p_solicitation_id
     order by a.number, a.created_at;
end;
$$;

revoke all on function public.solicitation_addenda(uuid) from public, anon, authenticated, service_role;
grant execute on function public.solicitation_addenda(uuid) to authenticated;
