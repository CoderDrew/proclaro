# Discovery: How the Real Process Works

Findings from a procurement contact and one complete, real construction RFB package, covering everything from the bid number request to the bond. The real documents are kept locally and are not in this repo. Everything here is generalized: no agency, bidder, person or project names.

The document has three parts, kept separate on purpose:

- **Observed:** seen in the documents or stated by the contact.
- **Proposed:** product ideas. Nothing here is decided until it's in `decisions.md`.
- **Open:** still needs an answer.

---

## 1. Observed

### 1.1 Who does what

Two organizations are involved, not one agency with internal roles:

| Party | Observed responsibilities |
|---|---|
| **Requesting agency** (the agency that owns the project; in the example it was the central construction department itself, acting as owner) | Requests a bid number; supplies plans, the project manual and specifications; its project manager and engineer write addenda; picks the award from the accepted bids; signs the letter of intent to award |
| **Central procurement office** | Assigns the bid number; publishes the solicitation and addenda on the bidding platform; places newspaper ads; downloads bids at close; checks each bid for responsiveness; builds and publishes the recap; publishes the award; collects the original performance bond; closes and archives the solicitation; tracks every solicitation in a spreadsheet |
| **Bidder** | Registers on the platform (activation takes about a day); submits the bid before the deadline; after award, delivers the bond package |
| **Others** | The surety company and notaries (bond package); the state's legal office (approves the bond as to form); labor and revenue agencies (copied on the award letter) |

The deadline is enforced with no exceptions. In the example, the requesting agency's project manager was willing to accept a bid from someone whose platform account wasn't active at the deadline. The procurement office refused because all bids must be submitted on the platform by the deadline.

### 1.2 Lifecycle

1. **Bid number request.** The requesting agency fills in an online intake form (fields in 1.3). The procurement office assigns a number. A "bid timeline calculator" helps with the minimum gaps between dates.
2. **Solicitation preparation.** A Word RFB built from the office's template, plus plans (a large PDF), a project manual, prevailing wage rates, a sample contract and a contractor's affidavit form.
3. **Publication.** The solicitation is posted on the platform and advertised in newspapers for two weeks.
4. **Q&A and addenda.** In the example there were three addenda. They moved the bid date by two weeks, reopened the Q&A window, revised drawings, added bid items and approved product substitutions. Bidders must acknowledge every addendum by number on the bid form.
5. **Close.** At 1:00 p.m. on the due date, uploads lock. No one, including the bidder, can see a submitted bid before close.
6. **Responsiveness review.** Staff download every bid as one ZIP, match up any bonds uploaded separately, check each bid, and type every line-item price into an Excel recap.
7. **Recap.** A spreadsheet listing *only accepted bids*. It goes to the requesting agency along with PDFs of the bids, and is posted publicly as a PDF. Accepted doesn't mean awarded.
8. **Award selection.** The requesting agency chooses the lowest responsible bid after the residency preference is applied, and issues a *conditional* letter of intent to award. It's conditional on negotiating the contract and can be cancelled before the contract is signed.
9. **Award publication.** Staff reopen the recap, bold the winner and mark it "AWARDED", rename it from RECAP to AWARD, export a PDF and post it.
10. **Post-award package.** Bond, certification letter, insurance and certificates (see 1.6). The contract is issued by a separate contracts person.
11. **Close-out.** The solicitation is closed on the platform and the files are moved to a "closed" folder in a shared drive.

The tracker records outcomes besides "awarded": not awarded because the bids were over budget, followed by direct negotiation; solicitation retracted because no firms attended the mandatory pre-proposal meeting; a bidder withdrew; best-and-final-offer and funding holds. It also covers more solicitation types than RFBs: RFQ, RFP, design-build RFP and emergency/direct (BEA) procurements.

### 1.3 Data fields observed

**Bid number request (intake)**

- Requester name, email and phone; agency name and number
- Short title (up to 30 characters) and long title
- Type: Construction, Major Maintenance, Capital Construction, A&E professional services, RFP, RFQ, or other
- One- or two-sentence summary
- Dates:
  - Requested release date (the office must receive the bid at least 3 days before)
  - Advertisement dates (a two-week period)
  - Questions due
  - Answers/addenda due
  - Bid due (at least 5 days after answers/addenda are due)
- Pre-bid meeting (no / yes / mandatory) and its date
- Bid bond required (a discretionary choice for $50,000–$149,999) and performance and payment bond required
- Estimated cost ("an amount the bid should not go over")
- Funding source; federal funds yes/no (which triggers the federal domestic-content clauses)
- Supporting documents

**Bid form, section 1: price schedule**

- A line item per building or part of the work, each as a figure **and** in words, plus a total in figures and words.
- Residency: yes/no plus a resident certificate number.
- Apprentice commitment (only if the estimate is $1M or more).
- Date.

**Bid form, section 2, and signature page**

- Addenda acknowledged by number.
- Bidder name, mailing and billing addresses, email, phone and federal tax ID.
- Name of the signer, with a signature.
- The person who will sign the contract.
- Legal structure (LLC, corporation, etc.).
- People authorized to sign.
- A sworn verification signed "under penalty of perjury" (not notarized).

**Attachments**

- Qualifications: years in business; key personnel with licenses or experience.
- Current work: a projects-in-progress table.
- References.
- Proof of insurance.
- Resident contractor certificate, which has an **expiration date**.
- Bid bond.

**Recap/award spreadsheet**

- One column per accepted bidder.
- Rows: resident yes/no; addenda acknowledged; bid bond yes/no; each line item; total base bid; "+5% preference" (added to *non-resident* totals); adjusted total.

