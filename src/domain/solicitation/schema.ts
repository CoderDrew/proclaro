import { z } from "zod";
import type { SolicitationData } from "./types";

/** A real calendar date in YYYY-MM-DD form (rejects 2026-02-30, 2026-13-01). */
const localDate = z.string().refine((s) => {
  const m = /^(\d{4})-(\d{2})-(\d{2})$/.exec(s);
  if (!m) return false;
  const [y, mo, d] = [Number(m[1]), Number(m[2]), Number(m[3])];
  const dt = new Date(Date.UTC(y, mo - 1, d));
  return dt.getUTCFullYear() === y && dt.getUTCMonth() === mo - 1 && dt.getUTCDate() === d;
}, "Invalid calendar date");

/** HH:mm, 00:00 to 23:59. */
const localTime = z.string().regex(/^([01]\d|2[0-3]):[0-5]\d$/, "Invalid time");

const contact = z.object({ name: z.string(), email: z.string(), phone: z.string() });
const dateTime = z.object({ date: localDate, time: localTime });
const sectionEnum = z.enum([
  "bid_form_1", "bid_form_2", "signature_page", "insurance",
  "qualifications", "references", "current_work",
]);
const optionalSection = z.enum(["qualifications", "references", "current_work"]);
const fundingSource = z.enum(["capital_construction", "major_maintenance", "other"]);

export const solicitationSchema = z.object({
  shortTitle: z.string(),
  longTitle: z.string(),
  category: z.enum(["construction", "major_maintenance", "capital_construction"]).nullable(),
  summary: z.string(),
  projectDescription: z.string(),
  scopeNotes: z.string(),
  specialProvisions: z.string(),
  location: z.object({ address: z.string(), city: z.string(), county: z.string() }),
  requester: contact,
  projectManager: contact,
  estimateCents: z.number().int().nonnegative().nullable(),
  fundingSource: fundingSource.nullable(),
  fundingOther: z.string(),
  federalFunds: z.boolean().nullable(),
  releaseDate: localDate.nullable(),
  adStart: localDate.nullable(),
  adEnd: localDate.nullable(),
  newspapers: z.string(),
  questionsDue: dateTime.nullable(),
  answersDue: dateTime.nullable(),
  bidDueDate: localDate.nullable(),
  bidDueTime: localTime,
  tentativeAwardDate: localDate.nullable(),
  estimatedStartDate: localDate.nullable(),
  estimatedCompletionDate: localDate.nullable(),
  bidValidityDays: z.number().int().positive(),
  preBid: z.object({
    kind: z.enum(["none", "optional", "mandatory"]),
    format: z.enum(["in_person", "phone", "video"]).nullable(),
    date: localDate.nullable(),
    time: localTime.nullable(),
    location: z.string(),
  }),
  backgroundCheck: z.object({
    required: z.boolean(),
    contact: z.string(),
    leadDays: z.number().int().nonnegative().nullable(),
  }),
  schedule: z.object({
    items: z.array(z.object({ name: z.string(), description: z.string() })),
    alternates: z.array(z.object({ kind: z.enum(["additive", "deductive"]), description: z.string() })),
  }),
  optionalSections: z.array(optionalSection),
  pageLimits: z.partialRecord(sectionEnum, z.number().int().positive()),
  attachments: z.array(z.object({
    kind: z.enum(["plans", "specifications", "sample_contract", "prevailing_wage", "other"]),
    label: z.string(),
    storagePath: z.string(),
    issueDate: localDate.nullable(),
  })),
}) satisfies z.ZodType<SolicitationData>;

const emptyContact = () => ({ name: "", email: "", phone: "" });

export function emptySolicitation(): SolicitationData {
  return {
    shortTitle: "", longTitle: "", category: null,
    summary: "", projectDescription: "", scopeNotes: "", specialProvisions: "",
    location: { address: "", city: "", county: "" },
    requester: emptyContact(), projectManager: emptyContact(),
    estimateCents: null, fundingSource: null, fundingOther: "", federalFunds: null,
    releaseDate: null, adStart: null, adEnd: null, newspapers: "",
    questionsDue: null, answersDue: null,
    bidDueDate: null, bidDueTime: "13:00",
    tentativeAwardDate: null, estimatedStartDate: null, estimatedCompletionDate: null,
    bidValidityDays: 90,
    preBid: { kind: "none", format: null, date: null, time: null, location: "" },
    backgroundCheck: { required: false, contact: "", leadDays: null },
    schedule: { items: [], alternates: [] },
    optionalSections: [],
    pageLimits: {},
    attachments: [],
  };
}

/**
 * Stored `data` merged over the empty defaults, or null when it does not match the schema. Pages and publish use
 * this instead of `parse` so a malformed row shows a clear state instead of throwing.
 */
export function parseStoredData(raw: unknown): SolicitationData | null {
  if (raw === null || typeof raw !== "object" || Array.isArray(raw)) return null;
  const r = solicitationSchema.safeParse({ ...emptySolicitation(), ...raw });
  return r.success ? r.data : null;
}
