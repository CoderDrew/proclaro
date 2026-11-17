-- Publish hardening.
--   (a) Office may delete `published` objects whose solicitation is not yet published, so a failed publish can
--       clean up the files it uploaded. Once published, the files are frozen like the row.
--   (b) publish_solicitation rejects blank paths, snapshot and due date with invalid_data (everything else is
--       unchanged from 0002).

create function app.can_delete_unpublished_file(p_name text)
returns boolean
language sql stable security definer
set search_path = ''
as $$
  select app.is_office() and exists (
    select 1 from public.solicitations s
    where s.id = app.path_solicitation_id(p_name)
      and s.state <> 'published'
  );
$$;

revoke all on function app.can_delete_unpublished_file(text) from public;
grant execute on function app.can_delete_unpublished_file(text) to anon, authenticated, service_role;

create policy published_delete on storage.objects for delete to authenticated
  using (bucket_id = 'published' and app.can_delete_unpublished_file(name));

create or replace function public.publish_solicitation(
  p_id uuid,
  p_rfb_path text,
  p_bid_form_path text,
  p_snapshot jsonb,
  p_bid_due_at timestamptz)
returns void
language plpgsql security definer
set search_path = ''
as $$
declare
  v_row     public.solicitations;
  v_release date;
begin
  perform app.require_office();
  v_row := app.lock_solicitation(p_id);
  perform app.require_state(v_row, 'approved');
  if auth.uid() is distinct from v_row.reviewer_id and auth.uid() is distinct from v_row.checker_id then
    raise exception 'not_authorized' using errcode = 'P0001';
  end if;

  if p_rfb_path is null or btrim(p_rfb_path) = ''
     or p_bid_form_path is null or btrim(p_bid_form_path) = ''
     or p_snapshot is null or p_snapshot in ('null'::jsonb, '{}'::jsonb)
     or p_bid_due_at is null then
    raise exception 'invalid_data' using errcode = 'P0001';
  end if;

  begin
    v_release := (v_row.data ->> 'releaseDate')::date;
  exception when others then
    v_release := null;
  end;
  if v_release is null or v_release < app.today() then
    raise exception 'invalid_release_date' using errcode = 'P0001';
  end if;

  update public.solicitations s
     set state = 'published',
         version = 1,
         published_at = now(),
         release_date = v_release,
         rfb_path = p_rfb_path,
         bid_form_path = p_bid_form_path,
         published_snapshot = p_snapshot,
         bid_due_at = p_bid_due_at
   where s.id = p_id and s.state = 'approved';
  if not found then
    raise exception 'invalid_state' using errcode = 'P0001';
  end if;

  perform app.audit(p_id, 'publish_solicitation', jsonb_build_object(
    'from', 'approved', 'to', 'published', 'version', 1,
    'release_date', v_release, 'bid_due_at', p_bid_due_at,
    'rfb_path', p_rfb_path, 'bid_form_path', p_bid_form_path));
end;
$$;
