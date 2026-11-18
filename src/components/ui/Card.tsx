import type { HTMLAttributes, ReactNode } from "react";
import { cx } from "./cx";

export type CardProps = {
  title?: ReactNode;
  titleId?: string;
  as?: "section" | "div" | "aside";
  "data-testid"?: string;
} & Omit<HTMLAttributes<HTMLElement>, "title">;

export function Card({ title, titleId, as: Tag = "section", className, children, ...rest }: CardProps) {
  return (
    <Tag {...rest} className={cx("ui-card", className)}>
      {title !== undefined && (
        <h2 className="ui-card-title" id={titleId}>
          {title}
        </h2>
      )}
      {children}
    </Tag>
  );
}
