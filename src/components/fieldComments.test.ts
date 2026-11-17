import { describe, expect, it } from "vitest";
import { emptySolicitation } from "@/domain/solicitation/schema";
import { sidebarComments } from "./fieldComments";

const c = (field: string | null) => ({ field, body: `on ${field}` });

describe("sidebarComments", () => {
  it("keeps general comments and drops comments shown beside a rendered field", () => {
    const out = sidebarComments([c(null), c("bidDueDate"), c("attachments.plans"), c("schedule.items")], emptySolicitation());
    expect(out.map((x) => x.field)).toEqual([null]);
  });

  it("shows comments on conditionally hidden inputs in the sidebar, and beside them once shown", () => {
    const d = emptySolicitation();
    const hidden = sidebarComments([c("preBid.date"), c("fundingOther"), c("backgroundCheck.leadDays")], d);
    expect(hidden.map((x) => x.field)).toEqual(["preBid.date", "fundingOther", "backgroundCheck.leadDays"]);
    const shown = sidebarComments(
      [c("preBid.date"), c("fundingOther"), c("backgroundCheck.leadDays")],
      { ...d, fundingSource: "other", preBid: { ...d.preBid, kind: "mandatory" }, backgroundCheck: { ...d.backgroundCheck, required: true } },
    );
    expect(shown).toEqual([]);
  });

  it("renders backgroundCheck.contact beside its input (not twice) while the check is required", () => {
    const d = emptySolicitation();
    expect(sidebarComments([c("backgroundCheck.contact")], d).map((x) => x.field)).toEqual(["backgroundCheck.contact"]);
    const shown = sidebarComments([c("backgroundCheck.contact")], { ...d, backgroundCheck: { ...d.backgroundCheck, required: true } });
    expect(shown).toEqual([]);
  });

  it("shows comments on unknown or removed fields in the sidebar", () => {
    const out = sidebarComments([c("schedule.items.3.name"), c("something.else")], emptySolicitation());
    expect(out).toHaveLength(2);
  });
});
