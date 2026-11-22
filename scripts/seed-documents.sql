-- Read by scripts/seed-documents.live.test.ts through `supabase db query --read-only` (as the database owner, since the
-- API roles have no grant on these tables). One row per published solicitation version, in version order.
select v.solicitation_id,
       v.version,
       v.snapshot,
       v.rfb_path,
       v.bid_form_path,
       v.addendum_path,
       v.published_at,
       s.number,
       o.name as agency_name,
       (select st.timezone from public.settings st where st.id = 1) as timezone,
       a.number as addendum_number,
       a.narrative as addendum_narrative,
       coalesce((select jsonb_agg(jsonb_build_object('publishedQuestion', x.published_question, 'answer', x.answer)
                                  order by q.asked_at, q.id)
                   from public.addendum_answers x
                   join public.questions q on q.id = x.question_id
                  where x.addendum_id = a.id), '[]'::jsonb) as answers
  from public.solicitation_versions v
  join public.solicitations s on s.id = v.solicitation_id
  join public.organizations o on o.id = s.agency_id
  left join public.addenda a on v.addendum_path is not null
                            and a.solicitation_id = v.solicitation_id and a.number = v.version - 1
 order by v.solicitation_id, v.version;
