import { useState, useEffect } from "react";

export default function useNow(intervalMs = 1000) {
  const [now, setNow] = useState(new Date());
  useEffect(() => {
    if (intervalMs) {
      const interval = setInterval(() => setNow(new Date()), intervalMs);
      return () => clearInterval(interval);
    }
  }, [intervalMs]);
  return now;
}
