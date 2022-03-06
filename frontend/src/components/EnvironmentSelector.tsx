import { useCallback } from 'react';
import { useSearchParams } from 'react-router-dom';

import * as models from '../models';
import useSubscription from '../hooks/useSubscription';
import Loading from './Loading';

type Props = {
  className?: string;
}

export default function EnvironmentSelector({ className }: Props) {
  const [searchParams, setSearchParams] = useSearchParams();
  const selected = searchParams.get('environment');
  const environments = useSubscription<Record<string, models.Environment>>('environments');
  const handleChange = useCallback((ev) => {
    // TODO: merge with existing params
    setSearchParams({ environment: ev.target.value })
  }, [setSearchParams]);
  return (
    <div className={className}>
      {environments === undefined ? (
        <Loading />
      ) : !Object.keys(environments).length ? (
        <p>No environments</p>
      ) : (
        <select
          value={selected || ""}
          onChange={handleChange}
          className="text-slate-300 bg-slate-700 rounded p-2 w-full"
        >
          <option value="">Select...</option>
          {Object.entries(environments).map(([environmentId, environment]) => (
            <option value={environment.name} key={environmentId}>
              {environment.name}
            </option>
          ))}
        </select>
      )}
    </div>
  );
}
