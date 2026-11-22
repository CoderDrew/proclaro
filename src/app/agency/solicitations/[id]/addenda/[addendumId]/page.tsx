import { notFound } from "next/navigation";
import { parseStoredData } from "@/domain/solicitation/schema";
import { createServerClient } from "@/lib/supabase/server";
import { Notice, Page, PageHeader } from "@/components/ui";
import { requireAgencyPage } from "../../../../guard";
import { AddendumEditor } from "./AddendumEditor";

export const dynamic = "force-dynamic";

const UUID = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;

export default async function AddendumPage({ params }: { params: Promise<{ id: string; addendumId: string }> }) {
  const ctx = await requireAgencyPage();
  const { id, addendumId } = await params;
  if (!UUID.test(id) || !UUID.test(addendumId)) notFound();

  const supabase = await createServerClient();
  // RLS hides other agencies' rows; the explicit agency check is a second line of defense.
  const [solRes, addRes] = await Promise.all([
    supabase.from("solicitations").select("id, agency_id, number, data, published_snapshot").eq("id", id).maybeSingle(),
    supabase.from("addenda").select("id, solicitation_id, number, state, data, narrative").eq("id", addendumId).maybeSingle(),
  ]);
  if (solRes.error) throw new Error(solRes.error.message);
  if (addRes.error) throw new Error(addRes.error.message);
  const sol = solRes.data;
  const add = addRes.data;
  if (!sol || sol.agency_id !== ctx.orgId || !add || add.solicitation_id !== id) notFound();

  const [settings, holidays, comments, list, questions, answers] = await Promise.all([
    supabase.from("settings").select("timezone").eq("id", 1).single(),
    supabase.from("holidays").select("day"),
    supabase.from("addendum_comments").select("field, body, created_at").eq("addendum_id", addendumId)
      .eq("kind", "return").order("created_at", { ascending: false }),
    supabase.rpc("solicitation_addenda", { p_solicitation_id: id }),
    supabase.rpc("agency_questions", { p_solicitation_id: id }),
    supabase.rpc("addendum_answers_draft", { p_addendum_id: addendumId }),
  ]);
  for (const r of [settings, holidays, comments, list, questions, answers]) if (r.error) throw new Error(r.error.message);

  const crumbs = (
    <>
      <a href="/agency">My solicitations</a> / <a href={`/agency/solicitations/${id}`}>{sol.number ?? "Solicitation"}</a>
    </>
  );
  const title = `Addendum ${add.number}`;
  const data = parseStoredData(add.data);
  if (data === null) {
    return (
      <Page width="full">
        <PageHeader crumbs={crumbs} title={title} />
        <Notice tone="error" role="alert">
          This addendum&apos;s saved data could not be read, so it cannot be shown or edited here.
          Contact the procurement office.
        </Notice>
      </Page>
    );
  }

  // The schedule bidders have now: the current published snapshot (falling back to the solicitation's data).
  const snapshot = sol.published_snapshot as { data?: unknown } | null;
  const current = parseStoredData(snapshot?.data) ?? parseStoredData(sol.data);
  // After close an unpublished addendum counts as withdrawn (solicitation_addenda carries the effective state).
  const effective = list.data!.find((a) => a.id === addendumId)?.effective_state ?? add.state;
  const answered = new Set(answers.data!.map((a) => a.question_id));

  return (
    <Page width="full">
      <PageHeader crumbs={crumbs} title={title} />
      <AddendumEditor
        solicitationId={id}
        addendumId={addendumId}
        number={add.number}
        state={effective}
        initial={data}
        narrative={add.narrative}
        baseSchedule={current?.schedule ?? null}
        tz={settings.data!.timezone}
        holidays={holidays.data!.map((h) => h.day)}
        comments={comments.data!.map((c) => ({ field: c.field, body: c.body }))}
        questions={questions.data!
          .filter((q) => q.status === "open" || answered.has(q.id))
          .map((q) => ({ id: q.id, body: q.body, reference: q.reference, askedAt: q.asked_at }))}
        answers={answers.data!.map((a) => ({
          questionId: a.question_id, publishedQuestion: a.published_question, answer: a.answer,
        }))}
      />
    </Page>
  );
}
