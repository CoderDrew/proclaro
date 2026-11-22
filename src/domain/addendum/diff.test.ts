import { describe, expect, it } from "vitest";
import type { SolicitationData } from "../solicitation/types";
import { describeScheduleChange, diffSchedule, scheduleChanged, type ScheduleChange } from "./diff";

type Schedule = SolicitationData["schedule"];

// The schedule tests.make_published_solicitation uses; addendum_publish.test.sql runs the same six cases through
// app.schedule_changed, and its boolean must equal diffSchedule(...).length > 0.
const base: Schedule = {
  items: [
    { name: "Base bid", description: "Site work" },
    { name: "Item 2", description: "Roofing" },
  ],
  alternates: [{ kind: "deductive", description: "Omit canopy" }],
};

const cases: { name: string; next: Schedule; expected: ScheduleChange[] }[] = [
  { name: "identical", next: structuredClone(base), expected: [] },
  {
    name: "item added at end",
    next: { ...base, items: [...base.items, { name: "Item 3", description: "Paving" }] },
    expected: [{ kind: "item", change: "added", position: 3, after: "Item 3: Paving" }],
  },
  {
    name: "item removed",
    next: { ...base, items: [base.items[0]] },
    expected: [{ kind: "item", change: "removed", position: 2, before: "Item 2: Roofing" }],
  },
  {
    name: "item renamed",
    next: { ...base, items: [base.items[0], { name: "Roof replacement", description: "Roofing" }] },
    expected: [
      { kind: "item", change: "changed", position: 2, before: "Item 2: Roofing", after: "Roof replacement: Roofing" },
    ],
  },
  {
    name: "alternate kind flipped",
    next: { ...base, alternates: [{ kind: "additive", description: "Omit canopy" }] },
    expected: [
      {
        kind: "alternate", change: "changed", position: 1,
        before: "Deductive: Omit canopy", after: "Additive: Omit canopy",
      },
    ],
  },
  {
    name: "two items swapped",
    next: { ...base, items: [base.items[1], base.items[0]] },
    expected: [
      { kind: "item", change: "changed", position: 1, before: "Base bid: Site work", after: "Item 2: Roofing" },
      { kind: "item", change: "changed", position: 2, before: "Item 2: Roofing", after: "Base bid: Site work" },
    ],
  },
];

describe("diffSchedule (parity cases with addendum_publish.test.sql)", () => {
  for (const c of cases) {
    it(c.name, () => {
      expect(diffSchedule(base, c.next)).toEqual(c.expected);
      expect(scheduleChanged(base, c.next)).toBe(c.expected.length > 0);
    });
  }
});

describe("diffSchedule details", () => {
  it("labels an item without a description by its name alone", () => {
    expect(diffSchedule({ items: [], alternates: [] }, { items: [{ name: "Base bid", description: "" }], alternates: [] }))
      .toEqual([{ kind: "item", change: "added", position: 1, after: "Base bid" }]);
  });
  it("counts a description-only change", () => {
    const next = { ...base, items: [{ name: "Base bid", description: "Site work and grading" }, base.items[1]] };
    expect(diffSchedule(base, next)).toEqual([
      {
        kind: "item", change: "changed", position: 1,
        before: "Base bid: Site work", after: "Base bid: Site work and grading",
      },
    ]);
  });
  it("lists items before alternates, each in position order", () => {
    const next: Schedule = { items: [base.items[0]], alternates: [] };
    expect(diffSchedule(base, next).map((c) => [c.kind, c.change, c.position])).toEqual([
      ["item", "removed", 2],
      ["alternate", "removed", 1],
    ]);
  });
});

describe("describeScheduleChange", () => {
  it("words added, removed and changed rows the same everywhere", () => {
    expect(describeScheduleChange({ kind: "item", change: "added", position: 3, after: "Item 3: Paving" }))
      .toBe("Item 3 added: Item 3: Paving");
    expect(describeScheduleChange({ kind: "alternate", change: "removed", position: 1, before: "Deductive: Omit canopy" }))
      .toBe("Alternate 1 removed: Deductive: Omit canopy");
    expect(describeScheduleChange({ kind: "item", change: "changed", position: 2, before: "A", after: "B" }))
      .toBe('Item 2 changed from "A" to "B"');
  });
  it("never prints undefined when a side is missing", () => {
    expect(describeScheduleChange({ kind: "item", change: "added", position: 1 })).toBe("Item 1 added: ");
    expect(describeScheduleChange({ kind: "alternate", change: "changed", position: 1 }))
      .toBe('Alternate 1 changed from "" to ""');
  });
  it("words every change diffSchedule produces", () => {
    const next: Schedule = { items: [{ name: "Base bid", description: "" }], alternates: [] };
    expect(diffSchedule(base, next).map(describeScheduleChange)).toEqual([
      'Item 1 changed from "Base bid: Site work" to "Base bid"',
      "Item 2 removed: Item 2: Roofing",
      "Alternate 1 removed: Deductive: Omit canopy",
    ]);
  });
});
