-- Version 1 of every clause. Written for the fictional State of Calder.
-- Bodies are plain text: blank lines separate paragraphs, a first line starting
-- with "# " is a heading, and {{name}} is replaced when a document is generated.
-- Variables: stateName, officeName, agencyName, number, bidDueDate, bidDueTime,
-- questionsDue, answersDue, bidValidityDays.
-- clauses is insert-only; a change to wording is a new version row, never an edit.

insert into public.clauses (key, version, body, created_by) values

('notice', 1, $clause$# Notice of Request for Bids

The {{officeName}}, acting for {{agencyName}}, invites sealed bids for the project described in this document (Solicitation {{number}}). Bids are received until {{bidDueTime}} on {{bidDueDate}}. A bid that arrives after that time is not opened and is returned unread.

This solicitation follows the procurement rules of the {{stateName}}. Each bidder is responsible for reading this whole document, including the plans and specifications listed at the end, before bidding.$clause$, null),

('prebid_meeting', 1, $clause$# Pre-Bid Meeting

A pre-bid meeting will be held at the time and place shown in the meeting details below. The meeting gives bidders a chance to see the work, hear an overview of the project and ask questions.

If the details say attendance is required, a bid from a firm that was not represented at the meeting will be rejected. If the details say attendance is optional, bidders are still encouraged to attend, but a bid will not be penalized for absence.

Nothing said at the meeting changes this document. Only a written addendum does that.$clause$, null),

('background_check', 1, $clause$# Facility Access and Background Checks

The work site is a secured facility. Every person who will work on site must pass a background check before being allowed in. The contact and the lead time needed to complete the checks are listed below.

Bidders should allow for that lead time in their schedules. Delays caused by late or incomplete background check requests are not grounds for extra time or extra payment.$clause$, null),

('addenda', 1, $clause$# Addenda

The {{officeName}} may change this solicitation by issuing a written addendum. Addenda are posted with the solicitation notice. They are not mailed, so bidders must check for them before submitting a bid, and again on the day before bids are due.

A bidder must acknowledge every addendum on the bid form. A bid that does not acknowledge all addenda issued may be rejected.$clause$, null),

('substitutions', 1, $clause$# Substitutions

The specifications name materials, products and methods. A bidder who wants to propose an equal alternative must ask in writing before {{questionsDue}}, and must give enough information for the {{officeName}} to judge whether the alternative is truly equal.

An alternative is accepted only if it is listed in an addendum. Bids based on an alternative that has not been approved in this way will be treated as bids for the specified item.$clause$, null),

('submission', 1, $clause$# Submission of Bids

Bids must be sealed and delivered as described in the notice, and must be in the hands of the {{officeName}} by {{bidDueTime}} on {{bidDueDate}}. The bidder is responsible for timely delivery. Mail, courier and electronic delays are the bidder's risk.

Each bid must include the bid form sections and the other items listed in the evaluation checklist, completed in ink or typed, and signed by a person with authority to bind the firm. Do not alter the wording of the bid form. Bids that are conditional, incomplete or unsigned may be rejected.

Bids are opened in public at the time due. The name of each bidder and the total bid are read aloud. Other bid contents stay confidential until an award is made.

A bid stays open for acceptance for {{bidValidityDays}} days after the bid due date.$clause$, null),

('bid_deposit', 1, $clause$# Bid Security

A bid must be accompanied by bid security equal to ten percent of the total bid, in the form of a bid bond issued by a surety company authorized to do business in the {{stateName}}. The bond must name the {{officeName}} as the party protected.

If the low bidder fails to sign the contract or fails to provide the required bonds and insurance, the bid security is forfeited. Security belonging to unsuccessful bidders is returned after the contract is signed.$clause$, null),

('performance_bond', 1, $clause$# Performance and Payment Bonds

The firm awarded the contract must provide, within the time stated in the notice of award, a performance bond and a payment bond. Each must be for one hundred percent of the contract price and be issued by a surety company authorized to do business in the {{stateName}}.

The performance bond protects the owner if the work is not finished as the contract requires. The payment bond protects those who supply labor and materials to the work. The contractor pays for both bonds, and the cost must be included in the bid.$clause$, null),

