import { useTopic } from '@topical/react';
import { ChangeEvent, useCallback } from 'react';
import { useSearchParams } from 'react-router-dom';

import * as models from '../models';
import Loading from './Loading';

type Props = {
  environments: string[] | undefined;
  className?: string;
}

export default function EnvironmentSelector({ environments, className }: Props) {
  const [searchParams, setSearchParams] = useSearchParams();
  const selected = searchParams.get('environment');
  const handleChange = useCallback((ev: ChangeEvent<HTMLSelectElement>) => {
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
          {environments.map((environmentName) => (
            <option value={environmentName} key={environmentName}>
              {environmentName}
            </option>
          ))}
        </select>
      )}
    </div>
  );
}
