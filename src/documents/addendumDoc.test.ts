import { describe, expect, it } from "vitest";
import { dateChanges } from "./addendumDoc";
import { ctxWith } from "./testFixtures";

const TZ = "America/Denver";
const base = ctxWith(200_000_00).data;

describe("dateChanges", () => {
  it("lists nothing when the dates are the same", () => {
    expect(dateChanges(base, { ...base }, TZ)).toEqual([]);
  });

  it("lists each changed key date as the RFB prints it, in settings.timezone", () => {
    const next = {
      ...base,
      questionsDue: { date: "2027-06-16", time: "13:00" },
      answersDue: { date: "2027-06-23", time: "15:30" },
      bidDueDate: "2027-07-08",
      bidDueTime: "14:00",
    };
    expect(dateChanges(base, next, TZ)).toEqual([
      { field: "Questions due", before: "June 15, 2027, 1:00 PM MDT", after: "June 16, 2027, 1:00 PM MDT" },
      { field: "Answers issued by", before: "June 22, 2027, 1:00 PM MDT", after: "June 23, 2027, 3:30 PM MDT" },
      { field: "Bids due", before: "July 1, 2027, 1:00 PM MDT", after: "July 8, 2027, 2:00 PM MDT" },
    ]);
  });

  it("lists a pre-bid meeting that was added or moved", () => {
    const withMeeting = { ...base, preBid: { ...base.preBid, kind: "optional" as const, date: "2027-06-08", time: "10:00" } };
    expect(dateChanges(base, withMeeting, TZ)).toEqual([
      { field: "Pre-bid meeting", before: "No pre-bid meeting", after: "June 8, 2027, 10:00 AM MDT" },
    ]);
    const moved = { ...withMeeting, preBid: { ...withMeeting.preBid, date: "2027-06-09" } };
    expect(dateChanges(withMeeting, moved, TZ)).toEqual([
      { field: "Pre-bid meeting", before: "June 8, 2027, 10:00 AM MDT", after: "June 9, 2027, 10:00 AM MDT" },
    ]);
  });
});
