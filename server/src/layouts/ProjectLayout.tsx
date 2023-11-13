import { Fragment, useEffect, useState } from "react";
import {
  Outlet,
  useOutletContext,
  useParams,
  useSearchParams,
} from "react-router-dom";
import { SocketProvider, useSocket, useTopic } from "@topical/react";
import {
  IconAlertCircle,
  IconAlertTriangle,
  IconCircle,
  IconCircleCheck,
} from "@tabler/icons-react";

import EnvironmentSelector from "../components/EnvironmentSelector";
import TargetsList from "../components/TargetsList";
import Logo from "../components/Logo";
import ProjectSelector from "../components/ProjectSelector";
import * as models from "../models";
import { pluralise } from "../utils";

type Target = { repository: string; target: string };

type ConnectionStatusProps = {
  projectId: string | undefined;
  environmentName: string | undefined;
};

function ConnectionStatus({
  projectId,
  environmentName,
}: ConnectionStatusProps) {
  const [_socket, status] = useSocket();
  const [agents] = useTopic<Record<string, Record<string, string[]>>>(
    "projects",
    projectId,
    "environments",
    environmentName,
    "agents"
  );
  const count = agents && Object.keys(agents).length;
  return (
    <div className="p-3 flex items-center border-t border-slate-200">
      <span className="ml-1 text-slate-700 flex flex items-center gap-1">
        {status == "connecting" ? (
          <Fragment>Connecting...</Fragment>
        ) : status == "connected" ? (
          count ? (
            <Fragment>
              <IconCircleCheck size={20} className="text-green-500" />
              {pluralise(count, "agent")} online
            </Fragment>
          ) : agents ? (
            <Fragment>
              <IconAlertCircle size={20} className="text-slate-500" />
              No agents online
            </Fragment>
          ) : (
            <Fragment>
              <IconCircle size={20} className="text-slate-500" />
              Connected
            </Fragment>
          )
        ) : (
          <Fragment>
            <IconAlertTriangle size={20} className="text-yellow-500" />
            Disconnected
          </Fragment>
        )}
      </span>
    </div>
  );
}

type HeaderProps = {
  projectId: string | undefined;
};

function Header({ projectId }: HeaderProps) {
  const [projects] = useTopic<Record<string, models.Project>>("projects");
  return (
    <div className="flex bg-slate-700 px-3 items-center h-14 flex-none">
      <Logo />
      {projects && (
        <Fragment>
          <ProjectSelector projectIds={Object.keys(projects)} />
          {projectId && projects[projectId] && (
            <Fragment>
              <span className="text-slate-500 px-1">/</span>
              <EnvironmentSelector
                environments={projects[projectId].environments}
              />
            </Fragment>
          )}
        </Fragment>
      )}
      <span className="flex-1"></span>
    </div>
  );
}

type OutletContext = {
  setActiveTarget: (task: Target | undefined) => void;
};

export default function ProjectLayout() {
  const { project: projectId } = useParams();
  const [searchParams] = useSearchParams();
  const environmentName = searchParams.get("environment") || undefined;
  const [activeTarget, setActiveTarget] = useState<Target>();
  return (
    <SocketProvider url={`ws://${window.location.host}/topics`}>
      <div className="flex flex-col min-h-screen max-h-screen">
        <Header projectId={projectId} />
        <div className="flex-auto flex overflow-hidden">
          <div className="w-64 bg-slate-100 text-gray-100 border-r border-slate-200 flex-none flex flex-col">
            <div className="flex-1 overflow-auto">
              <TargetsList
                projectId={projectId}
                environmentName={environmentName}
                activeTarget={activeTarget}
              />
            </div>
            <ConnectionStatus
              projectId={projectId}
              environmentName={environmentName}
            />
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
