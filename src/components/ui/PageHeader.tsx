import type { HTMLAttributes, ReactNode } from "react";
import { cx } from "./cx";

export function PageHeader({
  crumbs, eyebrow, title, actions, className, ...rest
}: Omit<HTMLAttributes<HTMLElement>, "title"> & { crumbs?: ReactNode; eyebrow?: ReactNode; title: ReactNode; actions?: ReactNode }) {
  return (
    <header {...rest} className={cx("ui-page-header", className)}>
      {crumbs !== undefined && <div className="ui-crumbs">{crumbs}</div>}
      <div className="ui-page-header-row">
        <div>
          {eyebrow !== undefined && <div className="ui-eyebrow">{eyebrow}</div>}
          <h1>{title}</h1>
        </div>
        {actions !== undefined && <div className="ui-page-actions">{actions}</div>}
      </div>
    </header>
  );
}

export function Page({
  width = "full", children, className, ...rest
}: HTMLAttributes<HTMLElement> & { width?: "narrow" | "full" }) {
  return <main {...rest} className={cx("ui-page", `ui-page--${width}`, className)}>{children}</main>;
}
