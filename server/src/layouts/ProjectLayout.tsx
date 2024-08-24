import { Fragment, useEffect, useState } from "react";
import {
  Outlet,
  useNavigate,
  useOutletContext,
  useParams,
  useSearchParams,
} from "react-router-dom";
import { useSocket, useTopic } from "@topical/react";
import {
  IconAlertCircle,
  IconAlertTriangle,
  IconCircle,
  IconCircleCheck,
} from "@tabler/icons-react";

import * as models from "../models";
import TargetsList from "../components/TargetsList";
import { pluralise } from "../utils";
import { useTitlePart } from "../components/TitleContext";

type Target = { repository: string; target: string | null };

type ConnectionStatusProps = {
  agents: Record<string, Record<string, string[]>> | undefined;
};

function ConnectionStatus({ agents }: ConnectionStatusProps) {
  const [_socket, status] = useSocket();
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

type OutletContext = {
  setActiveTarget: (target: Target | undefined) => void;
};

export default function ProjectLayout() {
  const { project: projectId } = useParams();
  const navigate = useNavigate();
  const [searchParams] = useSearchParams();
  const environmentName = searchParams.get("environment") || undefined;
  const [activeTarget, setActiveTarget] = useState<Target>();
  const [projects] = useTopic<Record<string, models.Project>>("projects");
  const [environments] = useTopic<Record<string, models.Repository>>(
    "projects",
    projectId,
    "environments",
  );
  const [repositories] = useTopic<Record<string, models.Repository>>(
    "projects",
    projectId,
    "repositories",
    environmentName,
  );
  const [agents] = useTopic<Record<string, Record<string, string[]>>>(
    "projects",
    projectId,
    "agents",
    environmentName,
  );
  const project = (projectId && projects && projects[projectId]) || undefined;
  const defaultEnvironment = environments && Object.keys(environments)[0];
  useEffect(() => {
    if (projectId && !environmentName && defaultEnvironment) {
      // TODO: retain current url?
      navigate(`/projects/${projectId}?environment=${defaultEnvironment}`, {
        replace: true,
      });
    }
  }, [navigate, projectId, environmentName, defaultEnvironment]);
  useTitlePart(
    project && environmentName && `${project.name} (${environmentName})`,
  );
  return (
    <div className="flex-auto flex overflow-hidden">
      {repositories && (
        <div className="w-64 bg-slate-100 text-slate-100 border-r border-slate-200 flex-none flex flex-col">
          <div className="flex-1 overflow-auto">
            <TargetsList
              projectId={projectId}
              environmentName={environmentName}
              activeTarget={activeTarget}
              repositories={repositories}
              agents={agents}
            />
          </div>
          <ConnectionStatus agents={agents} />
        </div>
      )}
      <div className="flex-1 flex flex-col">
        <Outlet context={{ setActiveTarget }} />
      </div>
    </div>
  );
}

export function useSetActiveTarget(target: Target | undefined) {
  const { setActiveTarget } = useOutletContext<OutletContext>();
  useEffect(() => {
    setActiveTarget(target);
    return () => setActiveTarget(undefined);
  }, [setActiveTarget, target]);
}
