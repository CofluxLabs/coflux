export function parseHash(hash: string | undefined): [null, null] | [string, null] | [string, number] {
  const parts = hash?.split('/', 2);
  if (parts) {
    if (parts.length == 2) {
      return [parts[0], parseInt(parts[1])];
    } else {
      return [parts[0], null];
    }
  } else {
    return [null, null];
  }
}