('modification_withdrawal', 1, $clause$# Modification and Withdrawal of Bids

A bidder may withdraw or change a bid at any time before the bid due time. A request must be in writing, signed by the same kind of authorized person who signed the bid, and delivered to the {{officeName}} before {{bidDueTime}} on {{bidDueDate}}.

A change must not reveal the bid price. The safest way to change a bid is to withdraw it and deliver a complete replacement in a new sealed package before the deadline. A change that discloses the price before the bid opening will cause the bid to be rejected.

After the bid due time a bid cannot be withdrawn until the bid validity period has ended.$clause$, null),

('award_contract', 1, $clause$# Award and Contract

The contract will be awarded to the lowest responsible bidder whose bid meets the requirements of this document, or all bids will be rejected. The {{officeName}} may take the alternates into account in the order stated on the bid form when deciding which bid is lowest.

The notice of award is sent in writing. The successful bidder must sign and return the contract, together with the required insurance and any required bonds, within the time stated in the notice of award. Work may not begin until the contract is fully signed and the {{agencyName}} gives a written notice to proceed.

The sample contract listed at the end of this document shows the terms the contract will contain. By bidding, the bidder agrees to those terms.$clause$, null),

('resident_preference', 1, $clause$# Preference for Resident Bidders

When two bids are otherwise equal in price, the {{stateName}} gives preference to a bidder that is a resident of the state, as the state's procurement rules define residency. A bidder claiming this preference must say so on the bid form and be able to show that it qualifies.

This preference never applies where it would conflict with a requirement of a program that is paying for the work.$clause$, null),

('registrations', 1, $clause$# Licenses and Registrations

At the time of bidding, the bidder must hold every license and registration that the {{stateName}} requires to perform this work, and must be in good standing to do business in the state. The bidder must list its license and registration numbers on the bid form.

Subcontractors must also hold the licenses and registrations their part of the work requires. The {{officeName}} may ask for proof at any time before award, and a bid may be rejected if the proof is not provided promptly.$clause$, null),

('apprentice_credit', 1, $clause$# Apprenticeship Program Credit

Because of the size of this project, bidders are asked on the bid form whether they take part in an approved apprenticeship program. Participation is considered when the {{officeName}} compares bids that are otherwise equal.

A bidder that answers yes must be able to show, on request, that its program is approved and that apprentices are working on its current projects. An answer of no does not make a bid ineligible.$clause$, null),

