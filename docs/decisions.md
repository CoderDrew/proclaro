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

## Open questions (pending input from agency contact)

- Notarized packet: deadline, and consequence of late/missing packet
- Actual RFB workflow steps and who performs each
- Award determination rules
- Real bid fields and what makes each fail; disqualifying vs. minor irregularity
