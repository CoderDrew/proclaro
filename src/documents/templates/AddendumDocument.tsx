import { describeScheduleChange } from "../../domain/addendum/diff";
import type { AddendumDocContext } from "../addendumDoc";
import { formatDate } from "../format";
import { footerTemplate } from "./BidFormSections";
import { FreeText, Shell } from "./Layout";


/**
 * The addendum PDF (spec §3): number, solicitation number and title, publish date, the narrative, the computed
 * schedule changes and key-date changes, and the answered questions with no names. The footer uses the bid form's
 * mechanism: a hidden `<footer data-footer-template>` that the PDF step turns into Chromium's page footer.
 */
export function AddendumDocument({ ctx }: { ctx: AddendumDocContext }) {
  const tpl = footerTemplate({ draft: false, number: ctx.solicitationNumber, version: ctx.version });
  return (
    <Shell title={`Addendum ${ctx.number} to Solicitation ${ctx.solicitationNumber}`} draft={false}>
      <h1>Addendum {ctx.number}</h1>
      <table data-addendum-meta>
        <tbody>
          <tr><th>Solicitation</th><td>{ctx.solicitationNumber}</td></tr>
          <tr><th>Title</th><td>{ctx.title}</td></tr>
          <tr><th>Version</th><td>Version {ctx.version}</td></tr>
          <tr><th>Published</th><td>{formatDate(ctx.publishedOn)}</td></tr>
        </tbody>
      </table>

      <section data-addendum-narrative>
        <h2>Changes in this addendum</h2>
        <FreeText text={ctx.narrative} />
      </section>

      <section data-addendum-schedule>
        <h2>Bid schedule changes</h2>
        {ctx.changes.length === 0
          ? <p>This addendum does not change the bid schedule.</p>
          : <ul>{ctx.changes.map((c) => <li key={`${c.kind}-${c.position}`}>{describeScheduleChange(c)}</li>)}</ul>}
      </section>

      <section data-addendum-dates>
        <h2>Key date changes</h2>
        {ctx.dateChanges.length === 0
          ? <p>This addendum does not change the key dates.</p>
          : (
            <table>
              <thead><tr><th>Date</th><th>Was</th><th>Now</th></tr></thead>
              <tbody>
                {ctx.dateChanges.map((c) => <tr key={c.field}><td>{c.field}</td><td>{c.before}</td><td>{c.after}</td></tr>)}
              </tbody>
            </table>
          )}
      </section>

      <section data-addendum-answers>
        <h2>Questions and answers</h2>
        {ctx.answers.length === 0
          ? <p>This addendum does not answer any questions.</p>
          : ctx.answers.map((a, i) => (
            <div key={i} data-answer>
              <h3>Question {i + 1}</h3>
              <FreeText text={a.publishedQuestion} />
              <p><strong>Answer</strong></p>
              <FreeText text={a.answer} />
            </div>
          ))}
      </section>

      <footer hidden data-footer="final" data-footer-template={tpl} />
    </Shell>
  );
}
