import type { HTMLAttributes, TableHTMLAttributes, TdHTMLAttributes, ThHTMLAttributes } from "react";
import { cx } from "./cx";

export function Table({ className, ...rest }: TableHTMLAttributes<HTMLTableElement> & { "data-testid"?: string }) {
  return (
    <div className="ui-table-scroll">
      <table {...rest} className={cx("ui-table", className)} />
    </div>
  );
}

export function Th({ numeric, className, ...rest }: ThHTMLAttributes<HTMLTableCellElement> & { numeric?: boolean }) {
  return <th {...rest} className={cx(numeric && "ui-num tabular", className)} />;
}

export function Td({ numeric, className, ...rest }: TdHTMLAttributes<HTMLTableCellElement> & { numeric?: boolean }) {
  return <td {...rest} className={cx(numeric && "ui-num tabular", className)} />;
}

export function EmptyState({ className, ...rest }: HTMLAttributes<HTMLParagraphElement>) {
  return <p {...rest} className={cx("ui-empty", className)} />;
}
