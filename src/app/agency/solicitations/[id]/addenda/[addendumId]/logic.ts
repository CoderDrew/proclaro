// Pure, server-free logic behind the agency's addendum screens. Kept out of the "use server" file so it can be tested
// with injected deps and so clients can never pass their own `deps` to a server action.
import { lockedFieldChanges } from "@/domain/addendum/lockedFields";
import type { SolicitationData } from "@/domain/solicitation/types";
import { validate, type Issue, type ValidationContext } from "@/domain/solicitation/validate";
import type { SubmitResult } from "../../logic";

export type AddendumResult = { ok: true } | { ok: false; message: string };
export type StartAddendumResult = { ok: true; id: string } | { ok: false; message: string };
/** The form's SubmitResult, or a refusal with plain copy (state, deadline, authorization). */
export type AddendumSubmitResult = SubmitResult | { ok: false; message: string };

/** One answer as the editor holds it: `saved` is false once it is opened or edited and not yet saved. */
export interface AnswerDraft {
  questionId: string;
  /** How the question is named in messages, e.g. "Question 2". */
  label: string;
  publishedQuestion: string;
  answer: string;
  saved: boolean;
}

export const ANSWER_MAX = 4000;
const UUID = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;

const GENERIC = "Something went wrong. Reload the page and try again.";

/** Plain copy for every database error code the addendum functions raise (plus the attachment-path check). */
const CODES: Record<string, string> = {
  addendum_in_progress: "Another addendum is already in progress for this solicitation. Finish or withdraw it first.",
  locked_field: "The release date, advertisement dates, newspapers and category can't change in an addendum.",
  narrative_required: "Describe the changes in this addendum before submitting it.",
  invalid_data: "Some of the entered data was not accepted. Check the fields and try again.",
  bids_closed: "Bids have closed, so addenda can no longer be started, changed or submitted.",
  not_open: "Bidding is not open on this solicitation.",
  invalid_state: "This addendum is no longer a draft, so it can't be changed here. Reload the page.",
  not_authorized: "You are not allowed to do that.",
  reason_required: "Enter a reason.",
  not_found: "That addendum or question was not found. Reload the page.",
  question_not_open: "That question is no longer open, so it can't be answered in this addendum. Reload the page.",
  invalid_attachment_path: "An attachment is not stored with this solicitation. Remove it and upload it again.",
};

function codeOf(e: unknown): string {
  if (e && typeof e === "object" && "message" in e && typeof (e as { message: unknown }).message === "string") {
    return (e as { message: string }).message;
  }
  return "";
}

export function addendumMessageFor(e: unknown): string {
  const code = codeOf(e);
  return Object.hasOwn(CODES, code) ? CODES[code] : GENERIC;
}

/** Mirrors start_addendum's guard: published, bidding still open, and no other addendum in progress. */
export function canStartAddendum(state: string, closed: boolean, inProgress: boolean): boolean {
  return state === "published" && !closed && !inProgress;
}

/** True when some addendum (by effective state, from solicitation_addenda) is neither published nor withdrawn. */
export function addendumInProgress(rows: { effective_state: string }[]): boolean {
  return rows.some((r) => r.effective_state !== "published" && r.effective_state !== "withdrawn");
}

export function narrativeProblems(narrative: string): Issue[] {
  return narrative.trim() === ""
    ? [{ code: "required", field: "narrative", message: "Describe the changes in this addendum." }]
    : [];
}

/** Answers that would not go out as shown: unsaved edits, or a blank published question or answer. */
export function answerDraftProblems(answers: AnswerDraft[]): Issue[] {
  const out: Issue[] = [];
  for (const a of answers) {
    if (!a.saved) {
      out.push({ code: "required", field: `answers.${a.questionId}`, message: `${a.label}: save or remove this answer.` });
      continue;
    }
    if (a.publishedQuestion.trim() === "") {
      out.push({ code: "required", field: `answers.${a.questionId}.publishedQuestion`,
        message: `${a.label}: enter the question as it will be published.` });
    }
    if (a.answer.trim() === "") {
      out.push({ code: "required", field: `answers.${a.questionId}.answer`, message: `${a.label}: enter the answer.` });
    }
  }
  return out;
}

/** The published question and answer, trimmed, 1 to 4,000 characters each (as save_addendum_answer checks). */
export function parseAnswerInput(publishedQuestion: unknown, answer: unknown):
  | { ok: true; value: { publishedQuestion: string; answer: string } }
  | { ok: false; message: string } {
  const q = typeof publishedQuestion === "string" ? publishedQuestion.trim() : "";
  const a = typeof answer === "string" ? answer.trim() : "";
  if (q === "" || q.length > ANSWER_MAX) {
    return { ok: false, message: `Enter the published question (1 to ${ANSWER_MAX.toLocaleString("en-US")} characters).` };
  }
  if (a === "" || a.length > ANSWER_MAX) {
    return { ok: false, message: `Enter the answer (1 to ${ANSWER_MAX.toLocaleString("en-US")} characters).` };
  }
  return { ok: true, value: { publishedQuestion: q, answer: a } };
}

/** Runs one database call and maps its error code to copy. */
export async function runAddendumCall(call: () => Promise<void>): Promise<AddendumResult> {
  try {
    await call();
    return { ok: true };
  } catch (e) {
    return { ok: false, message: addendumMessageFor(e) };
  }
}

export async function runStartAddendum(
  solicitationId: string, deps: { start(solicitationId: string): Promise<string> },
): Promise<StartAddendumResult> {
  if (typeof solicitationId !== "string" || !UUID.test(solicitationId)) {
    return { ok: false, message: addendumMessageFor(new Error("not_found")) };
  }
  try {
    return { ok: true, id: await deps.start(solicitationId) };
  } catch (e) {
    return { ok: false, message: addendumMessageFor(e) };
  }
}

export interface AddendumSubmitDeps {
  /** The stored addendum as the caller sees it (RLS) plus the solicitation's current data, or null when invisible. */
  loadAddendum(id: string): Promise<{ state: string; data: SolicitationData; narrative: string; baseData: SolicitationData } | null>;
  validationContext(): Promise<ValidationContext>;
  /** Calls submit_addendum; throws an error whose message is the database code. */
  submit(id: string): Promise<void>;
}

/**
 * Re-validates from the stored addendum (never client data) in addendum mode, with the narrative and locked fields,
 * then submits. Warnings never block: addenda have no warning acknowledgments, and the office reviews every addendum.
 */
export async function runSubmitAddendum(id: string, deps: AddendumSubmitDeps): Promise<AddendumSubmitResult> {
  const row = await deps.loadAddendum(id);
  if (!row) return { ok: false, message: addendumMessageFor(new Error("not_found")) };
  if (row.state !== "draft") return { ok: false, message: addendumMessageFor(new Error("invalid_state")) };

  const { errors } = validate(row.data, await deps.validationContext());
  const locked: Issue[] = lockedFieldChanges(row.baseData, row.data).map((k) => ({
    code: "locked_field", field: k, message: "This field can't change in an addendum.",
  }));
  const all = [...narrativeProblems(row.narrative), ...locked, ...errors];
  if (all.length > 0) return { ok: false, errors: all, unacknowledged: [] };

  const r = await runAddendumCall(() => deps.submit(id));
  return r.ok ? { ok: true } : r;
}
