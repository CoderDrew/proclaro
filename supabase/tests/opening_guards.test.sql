-- 0035: opening and evaluation wait for an in-flight addendum publish. Two sessions can't be driven from pgTAP, so
-- this pins the order in each body: FOR SHARE on the solicitation row comes before the bids_closed judgement, which
-- is what makes a waiting caller re-read the committed bid_due_at (behaviour reasoned in the 0035 header).
begin;
select plan(4);

select ok((select position('for share' in lower(p.prosrc)) between 1 and position('bids_closed' in p.prosrc)
             from pg_proc p where p.oid = 'app.open_bids_gate(uuid)'::regprocedure),
  'open_bids_gate locks the solicitation row before judging bids closed');
select ok((select position('for share' in lower(p.prosrc)) between 1 and position('bids_closed' in p.prosrc)
             from pg_proc p where p.oid = 'app.lock_evaluation(uuid)'::regprocedure),
  'lock_evaluation locks the solicitation row before judging bids closed');
select ok((select p.prosrc like '%from public.solicitations s where s.id = p_solicitation_id for share%'
             from pg_proc p where p.oid = 'app.open_bids_gate(uuid)'::regprocedure),
  'the open_bids_gate lock targets the solicitation row');
select ok(not has_function_privilege('authenticated', 'app.lock_evaluation(uuid)', 'execute')
          and not has_function_privilege('authenticated', 'app.open_bids_gate(uuid)', 'execute'),
  'the gate helpers stay uncallable through the API');

select * from finish();
rollback;
