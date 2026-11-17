-- 0005: administrator writes. Until now every table in this list was read-only to the
-- application roles. Each grant is narrow (named columns) and each policy requires app.is_admin().
-- Clauses stay insert-only (update/delete were revoked from every role in 0001), and (key, version)
-- is the primary key, so two concurrent saves of one key cannot both claim the same version.

grant update (state_name, office_name, timezone, fiscal_year_start_month) on public.settings to authenticated;
grant insert, delete on public.holidays to authenticated;
grant insert (name, kind) on public.organizations to authenticated;
grant update (name) on public.organizations to authenticated;
grant insert (key, version, body, created_by) on public.clauses to authenticated;

create policy settings_admin_update on public.settings for update to authenticated
  using ((select app.is_admin())) with check ((select app.is_admin()));

create policy holidays_admin_insert on public.holidays for insert to authenticated
  with check ((select app.is_admin()));
create policy holidays_admin_delete on public.holidays for delete to authenticated
  using ((select app.is_admin()));

create policy organizations_admin_insert on public.organizations for insert to authenticated
  with check ((select app.is_admin()));
create policy organizations_admin_update on public.organizations for update to authenticated
  using ((select app.is_admin())) with check ((select app.is_admin()));

create policy clauses_admin_insert on public.clauses for insert to authenticated
  with check ((select app.is_admin()) and created_by = (select auth.uid()));
