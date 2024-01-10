import { isNil, omitBy } from "lodash";
import { Duration, DurationObjectUnits } from "luxon";

export function buildUrl(
  path: string,
  params: Record<string, string | number | null | undefined>
) {
  const queryString = new URLSearchParams(omitBy(params, isNil)).toString();
  return `${path}${queryString ? "?" + queryString : ""}`;
}

export function pluralise(count: number, singular: string, plural?: string) {
  const noun = count == 1 ? singular : plural || `${singular}s`;
  return `${count} ${noun}`;
}

export function choose(values: string[]): string {
  return values[Math.floor(Math.random() * values.length)];
}

const DIFF_UNITS: Partial<Record<keyof DurationObjectUnits, string>> = {
  days: "day",
  hours: "hour",
  minutes: "minute",
  seconds: "second",
  milliseconds: "millisecond",
};

export function formatDiff(diff: Duration, concise = false, maxParts = 2) {
  const parts = diff.toObject();
  const units = (Object.keys(DIFF_UNITS) as (keyof DurationObjectUnits)[])
    .filter((unit) => unit != "milliseconds" && parts[unit])
    .slice(0, maxParts);
  if (units.length) {
    return units
      .map((unit) => {
        const value = Math.floor(parts[unit]!);
        if (concise) {
          return `${value}${DIFF_UNITS[unit]![0]}`;
        } else {
          return pluralise(Math.floor(parts[unit]!), DIFF_UNITS[unit]!);
        }
      })
      .join(", ");
  } else {
    const value = Math.floor(diff.toMillis());
    if (concise) {
      return `${value}ms`;
    } else {
      return pluralise(value, "millisecond");
    }
  }
}
