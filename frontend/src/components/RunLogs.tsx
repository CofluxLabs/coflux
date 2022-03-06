import { sortBy } from 'lodash';
import classNames from 'classnames';
import { DateTime } from 'luxon';
import { Link } from 'react-router-dom';

import * as models from '../models';
import { buildUrl } from '../utils';

const LOG_LEVELS = {
  0: ['Debug', 'text-gray-400'],
  1: ['Info', 'text-blue-400'],
  2: ['Warning', 'text-yellow-500'],
  3: ['Error', 'text-red-600']
}

type Props = {
  run: models.Run;
  logs: Record<string, models.LogMessage>;
  projectId: string;
  environmentName: string | null | undefined;
  activeStepId: string | null;
  activeAttemptNumber: number | null;
}

export default function RunLogs({ run, logs, projectId, environmentName, activeStepId, activeAttemptNumber }: Props) {
  const startTime = DateTime.fromISO(run.createdAt);
  return (
    <div>
      {Object.keys(logs).length == 0 ? (
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
                  <td className="text-sm w-0">
                    <span title={createdAt.toLocaleString(DateTime.DATETIME_SHORT_WITH_SECONDS)}>
                      +{(createdAt.diff(startTime).toMillis())}ms
                    </span>
                  </td>
                  <td className="w-0">
                    <div className="w-40">
                      {step && attempt && (
                        <Link
                          to={buildUrl(`/projects/${projectId}/runs/${run.id}/logs`, { environment: environmentName, step: isActive ? undefined : step.id, attempt: isActive ? undefined : attempt.number })}
                          className={classNames('inline-block whitespace-nowrap px-1 truncate max-w-full rounded', isActive && 'ring ring-offset-2')}
                        >
                          <span className="font-mono">{step.target}</span> <span className="text-gray-500 text-sm">({step.repository})</span>
                        </Link>
                      )}
                    </div>
                  </td>
                  <td className="w-0">
                    <span className={classNames('font-bold pr-1 inline-block', className)} title={name}>
                      <svg xmlns="http://www.w3.org/2000/svg" width="10" height="10" fill="currentColor" viewBox="0 0 16 16">
                        <circle cx="8" cy="8" r="8" />
                      </svg>
                    </span>
                  </td>
                  <td className="">
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

