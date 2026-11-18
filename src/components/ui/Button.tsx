import type { AnchorHTMLAttributes, ButtonHTMLAttributes } from "react";

export type ButtonVariant = "primary" | "secondary" | "danger" | "link";

export type ButtonProps = Omit<ButtonHTMLAttributes<HTMLButtonElement>, "type"> & {
  type: "button" | "submit";
  variant?: ButtonVariant;
  loading?: boolean;
  "data-testid"?: string;
};

/** React 19 passes `ref` as a normal prop, so it reaches the <button> through the spread. */
export function Button({ variant = "secondary", loading, className, disabled, children, ...rest }: ButtonProps) {
  const cls = ["ui-button", `ui-button--${variant}`, className].filter(Boolean).join(" ");
  return (
    <button {...rest} className={cls} disabled={disabled || loading} aria-busy={loading ? true : rest["aria-busy"]}>
      {children}
    </button>
  );
}

export type ButtonLinkProps = AnchorHTMLAttributes<HTMLAnchorElement> & { variant?: ButtonVariant };

/** An <a> with the Button look, for navigation (a real link, same href and target) that should read as a button. */
export function ButtonLink({ variant = "secondary", className, children, ...rest }: ButtonLinkProps) {
  const cls = ["ui-button", `ui-button--${variant}`, className].filter(Boolean).join(" ");
  return <a {...rest} className={cls}>{children}</a>;
}
