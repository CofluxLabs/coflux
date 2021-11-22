import { useCallback, useEffect, useState } from 'react';

function getWindowHash() {
  return typeof window !== 'undefined' && window.location.hash.substr(1) || undefined;
}

export default function useWindowHash() {
  const [_, setCount] = useState(0);
  const update = useCallback(() => setCount((c) => c + 1), []);
  useEffect(() => {
    window.addEventListener('hashchange', update);
    return () => window.removeEventListener('hashchange', update);
  }, [update]);
  return getWindowHash();
}
