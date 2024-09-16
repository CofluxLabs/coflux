import { Fragment, useEffect, useState } from "react";
import {
  Outlet,
  useNavigate,
  useOutletContext,
  useParams,
  useSearchParams,
} from "react-router-dom";
import { useSocket } from "@topical/react";
import {
  IconAlertCircle,
  IconAlertTriangle,
  IconCircle,
  IconCircleCheck,
} from "@tabler/icons-react";
import { findKey } from "lodash";

import TargetsList from "../components/TargetsList";
import { pluralise } from "../utils";
import { useTitlePart } from "../components/TitleContext";
import {
  useAgents,
  useEnvironments,
  useProjects,
  useRepositories,
} from "../topics";

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
  setActive: (active: [string, string | undefined] | undefined) => void;
};

export default function ProjectLayout() {
  const { project: projectId } = useParams();
  const navigate = useNavigate();
  const [searchParams] = useSearchParams();
  const environmentName = searchParams.get("environment") || undefined;
  const [active, setActive] = useState<
    [string, string | undefined] | undefined
  >();
  const projects = useProjects();
  const environments = useEnvironments(projectId);
  const environmentId = findKey(
    environments,
    (e) => e.name == environmentName && e.status != 1,
  );
  const repositories = useRepositories(projectId, environmentId);
  const agents = useAgents(projectId, environmentId);
  const project = (projectId && projects && projects[projectId]) || undefined;
  const defaultEnvironmentName =
    environments &&
    Object.values(environments).find((e) => e.status != 1)?.name;
  useEffect(() => {
    if (projectId && !environmentName && defaultEnvironmentName) {
      // TODO: retain current url?
      navigate(`/projects/${projectId}?environment=${defaultEnvironmentName}`, {
        replace: true,
      });
    }
  }, [navigate, projectId, environmentName, defaultEnvironmentName]);
  useTitlePart(
    project && environmentName && `${project.name} (${environmentName})`,
  );
  return (
    <div className="flex-1 flex min-h-0">
      {repositories && (
        <div className="w-64 bg-slate-100 text-slate-100 border-r border-slate-200 flex-none flex flex-col">
          <div className="flex-1 overflow-auto min-h-0">
            <TargetsList
              projectId={projectId}
              environmentName={environmentName}
              activeRepository={active?.[0]}
              activeTarget={active?.[1]}
              repositories={repositories}
              agents={agents}
            />
          </div>
          <ConnectionStatus agents={agents} />
        </div>
      )}
      <div className="flex-1 flex flex-col min-w-0">
        <Outlet context={{ setActive }} />
      </div>
    </div>
  );
}

export function useSetActiveTarget(
  repository: string | undefined,
  target: string | undefined,
) {
  const { setActive } = useOutletContext<OutletContext>();
  useEffect(() => {
    setActive(repository ? [repository, target] : undefined);
    return () => setActive(undefined);
  }, [setActive, target]);
}
