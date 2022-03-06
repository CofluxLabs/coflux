import { Fragment, useCallback, useState } from 'react';
import { useNavigate } from 'react-router-dom';
import { useSocket } from '../hooks/useSubscription';

import * as models from '../models';
import { buildUrl } from '../utils';
import RunDialog from './RunDialog';

type Props = {
  task: models.Task;
  projectId: string;
  environmentName: string;
}

export default function RunButton({ task, projectId, environmentName }: Props) {
  const { socket } = useSocket();
  const [starting, setStarting] = useState(false);
  const [runDialogOpen, setRunDialogOpen] = useState(false);
  const navigate = useNavigate();
  const handleRunClick = useCallback(() => {
    setRunDialogOpen(true);
  }, []);
  const handleStartRun = useCallback((args) => {
    setStarting(true);
    socket?.request('start_run', [task.repository, task.target, environmentName, args], (runId) => {
      setStarting(false);
      setRunDialogOpen(false);
      navigate(buildUrl(`/projects/${projectId}/runs/${runId}`, { environment: environmentName }));
    });
  }, [projectId, task, environmentName, socket, navigate]);
  const handleRunDialogClose = useCallback(() => setRunDialogOpen(false), []);
  return (
    <Fragment>
      <button
        className="px-2 py-1 m-2 border border-slate-400 text-slate-500 rounded font-bold hover:bg-slate-100"
        onClick={handleRunClick}
      >
        Run...
      </button>
      <RunDialog
        parameters={task.parameters}
        open={runDialogOpen}
        starting={starting}
        onRun={handleStartRun}
        onClose={handleRunDialogClose}
      />
    </Fragment>
  );
}
