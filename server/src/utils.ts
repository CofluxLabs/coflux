import { isNil, omitBy } from "lodash";

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
