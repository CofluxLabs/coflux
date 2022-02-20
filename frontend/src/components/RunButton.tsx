import { Fragment, useCallback, useState } from 'react';
import Router from 'next/router';

import useSocket from '../hooks/useSocket';
import RunDialog from './RunDialog';

type Props = {
  projectId: string;
  repository: string;
  target: string;
  environmentName: string;
}

export default function RunButton({ projectId, repository, target, environmentName }: Props) {
  const { socket } = useSocket();
  const [starting, setStarting] = useState(false);
  const [runDialogOpen, setRunDialogOpen] = useState(false);
  const handleRunClick = useCallback(() => {
    setRunDialogOpen(true);
  }, []);
  const handleStartRun = useCallback((args) => {
    setStarting(true);
    socket?.request('start_run', [repository, target, environmentName, args], (runId) => {
      setStarting(false);
      setRunDialogOpen(false);
      Router.push(`/projects/${projectId}/runs/${runId}`);
    });
  }, [projectId, repository, target, environmentName, socket]);
  const handleRunDialogClose = useCallback(() => setRunDialogOpen(false), []);
  return (
    <Fragment>
      <button
        className="px-2 py-1 m-2 border border-blue-400 text-blue-500 rounded font-bold hover:bg-blue-100"
        onClick={handleRunClick}
      >
        Run...
      </button>
      <RunDialog
        repository={repository}
        target={target}
        environmentName={environmentName}
        open={runDialogOpen}
        starting={starting}
        onRun={handleStartRun}
        onClose={handleRunDialogClose}
      />
    </Fragment>
  );
}
