export function formatSolicitationNumber(fiscalYear: number, seq: number): string {
  const yy = String(fiscalYear % 100).padStart(2, "0");
  return `${yy}-${String(seq).padStart(4, "0")}`;
}
