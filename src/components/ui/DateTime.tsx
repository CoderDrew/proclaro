import type { TimeHTMLAttributes } from "react";
import { formatInstant } from "@/app/solicitations/status";

export function DateTime({ iso, tz, ...rest }: Omit<TimeHTMLAttributes<HTMLTimeElement>, "dateTime"> & { iso: string; tz: string }) {
  return <time {...rest} dateTime={iso}>{formatInstant(iso, tz)}</time>;
}
