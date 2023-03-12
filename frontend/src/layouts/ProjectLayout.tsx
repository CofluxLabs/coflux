import { useEffect, useState } from 'react';
import { Outlet, useOutletContext, useParams, useSearchParams } from 'react-router-dom';

import { SocketProvider, useSocket } from '@topical/react';
import EnvironmentSelector from '../components/EnvironmentSelector';
import TargetsList from '../components/TargetsList';
import Logo from '../components/Logo';
import ProjectSelector from '../components/ProjectSelector';

type Target = { repository: string, target: string };

function SocketStatus() {
  const [_socket, status] = useSocket();
  return (
    <div className="p-3 flex items-center border-t border-slate-200">
      <span className="ml-1 text-slate-700">{status}</span>
    </div>
  );
}

type OutletContext = {
  setActiveTarget: (task: Target | undefined) => void;
}

export default function ProjectLayout() {
  const { project: projectId } = useParams();
  const [searchParams] = useSearchParams();
  const environmentName = searchParams.get('environment') || undefined;
  const [activeTarget, setActiveTarget] = useState<Target>();
  return (
    <SocketProvider url="ws://localhost:7070/topics">
      <div className="flex flex-col min-h-screen max-h-screen">
        <div className="flex bg-slate-700 px-3 items-center h-14 flex-none">
          <Logo />
          <EnvironmentSelector projectId={projectId!} />
          <span className="flex-1"></span>
          <span className="text-slate-100 rounded px-3 py-1 mr-1">
            <ProjectSelector projectIds={["project_1", "project_2"]} />
          </span>
        </div>
        <div className="flex-auto flex overflow-hidden">
          <div className="w-64 bg-slate-100 text-gray-100 border-r border-slate-200 overflow-auto flex-none flex flex-col">
            <div className="flex-1">
              <TargetsList projectId={projectId} environmentName={environmentName} activeTarget={activeTarget} />
            </div>
            <SocketStatus />
          </div>
          <div className="flex-1 flex flex-col">
            <Outlet context={{ setActiveTarget }} />
          </div>
        </div>
      </div>
    </SocketProvider>
  );
}

export function useSetActiveTarget(task: Target | undefined) {
  const { setActiveTarget } = useOutletContext<OutletContext>();
  useEffect(() => {
    setActiveTarget(task);
    return () => setActiveTarget(undefined);
  }, [setActiveTarget, task]);
}