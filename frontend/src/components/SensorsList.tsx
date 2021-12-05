import React, { useCallback, useState } from 'react';
import Router from 'next/router';
import Link from 'next/link';
import classNames from 'classnames';

import * as models from '../models';
import useSocket, { useSubscription } from '../hooks/useSocket';
import ActivateSensorDialog from './ActivateSensorDialog';

type Props = {
  projectId: string | null;
  sensorId?: string | null;
}

export default function SensorsList({ projectId, sensorId: activeSensorId }: Props) {
  const { socket } = useSocket();
  const activations = useSubscription<models.SensorActivation[]>('sensors');
  const [activating, setActivating] = useState(false);
  const [activateDialogOpen, setActivateDialogOpen] = useState(false);
  const handleActivateClick = useCallback(() => setActivateDialogOpen(true), []);
  const handleActivate = useCallback((repository, target) => {
    setActivating(true);
    socket?.request('activate_sensor', [repository, target], (activationId) => {
      setActivating(false);
      setActivateDialogOpen(false);
      Router.push(`/projects/${projectId}/sensors/${activationId}`);
    });
  }, [projectId, socket]);
  const handleActivateDialogClose = useCallback(() => setActivateDialogOpen(false), []);
  if (activations === undefined) {
    return <div>Loading...</div>;
  } else {
    return (
      <div className="py-2">
        <div className="flex items-center mt-4 p-1 pl-4">
          <h2 className="flex-1 font-bold uppercase text-gray-500 text-sm">Sensors</h2>
          <button className="bg-gray-500 bg-opacity-10 hover:bg-opacity-20 w-7 h-7 rounded text-lg text-gray-500" onClick={handleActivateClick}>+</button>
          <ActivateSensorDialog open={activateDialogOpen} activating={activating} onActivate={handleActivate} onClose={handleActivateDialogClose} />
        </div>
        {Object.keys(activations).length ? (
          <ul>
            {Object.entries(activations).map(([activationId, activation]) => (
              <li key={activationId}>
                <Link href={`/projects/${projectId}/sensors/${activationId}`}>
                  <a className={classNames('block hover:bg-gray-300 px-4 py-2', { 'bg-gray-300': activationId == activeSensorId })}>
                    <div className="font-mono">{activation.target}</div>
                    <div className="text-sm text-gray-500">{activation.repository}</div>
                  </a>
                </Link>
              </li>
            ))}
          </ul>
        ) : (
          <p className="px-4 text-gray-400 italic">No active sensors</p>
        )}
      </div>
    );
  }
}