**Tracker (one row per solicitation)**

- Number, type, agency, project and project manager.
- Dates: bid opening, ad dates, pre-bid meeting, sign-in sheet received, questions due, answers due, addenda posted.
- Newspaper/order number and invoice sent to the agency.
- Bids received, contractor awarded, award amount, bonding yes/no.
- Free-text notes on award and bond status.

### 1.4 Evidence of the pain points

- **Transcription error in a published document.** On the winning bid form, the figures, the words and the arithmetic all agreed. When staff typed it into the recap, one line item was entered $3 too high, so the published recap and award both showed the wrong total. The letter of intent and the bond used the correct amount. A typing error made it into two public documents.
- **Inconsistent solicitation documents.** Two addenda revise the bid due date in their header while their body says "the bid opening time and date will not be modified by this addendum". The Q&A answer date in an addendum differs from the one on the intake form.
- **Most bids are scanned images.** Of the eight accepted bids, several have no text layer at all, and the winning bid is a scan with handwritten checkmarks and signatures. Any automated document check needs vision/OCR; plain text extraction isn't enough.
- **Bidders upload only the pages they filled in** (the winning bid was 9 pages of a 24-page RFB), and in no consistent order.

### 1.5 Rules observed

- **Deadline:** an upload that isn't complete when the platform locks is non-responsive. No exceptions.
- **Rejection grounds named by the contact:** a missing required signature; an invalid amount written in words; certain failures to acknowledge addenda. The addendum text says failing to acknowledge "may subject" a bidder to disqualification, so it's discretionary.
- **Residency preference:** 5% is added to non-resident totals before comparing. The resident certificate must be valid (it has a granted date and an expiration date).
- **Bond rule on the intake form:** "Any bid over $150,000 a Bid Bond is Required by Statute. Bids $50,000 up to 149,999 it is at the discretion of the Bidding Agency." The same wording applies to the performance and payment bond. (This conflicts with a decision already in the log; see 3.)
- **Bid bond:** included in the bid or uploaded separately on the platform.

### 1.6 Post-award bond package

- Delivered to the procurement office within 20 days of receiving the letter of intent:
  1. **Performance and payment bond** for 100% of the accepted bid. The original only: no copy, fax or email. It must be legal size, printed front to back, and notarized for both the principal and the surety.
  2. **Surety power of attorney** naming the attorney-in-fact who signed, with a per-bond limit.
  3. **Certification letter**: a notarized company resolution authorizing the person who signed the bond. It comes from the bidder, not the bonding company.
- **The company name must exactly match the Secretary of State registration.** Staff pull the registration record to compare. If it doesn't match, the bond is *returned for correction*, not rejected for good.
- **The bond is left undated** when it arrives. The surety authorizes the agency to fill in the dates after the contract is signed, because the bond date must be on or after the contract date.
- The bond goes to the state's legal office for approval as to form, then back to the agency signed. Change orders require a bond rider that goes through the same steps.
- Delivered directly to the requesting agency: insurance (including builder's risk), a workers' compensation certificate of good standing, an unemployment insurance certificate of good standing, and the same for each subcontractor before they start work.

---

## 2. Proposed (not decided)

Ranked by evidence and fit, not by how big the pain is.

1. **Structured price schedule and generated recap/award.** Bidders enter line items as data, and the recap, preference math and award document are generated from it. This removes the error class in 1.4 completely and is all deterministic, with no AI. It's the strongest evidence-backed feature.
2. **Sealed submission with enforced close.** No staff override of the deadline, plus an audit log. Bonds are attached to the bid record, not uploaded separately.
3. **Document checks on scanned bid forms.** The AI reads signatures, amounts in words, addenda numbers and checkmarks from scans and cites the page; rules then compare the extracted values (words = figures, sum of line items = total, all addenda listed, resident certificate valid on the due date). The value is highest where bids are paper scans, which is most of them.
4. **Structured solicitation setup.** The intake form fields, the date rules (bid due ≥ 5 days after answers due; 3-day lead time; 2-week ad period), the value-band requirements and the bid schedule definition. This is the data the checks in items 1–3 need, and it catches inconsistent dates at the source.
5. **Post-award bond tracking.** A 20-day clock, the package checklist, a name match against registration data, the dating-after-contract step, legal approval, and riders.
6. **Full solicitation document authoring and validation.** Template-driven generation and an AI consistency check of the narrative documents. This is the contact's biggest frustration, but it's also the largest build. Item 4 delivers the structured part of it.

---

## 3. Open questions

1. **Bond threshold:** the intake form says the statute applies to a *bid* over $150,000, with discretion between $50,000 and $149,999. The decision log says the *project estimate* at $150,000 or more. Which one does the system enforce, and what happens when the estimate and the bid fall on opposite sides of the line?
2. **Bidder access before close:** the contact says bidders can't reopen what they submitted, but the RFB lets them modify or withdraw before opening. Does modifying mean a full replacement upload?
3. **What happens during the responsiveness review**, and which defects are waived or fixable rather than disqualifying? Is the bid-bond cure period (5 p.m. the next business day) the only cure?
4. **Why was one bidder in the example marked non-responsive?** (The file is a scan with no text layer, so the reason isn't readable.)
5. **How is "responsible" determined** by the requesting agency? Are qualifications, references and current work scored or just read?
6. **Who drafts, reviews, approves and publishes** the solicitation documents, and is there a required approval before publication?
7. **What happens between the letter of intent and the signed contract** (negotiation, contracts staff)?
8. **Is the shared drive the official record**, or only a working copy? What are the retention requirements?
