import { isNil, omitBy } from 'lodash';

export function buildUrl(path: string, params: Record<string, string | number | null | undefined>) {
  const queryString = new URLSearchParams(omitBy(params, isNil)).toString();
  return `${path}${queryString ? '?' + queryString : ''}`;
}
