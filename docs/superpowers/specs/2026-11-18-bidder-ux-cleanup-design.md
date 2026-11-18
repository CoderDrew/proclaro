# Bidder bid page: UX cleanup

Status: Approved by Drew, 2026-11-18 (small change; short design).

## Why
Drew walked the bidder flow and found the bid page hard to follow: printing was a link, the bond radios were hard to read, the upload slots were confusing, and it wasn't clear that amounts had to be saved. Behaviour rules stay as they are; this is about making them understandable.

## Changes
1. **Two print buttons.**
   - **Print Blank Bid Form** goes at the top of the bid page. It prints the solicitation's unfilled bid form, for bidders who fill it in by hand. It is available to any signed-in bidder on an open, published solicitation, even before they start a draft.
   - **Print Bid Form for Signature** goes at the bottom. It prints the pre-filled PDF, and it is enabled only when every amount is filled in and saved.
   - Both are buttons, not links.
2. **Bond choice.** Show each option on its own line, with its label right next to the radio button, and space them tightly.
3. **Required uploads keep the existing rule: one file per item.** A new upload replaces the old one. Make that obvious:
   - Line up the upload controls in one column.
   - Before a file is uploaded, the control reads **Upload file**.
   - After an upload, the item shows the file name with a **Replace file** button and a **Remove** link, instead of a bare "Choose File".
   - A one-line note above the list says: "One file per item. Uploading again replaces the current file."
4. **Saving amounts.**
   - Rename the button to **Save Amounts**.
   - While there are unsaved changes, show an "Unsaved changes" notice next to it, and disable both Print Bid Form for Signature and Submit.
   - The browser warns before the bidder leaves the page with unsaved amounts.

## Non-goals
- No database or sealing changes.
- No visual restyle beyond these items.
- No multiple files per item: Drew confirmed one file per item is the rule.

## Left to the builder
- How the blank form is rendered. Reuse the slice-1 renderer with no fill, and use the published snapshot just as the filled form does.
- Exact layout, within the existing look.