('reservation_of_rights', 1, $clause$# Reservation of Rights

The {{officeName}} may reject any or all bids, waive minor mistakes in a bid that do not change its meaning or give the bidder an advantage, postpone the bid opening, and cancel this solicitation at any time before the contract is signed. None of these actions makes the {{stateName}} or {{agencyName}} responsible for any cost the bidder spent on preparing a bid.

Preparing and delivering a bid is at the bidder's own expense.$clause$, null),

('questions', 1, $clause$# Questions

Questions about this solicitation must be sent in writing to the person named as the contact in the notice, and must be received by {{questionsDue}}. Questions received later may not be answered.

Written answers are issued in an addendum by {{answersDue}}. Answers given any other way do not bind the {{stateName}}.$clause$, null),

('communication_restrictions', 1, $clause$# Communication Restrictions

From the date this solicitation is released until the contract is awarded, bidders and people acting for them must not discuss this solicitation with any employee of the {{stateName}}, any member of the evaluation team, or any official of {{agencyName}}, except through the written question process in this document or at the pre-bid meeting.

A bidder that breaks this rule may have its bid rejected. This rule does not stop anyone from carrying out existing work or contracts that have nothing to do with this solicitation.$clause$, null),

('insurance', 1, $clause$# Insurance

The contractor must carry the following insurance for the whole time the contract is in force, with insurers authorized to do business in the {{stateName}}:

(a) general liability insurance for bodily injury and property damage, including coverage for completed work;

(b) automobile liability insurance covering every vehicle used on the work;

(c) workers' compensation insurance as the state requires, with employer's liability coverage; and

(d) builder's risk insurance covering the work while it is being built, unless the contract says the owner provides it.

The minimum amounts of coverage are in the sample contract. A certificate of insurance showing these coverages must accompany the bid, and the {{agencyName}} and the {{stateName}} must be named as additional insured on the liability policies. Notice must be given to the owner before any policy is canceled.$clause$, null),

('prevailing_wage', 1, $clause$# Prevailing Wages

Because of the size of this project, every worker on the site must be paid at least the wage rates published for this kind of work and place. The current rates are listed among the attached documents and are part of this solicitation.

The contractor and every subcontractor must pay those rates, keep weekly payroll records, and give those records to the {{agencyName}} on request. A contractor that underpays workers must repay the difference and may be removed from this work and barred from future bidding.$clause$, null),

('warranty', 1, $clause$# Warranty

The contractor warrants that the work will be free from defects in materials and workmanship for one year after the owner accepts the work as complete, unless the specifications set a longer period for a particular item. A longer manufacturer's warranty passes to the owner.

The contractor must correct any defect reported during the warranty period promptly and at its own expense, including the cost of opening and restoring other work needed to reach it.$clause$, null),

('federal_domestic_content', 1, $clause$# Federal Funding and Domestic Content

Federal money is helping to pay for this project. Because of that, the contractor must follow the federal rules that come with the money, which are summarized in the sample contract and the specifications.

Iron, steel, manufactured products and construction materials permanently built into the work must be made in the United States, unless the {{agencyName}} grants a written waiver. The bidder must say on the bid form that it will comply. The contractor must keep records showing where materials come from and give them to the owner or to a federal reviewer on request.

If any federal rule is stricter than another term of this document, the federal rule controls.$clause$, null),

('evaluation_award', 1, $clause$# Evaluation and Award

The {{officeName}} first checks each bid against the checklist below. Each item is marked MET or NOT MET. A bid with any item marked NOT MET may be rejected as not responsive. Page limits stated in the checklist apply to the section they name; pages beyond the limit are not read.

Bids that pass the checklist are compared on total price as described in the award clause. Prices are compared only after all bids have been checked. The {{officeName}} will post the result of the evaluation and a notice of intended award for bidders to read.

A bidder who disagrees with the result may protest in writing as the {{stateName}} procurement rules allow. The protest must reach the {{officeName}} within the time those rules give, which starts on the day the notice of intended award is posted.$clause$, null),

('bid_form_instructions', 1, $clause$# Instructions for Completing the Bid Form

Read this whole document before filling in the bid form. Type or print clearly in ink. Fill in every line. Enter a price for every line item, using dollars and cents. Write "no change" for an alternate you are not pricing at a change. Do not leave a price line blank.

If you make a mistake, draw one line through it, write the correction beside it and initial it. Do not use correction fluid. A bid with an unreadable or unclear price may be rejected.

The person signing must be authorized to bind the firm. Attach the other items the checklist lists, in the order shown, and keep within the page limits stated. Put the bid, together with any bid security, in one sealed package marked with the solicitation number and the bid due date.$clause$, null),

('bid_form_terms', 1, $clause$# Bid Terms

The undersigned bidder offers to perform all of the work for this project, as described in the plans, specifications and addenda, for the total price shown in Section 1, and agrees to complete the work within the time stated in the contract.

The bidder confirms that it has examined the site and this solicitation, that it has acknowledged every addendum, and that its price includes all labor, materials, equipment, taxes, insurance, bonds and other costs needed to do the work.

The bid stays open for acceptance for {{bidValidityDays}} days after the bid due date. If the bidder is awarded the contract, it will sign the contract and provide the required insurance and any required bonds within the time stated in the notice of award.$clause$, null),

('signature_certifications', 1, $clause$# Signature and Certifications

By signing, the person named below, who is authorized to bind the bidder, certifies on the bidder's behalf that:

(a) the bid was prepared on its own, without any agreement or understanding with another bidder about prices or about whether to bid;

(b) the bidder has not offered or given a gift or favor to any public employee in connection with this solicitation;

(c) the bidder is not barred from public contracts in the {{stateName}} or suspended from them;

(d) everything stated in the bid is true and complete; and

(e) the bidder has read and agrees to every term of Solicitation {{number}}.

A false statement may lead to rejection of the bid, cancellation of any contract awarded, and the other remedies the law allows.$clause$, null);
