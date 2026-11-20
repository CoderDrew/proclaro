# Slice 2b: bid review, bid-bond cure, recap and award

Status: Approved by Drew, 2026-11-19 ("build it"). The items marked *(my call)* are the controller's proposals, made where the conversation stopped. Drew should check them.

## Intent
This slice completes v1: from a closed solicitation to a posted award. It also delivers the case study's headline feature: the recap and the award are computed from the structured portal prices. Nobody retypes a number, which removes the transcription error found in the real package.

## Decided by Drew
- **Order.**
  1. The office reviews every opened bid.
  2. The agency decides each flagged bid (accept or reject).
  3. The recap is built from what remains, gets a second person's check, and is posted.
  4. The agency picks the award.
  5. The award is posted after a second person's check.

  Flagged decisions come before the recap.
- **"Over budget"** is measured against a **funding amount** that the agency enters at solicitation setup. It is frozen at publish, so the ceiling is fixed before any price is seen.
- **Review outcomes, the bond cure, resident verification, the apprentice commitment and flagged-bid decisions** work as played back on 2026-11-19 (see Design §1–§4).

## Carried from earlier decisions
These come from docs/decisions.md.
- **Outcomes:**
  - Accepted.
  - Accepted, flagged for the agency.
  - Non-responsive. Allowed only for: late upload, wrong form, missing signature, or a bid bond still missing after the cure.
- **The cure is the only fix allowed after close.** The deadline is 5 p.m. the next business day, skipping weekends and the holiday calendar.
- **The recap lists only accepted bids, and it is the only public disclosure.**
- **Resident preference:** a certified resident bidder wins if its bid is within 5% of the lowest non-resident bid.
- **Apprentice credit:** on projects of $1M or more, a bidder committing apprentices to at least 10% of labor hours is evaluated as if the bid were 1% lower.
- **Words vs figures:** a mismatch is flagged for a person to decide.
- **The agency picks the award.** The system shows the expected winner and flags a pick that differs. Ties go to the agency.
- **All bids over budget:** an "all bids rejected" outcome, published as a memo.
- **Two-person check** on posting the recap and the award. A one-reviewer fallback is allowed and recorded. The same person can't be both reviewer and checker; this is the same rule as slice 1, enforced in Postgres.
- **v1 ends at award publication.**

## Goals, non-goals, anti-goals
**Goals:** everything above, with every guarantee enforced in Postgres and covered by pgTAP. That covers outcomes, deadlines, the same-person rule, the frozen funding amount, and computed figures.

**Non-goals:**
- Addenda and their acknowledgments (2c).
- The AI document check.
- Everything after award: the performance bond, the contract, the 20-day bond deadline, and the second-lowest fallback.
- The subcontractor list.
- Protests.

**Anti-goals:**
- A recap or award number that someone typed.
- A reviewer overriding the automatic cure disqualification or the late-original rule.
- Showing the agency or the public anything about bids other than through the posted recap.

## Design

### 0. Funding amount (reaches back into setup)
- The solicitation form gets a required **Funding amount** field (integer cents).
- Validation rule: it can't be blank.
- *(My call)* Warn when the funding amount is below the estimate.
- It is part of the published snapshot and frozen like everything else.
- Seeded and already-published solicitations without one: fall back to the estimate. *(My call; the seed only)*

### 1. Office review of each opened bid
- The reviewer sets one outcome per bid, each with a reason. Non-responsive reasons come from a fixed list.
- **"Signed original not received"** (2a's derived rule) is shown as an automatic non-responsive. It can't be changed.
- **Mailed form doesn't match the portal entry:** accepted and flagged, with a note.
- Outcomes can be changed until the recap is sent to check. *(My call)* Every change is audited.

### 2. Bid-bond cure
- If a bond is required and missing at close, the bid shows "pending cure, due [timestamp]". "Missing" means: an electronic choice with no file, or a paper choice with no logged paper original by the due time.
- Until the cure deadline, the bidder can upload only the bond file. The office can log a paper bond's arrival.
- At the deadline a bond that is still missing makes the bid non-responsive automatically, with the reason recorded. This is decided on the database clock, with no override, in the same pattern as 2a's derived rules.
- The recap can't be built while any cure is still pending.

### 3. Resident verification and apprentice commitment
- **Resident verification.** The office marks each claimed resident certificate *verified* or *not verified*, with a note. The preference applies only to verified bidders.
- **Apprentice commitment.** On $1M+ solicitations the bid gets a required yes/no line: "commits apprentices to at least 10% of labor hours".
  - It is sealed with the prices.
  - It is printed on the bid form.
  - It is checked by `bid_draft_problems` and the TypeScript validator (parity).

  This changes 2a's bid tables and screens.

### 4. Flagged bids
- The agency author sees only the flagged bids, with the reviewer's note. They see no other bids and no prices beyond what the flag concerns. *(My call: show that bid's base total, since deciding "words vs figures" needs it.)*
- The author accepts or rejects each one with a reason. A rejected flagged bid is excluded from the recap, and the reason is recorded.

### 5. Recap *(my calls throughout, following the clause text "alternates taken in the order stated on the bid form")*
- **Evaluated price** for each accepted bid is its base total, with the apprentice credit (−1%) applied where it qualifies.
- **Alternates** are taken in the order listed while the running total of the lowest evaluated bid stays within the funding amount. The same set of alternates applies to every bid.
- **Ranking:**
  - Bids are ranked by evaluated price for the chosen base plus alternates.
  - The resident preference is applied as the rule states: a verified resident bidder whose evaluated price is within 5% of the lowest non-resident evaluated price ranks ahead of that non-resident.
  - Exact ties are marked tied.
- **The recap lists:** each accepted bidder, base total, each alternate, the total for the selected set, the resident and apprentice flags, the rank, and the expected winner.
- **Workflow and posting:**
  - The reviewer prepares the recap.
  - A different office user checks and posts it, or the reviewer posts it alone with the fallback recorded.
  - Once posted it is frozen, and the public solicitation page shows it.
- **If every accepted bid's base total exceeds the funding amount:** instead of a recap, the office posts an "All bids rejected" memo (with the two-person check). The solicitation ends there.

### 6. Award
- After the recap is posted, the agency author picks the award from the recap's bids. The expected winner is preselected.
- A pick that differs from the expected winner requires a reason. So does a pick among tied bids.
- The office then posts the award with the two-person check.
- The public page shows the award: the winner, the amount and the selected alternates.
- The solicitation ends in **awarded**.

### 7. States after close *(my call; the builder can refine names)*
1. bid review
2. awaiting agency (flagged)
3. recap check
4. recap posted
5. award pending
6. award check
7. awarded, or all bids rejected

Every transition is a security-definer function: lock, state check, guarded write, one audit row. That is the slice 1 pattern.

## Access rules
- **Bidders:**
  - see their own bid's review outcome and cure status;
  - can upload only the bond during the cure;
  - see the public recap and award.
- **Agency author:** sees only flagged bids before the recap, then the posted recap. Picks the award.
- **Office:** sees everything after close.
- **Public:** sees the posted recap, the award and the "all bids rejected" memo only.

## Left to the builder
- Table and function names.
- How the recap is stored. Freeze it as a snapshot at posting, like the published solicitation.
- Exact copy.
- How each state appears on the existing office, agency and bidder pages, using the design system.
