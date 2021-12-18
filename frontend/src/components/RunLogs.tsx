import React from 'react';
import { sortBy } from 'lodash';
import classNames from 'classnames';
import Link from 'next/link';
import { DateTime } from 'luxon';

import * as models from '../models';
import { useSubscription } from '../hooks/useSocket';

const LOG_LEVELS = {
  0: ['Debug', 'bg-gray-400'],
  1: ['Info', 'bg-blue-400'],
  2: ['Warning', 'bg-yellow-500'],
  3: ['Error', 'bg-red-600']
}

type Props = {
  run: models.Run;
  activeStepId: string | null;
  activeAttemptNumber: number | null;
}

export default function RunLogs({ run, activeStepId, activeAttemptNumber }: Props) {
  const logs = useSubscription<Record<string, models.LogMessage>>(`logs.${run.id}`);
  const startTime = DateTime.fromISO(run.createdAt);
  return (
    <div>
      {logs === undefined ? (
        <p><em>Loading...</em></p>
      ) : Object.keys(logs).length == 0 ? (
        <p><em>None</em></p>
      ) : (
        <table className="w-full">
          <tbody>
            {sortBy(Object.values(logs), 'createdAt').map((message, index) => {
              const [name, className] = LOG_LEVELS[message.level];
              const step = Object.values(run.steps).find((s) => Object.values(s.attempts).some((a) => a.executionId == message.executionId));
              const attempt = step && Object.values(step.attempts).find((a) => a.executionId == message.executionId);
              const isActive = step && step.id == activeStepId && attempt && attempt.number == activeAttemptNumber;
              const createdAt = DateTime.fromISO(message.createdAt);
              return (
                <tr key={index}>
                  <td className="px-2 text-sm w-20">
                    <span title={createdAt.toLocaleString(DateTime.DATETIME_SHORT_WITH_SECONDS)}>
                      +{(createdAt.diff(startTime).toMillis())}ms
                    </span>
                  </td>
                  <td className="px-2 w-48">
                    {step && attempt && (
                    <Link href={`/projects/project_1/runs/${run.id}/logs${isActive ? '' : `#${step.id}/${attempt.number}`}`}>
                      <a className={classNames('whitespace-nowrap p-1', isActive && 'ring rounded')}>
                        <span className="font-mono">{step.target}</span> <span className="text-gray-500 text-sm">({step.repository})</span>
                      </a>
                    </Link>
                    )}
                  </td>
                  <td className="px-2 w-20">
                    <span className={classNames('rounded p-1 text-xs uppercase text-white mr-1 font-bold', className)}>{name}</span>
                  </td>
                  <td className="px-2">
                    {message.message}
                  </td>
                </tr>
              );
            })}
          </tbody>
        </table>
      )}
    </div>
  );
}

