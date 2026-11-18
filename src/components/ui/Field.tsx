import { Children, cloneElement, isValidElement, useId } from "react";
import type { HTMLAttributes, InputHTMLAttributes, LabelHTMLAttributes, ReactElement, ReactNode } from "react";
import { cx, hasText } from "./cx";

type FieldProps = Omit<HTMLAttributes<HTMLDivElement>, "id" | "children"> & {
  label: ReactNode;
  hint?: string;
  error?: string;
  wide?: boolean;
  /** Id for the control; the child's own id wins, then this, then a generated one. */
  id?: string;
  /** Id for the label element, for a group of controls that is labelled by it (aria-labelledby). */
  labelId?: string;
  children?: ReactNode;
};

/**
 * The label is tied to the control with htmlFor, and hint and error sit outside the label so they
 * are not folded into the control's accessible name. They are linked with aria-describedby instead.
 */
export function Field({ label, hint, error, wide, id, labelId, children, className, ...rest }: FieldProps) {
  const generated = useId();
  const only = Children.count(children) === 1 && isValidElement(children) ? (children as ReactElement<Record<string, unknown>>) : null;
  const controlId = (only && typeof only.props.id === "string" && only.props.id) || id || generated;
  const hintId = hasText(hint) ? `${controlId}-hint` : undefined;
  const errorId = hasText(error) ? `${controlId}-error` : undefined;

  let control: ReactNode = children;
  if (only) {
    const existing = typeof only.props["aria-describedby"] === "string" ? (only.props["aria-describedby"] as string) : undefined;
    const describedBy = cx(existing, hintId, errorId);
    control = cloneElement(only, {
      id: controlId,
      ...(describedBy ? { "aria-describedby": describedBy } : {}),
      ...(errorId ? { "aria-invalid": true } : {}),
    });
  }

  return (
    <div {...rest} className={cx("ui-field", wide && "ui-field--wide", className)}>
      <label className="ui-field-label" id={labelId} htmlFor={controlId}>{label}</label>
      {control}
      {hintId && <span className="ui-field-hint" id={hintId}>{hint}</span>}
      {errorId && <span className="ui-field-error" id={errorId}>{error}</span>}
    </div>
  );
}

export function FieldGrid({ children, className, ...rest }: HTMLAttributes<HTMLDivElement>) {
  return <div {...rest} className={cx("ui-field-grid", "ui-field-grid--auto", className)}>{children}</div>;
}

export function Choice({
  label, children, className, ...rest
}: Omit<LabelHTMLAttributes<HTMLLabelElement>, "children"> & { label: ReactNode; children?: ReactNode }) {
  return (
    <label {...rest} className={cx("ui-choice", className)}>
      {children}
      <span>{label}</span>
    </label>
  );
}

export function MoneyInput({ className, ...rest }: InputHTMLAttributes<HTMLInputElement>) {
  return (
    <span className="ui-money-input">
      <span aria-hidden="true">$</span>
      <input inputMode="decimal" {...rest} className={cx("tabular", className)} />
    </span>
  );
}
