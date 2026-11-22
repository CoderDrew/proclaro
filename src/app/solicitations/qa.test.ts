import { describe, expect, it } from "vitest";
import { addendumHeading, groupAnswers, versionLabel } from "./qa";

describe("groupAnswers", () => {
  it("groups by addendum, ascending, keeping the answer order within a group", () => {
    const g = groupAnswers([
      { addendum_number: 2, published_question: "Q3", answer: "A3" },
      { addendum_number: 1, published_question: "Q1", answer: "A1" },
      { addendum_number: 1, published_question: "Q2", answer: "A2" },
    ]);
    expect(g).toEqual([
      { addendum: 1, items: [{ question: "Q1", answer: "A1" }, { question: "Q2", answer: "A2" }] },
      { addendum: 2, items: [{ question: "Q3", answer: "A3" }] },
    ]);
  });

  it("returns nothing for no answers", () => {
    expect(groupAnswers([])).toEqual([]);
  });

  it("carries no other columns through", () => {
    const g = groupAnswers([{ addendum_number: 1, published_question: "Q", answer: "A", body: "secret" } as never]);
    expect(JSON.stringify(g)).not.toContain("secret");
  });
});

describe("labels", () => {
  it("names a version and marks the current one", () => {
    expect(versionLabel(1, true)).toBe("Version 1 (current)");
    expect(versionLabel(2, false)).toBe("Version 2");
  });
  it("names an addendum heading", () => {
    expect(addendumHeading(3)).toBe("Addendum 3");
  });
});
