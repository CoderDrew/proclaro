import { readFileSync } from "node:fs";
import { join } from "node:path";
import { describe, expect, it } from "vitest";
import { ackNote, missingAcknowledgments } from "./ack";

describe("ackNote", () => {
  it("lists the missing numbers comma-space separated", () => {
    expect(ackNote([1, 3])).toBe("Did not acknowledge Addendum 1, 3.");
  });

  it("names a single addendum", () => {
    expect(ackNote([2])).toBe("Did not acknowledge Addendum 2.");
  });

  it("uses the same text as app.ack_note in 0031_acknowledgments.sql", () => {
    const sql = readFileSync(join(process.cwd(), "supabase/migrations/0031_acknowledgments.sql"), "utf8");
    expect(sql).toContain("'Did not acknowledge Addendum ' || array_to_string(p_missing, ', ') || '.'");
  });
});

describe("missingAcknowledgments", () => {
  it("returns the published numbers without an acknowledgment", () => {
    expect(missingAcknowledgments([1, 2, 3], [2])).toEqual([1, 3]);
  });

  it("is empty when every addendum is acknowledged", () => {
    expect(missingAcknowledgments([1, 2], [2, 1])).toEqual([]);
  });

  it("returns the numbers ascending", () => {
    expect(missingAcknowledgments([3, 1, 2], [])).toEqual([1, 2, 3]);
  });
});
