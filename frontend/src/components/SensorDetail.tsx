import React, { Fragment, useCallback, useState } from 'react';
import Link from 'next/link';
import { sortBy } from 'lodash';

import * as models from '../models';
import useSocket, { useSubscription } from '../hooks/useSocket';
import Heading from './Heading';
import classNames from 'classnames';

type Props = {
  projectId: string | null;
  sensorId: string | null;
}

export default function SensorDetail({ projectId, sensorId }: Props) {
  const { socket } = useSocket();
  const sensor = useSubscription<models.SensorActivation>('sensor_activation', sensorId);
  const [deactivating, setDeactivating] = useState(false);
  const handleDeactivateClick = useCallback(() => {
    if (confirm('Are you sure you want to deactivate this sensor?')) {
      setDeactivating(true);
      socket?.request('deactivate_sensor', [sensorId], () => {
        setDeactivating(false);
      });
    }
  }, [sensorId, socket]);
  if (!sensor) {
    return <p>Loading...</p>;
  } else {
    return (
      <Fragment>
        <div className="flex items-start">
          <Heading><span className="font-mono">{sensor.target}</span> <span className="text-gray-500">({sensor.repository})</span></Heading>
          {sensor.deactivatedAt ? (
            <span className="ml-2 mt-4">(deactivated)</span>
          ) : (
            <button
              className={classNames('px-2 py-1 m-2 border rounded font-bold', deactivating ? 'border-blue-200 text-blue-200' : 'border-blue-400 text-blue-500 hover:bg-blue-100')}
              disabled={deactivating}
              onClick={handleDeactivateClick}
            >
              Deactivate
            </button>
          )}
        </div>
        {Object.keys(sensor.runs).length ? (
          <ol>
            {sortBy(Object.values(sensor.runs), 'createdAt').map((run) => (
              <li key={run.id}>
                <Link href={`/projects/${projectId}/runs/${run.id}`}>
                  <a className="underline">{run.id} ({run.createdAt})</a>
                </Link>
              </li>
            ))}
          </ol>
        ) : (
          <p>No runs</p>
        )}
      </Fragment>
    );
  }
}
