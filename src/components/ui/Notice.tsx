import type { HTMLAttributes, ReactNode } from "react";
import { cx } from "./cx";

export type NoticeTone = "info" | "success" | "warning" | "error";

export function Notice({
  tone, title, children, className, ...rest
}: Omit<HTMLAttributes<HTMLDivElement>, "title"> & {
  tone: NoticeTone;
  title?: ReactNode;
  "data-testid"?: string;
}) {
  return (
    <div {...rest} className={cx("ui-notice", `ui-notice--${tone}`, className)}>
      {title !== undefined && <strong className="ui-notice-title">{title}</strong>}
      {children}
    </div>
  );
}
