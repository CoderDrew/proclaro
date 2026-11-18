import type { HTMLAttributes } from "react";
import { formatMoney, type Cents } from "@/domain/money";
import { cx } from "./cx";

export function Money({ cents, className, ...rest }: HTMLAttributes<HTMLSpanElement> & { cents: Cents }) {
  return <span {...rest} className={cx("tabular", className)}>{formatMoney(cents)}</span>;
}
