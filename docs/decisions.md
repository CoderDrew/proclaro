# Decision Log

## 2026-11-16 — Initial product decisions

- **Purpose:** Public portfolio project demonstrating product engineering with AI coding agents. Drew acts as product engineer; agents write the code. Runs alongside ContractIQ (the hands-on Python learning project).
- **Fictional agency:** Workflow modeled on a real state agency process, but no real names, branding, bidder data or documents in the repo.
- **v1 scope: RFBs only.** RFPs (weighted scoring, evaluation committees) deferred to phase 2.
- **Sealed bids:** No agency user — and no AI process — can see bid contents before the official close/opening time.
- **Roles:** Bidder, Creator, Reviewer, Approver, Admin. The same person cannot review and approve the same solicitation; enforced by the system.
- **Review flow:** Reviewer checks each bid against requirements; Approver signs off. Bids meeting requirements go forward to award; others are marked non-responsive with a recorded reason. Disagreement sends the bid back to the Reviewer rather than the Approver overriding.
- **AI compliance check is advisory only.** It never rejects a bid. Reviewer confirms or overrides each item; overrides are logged with a reason.
- **Two check types:** Structured fields are checked by deterministic rules (no AI). Uploaded documents are checked by the AI. The checklist shows which method verified each item.
- **AI output:** met / not met / unclear, with evidence (document, page, excerpt). No confidence scores — self-reported model confidence is poorly calibrated and invites over-trust.
- **AI checks compliance, not award.** No scoring, ranking or winner recommendation.
- **Evaluation:** Synthetic bids with planted defects. False "met" rate reported separately from false "not met" — passing a non-compliant bid is the costly error.
- **Demo approach:** Screen-shared walkthroughs, not a self-serve demo mode. AI runs only on agency-triggered actions, which limits cost exposure.
- **Stack (proposed, not final):** TypeScript/Next.js + Supabase — chosen so Drew can read and explain the agent-written code fluently.

## 2026-11-16 — Findings from the real process (source documents and agency contact)

Real reference documents are kept locally in `source-docs/`, which is git-ignored. Only generalized, fictionalized rules go in this repo.

### Evaluation and award

- **Evaluation is a MET / NOT MET checklist** per required bid section. This matches the AI output design.
- **Award goes to the lowest responsible bidder whose bid meets the requirements.** "Responsive" (meets the requirements) and "responsible" (able to do the work) are separate determinations.
- **Price adjustments are applied by deterministic rules, not by the AI:**
  - In-state resident preference: a certified resident bidder wins if their bid is within 5% of the lowest non-resident bid.
  - Apprentice credit: on projects of $1M or more, a bidder committing apprentices to at least 10% of labor hours is evaluated as if the bid were 1% lower.
- **Fallback:** if the winner won't sign the contract or can't provide the performance bond, the second-lowest bidder gets the option; if they decline, the project is re-bid. The ranked list of responsive bids is kept after award.
- **Price conflicts:** the amount in words overrides the figures; unit prices override extended totals.

### Requirements depend on project value

- Thresholds are applied to the **agency's project estimate**, so a solicitation's requirement set is fixed when it is created.
- Value bands: $50K (competitive sealed bidding at or above it), $100K (prevailing wage), $150K (bonds), $1M (apprentice credit). The required bid sections differ by band, so requirements are configured per solicitation instead of being a fixed checklist.

### Bonds

- **Bonds are required only when the project estimate is $150,000 or more.**
- **Bid bond (10% of the bid):** guarantees the winner will sign the contract. Submitted with the bid as an electronic surety bond, or as an original bond or cashier's/certified check delivered on paper (a copy is not accepted). Staff record receipt of a paper original with a timestamp. Forfeited if the winner refuses to sign; returned to the others after award.
- **Cure period for a missing bid bond:** if a required bid bond is not with the bid, the bidder has until **5:00 p.m. the next business day** to provide it. Otherwise the bid is disqualified.
  - During the cure period the item's status is "pending cure, due [timestamp]", not "not met".
  - At the deadline the system disqualifies the bid automatically by rule and logs the reason.
  - "Next business day" skips weekends and state holidays, using a holiday calendar the agency can edit.
  - After close, the bidder can upload only the missing item, and only until the cure deadline.
- **Performance and payment bond (100% of the accepted bid):** guarantees the work is completed and that subcontractors and suppliers are paid. Due within **20 calendar days of the award notice**. If it isn't delivered, the agency may move to the next-lowest responsible bidder.
  - This is the notarized document: the principal and the surety each sign before a notary.
  - It must be increased if change orders raise the contract amount.
  - The workflow therefore continues after award: Awarded → Bond pending → Contract executed.
- **Performance bond checks:**
  - Bond amount ≥ 100% of the accepted bid: deterministic. The AI extracts the amount and a rule compares it.
  - Signatures, notary blocks and matching bond numbers: AI, with evidence.
  - Notary commission not expired at the acknowledgment date: deterministic, from dates the AI extracts.
  - "No alterations to the printed form": human only.
  - Approval as to form by the state's legal office: an agency approval step in the workflow, not a check.

### Hard rejections and workflow events

- **Grounds for hard rejection:** a late or incomplete upload; improper or missing signatures, or numbers that can't be read; modifying contract language; not signing in at a mandatory pre-bid meeting; contacting agency staff outside the allowed channels. Other irregularities can be waived at the agency's discretion.
- **Workflow events to support:**
  - Addenda, which bidders must acknowledge on the bid form (a deterministic check).
  - Substitution requests.
  - Public Q&A that doesn't identify who asked.
  - Bid modification or withdrawal before opening; no withdrawal for 30 days after opening.
  - A subcontractor list due within 24 hours after opening.
  - Bids stay binding for 90 days.
  - A bid tabulation published after opening.
- **v1 targets construction RFBs**, the domain of the reference documents.

## 2026-11-16 — Revisions after auditing a full real procurement package

Details and evidence: `docs/discovery.md`.

- **Roles and review flow are under review.** The real process involves two organizations. A central procurement office decides whether each bid is accepted (responsive), and the requesting agency picks the award from the accepted bids. The single-agency Creator/Reviewer/Approver model above is on hold until the real steps are mapped.
- **No deadline override, for anyone.** In the real example, a project manager was willing to accept a late bid and procurement refused. The system offers no override path.
- **Sealed bids include the bidder.** After submitting, a bidder can't view their submission until close.
- **Bond threshold confirmed: the project estimate, $150,000 or more.** This is set on the solicitation when it's created, not evaluated per bid. The real intake form words the statute as "any bid over $150,000"; Drew confirmed the estimate-based rule for Proclaro.
- **Document checks must work on scanned images.** Most real bids are scans with handwriting and no text layer.
- **Post-award bond package.** The package is:
  - the original performance and payment bond, notarized for both principal and surety, left undated so the agency can date it after the contract is signed;
  - the surety's power of attorney;
  - a notarized certification letter authorizing the person who signed.

  The bidder's name must exactly match the business registration record. A mismatch sends the bond back for correction, not disqualification.
- **The recap lists only accepted bids.** Accepted is a separate state from awarded.
- **v1 ends at award publication.** Everything after award is out of scope for v1: the performance and payment bond, the bond package, legal approval and contract execution. The post-award bond notes above are kept as reference for later. The **bid bond** is submitted with the bid, so checking it at review stays in v1.
- **A bid not on the solicitation's own bid form is non-responsive.** This is confirmed by a real rejection.

## Open questions

See `docs/discovery.md` §3.
