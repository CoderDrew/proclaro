// Pure helpers for the public page: versions and the published questions and answers.

export interface PublishedAnswerRow { addendum_number: number; published_question: string; answer: string }
export interface AnswerGroup { addendum: number; items: { question: string; answer: string }[] }

/** Groups published answers by addendum, ascending. Only the addendum number, question and answer are kept. */
export function groupAnswers(rows: readonly PublishedAnswerRow[]): AnswerGroup[] {
  const by = new Map<number, AnswerGroup>();
  for (const r of rows) {
    const g = by.get(r.addendum_number) ?? { addendum: r.addendum_number, items: [] };
    g.items.push({ question: r.published_question, answer: r.answer });
    by.set(r.addendum_number, g);
  }
  return [...by.values()].sort((a, b) => a.addendum - b.addendum);
}

export const versionLabel = (version: number, current: boolean) => `Version ${version}${current ? " (current)" : ""}`;
export const addendumHeading = (n: number) => `Addendum ${n}`;
