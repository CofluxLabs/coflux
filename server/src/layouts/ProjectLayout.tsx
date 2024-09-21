import { Fragment, useCallback, useEffect, useState } from "react";
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
  IconInfoSquareRounded,
  IconPlayerPause,
  IconPlayerPlay,
} from "@tabler/icons-react";
import { findKey } from "lodash";

import * as models from "../models";
import * as api from "../api";
import TargetsList from "../components/TargetsList";
import { pluralise } from "../utils";
import { useTitlePart } from "../components/TitleContext";
import {
  useAgents,
  useEnvironments,
  useProjects,
  useRepositories,
} from "../topics";

type PlayPauseButtonProps = {
  projectId: string;
  environmentId: string;
  environment: models.Environment;
};

function PlayPauseButton({
  projectId,
  environmentId,
  environment,
}: PlayPauseButtonProps) {
  const { status } = environment;
  const handleClick = useCallback(() => {
    // TODO: handle error
    if (status == 0) {
      api.pauseEnvironment(projectId, environmentId);
    } else if (status == 1) {
      api.resumeEnvironment(projectId, environmentId);
    }
  }, [environmentId, status]);
  return status == 0 ? (
    <button
      className="text-slate-700 bg-slate-200 rounded p-0.5 hover:bg-slate-300/60"
      title="Pause environment"
      onClick={handleClick}
    >
      <IconPlayerPause strokeWidth={1.5} size={20} />
    </button>
  ) : status == 1 ? (
    <button
      className="text-slate-700 bg-slate-200 rounded p-0.5 animate-pulse hover:bg-slate-300/60"
      title="Resume environment"
      onClick={handleClick}
    >
      <IconPlayerPlay strokeWidth={1.5} size={20} />
    </button>
  ) : null;
}

type ConnectionStatusProps = {
  projectId: string;
  environmentId: string | undefined;
  agents: Record<string, Record<string, string[]>> | undefined;
  environment: models.Environment | undefined;
};

function ConnectionStatus({
  projectId,
  agents,
  environmentId,
  environment,
}: ConnectionStatusProps) {
  const [_socket, status] = useSocket();
  const count = agents && Object.keys(agents).length;
  return (
    <div className="p-3 flex items-center border-t border-slate-200">
      <span className="ml-1 text-slate-700 flex-1 flex items-center gap-1 text-sm">
        {status == "connecting" ? (
          <Fragment>Connecting...</Fragment>
        ) : status == "connected" ? (
          count ? (
            <Fragment>
              <IconCircleCheck size={18} className="text-green-500" />
              {pluralise(count, "agent")} online
            </Fragment>
          ) : agents ? (
            <Fragment>
              <IconAlertCircle size={18} className="text-slate-500" />
              No agents online
            </Fragment>
          ) : (
            <Fragment>
              <IconCircle size={18} className="text-slate-500" />
              Connected
            </Fragment>
          )
        ) : (
          <Fragment>
            <IconAlertTriangle size={18} className="text-yellow-500" />
            Disconnected
          </Fragment>
        )}
      </span>
      {environmentId && environment && (
        <PlayPauseButton
          projectId={projectId}
          environmentId={environmentId}
          environment={environment}
        />
      )}
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
    (e) => e.name == environmentName && e.status != 2,
  );
  const environment = environmentId ? environments?.[environmentId] : undefined;
  const repositories = useRepositories(projectId, environmentId);
  const agents = useAgents(projectId, environmentId);
  const project = (projectId && projects && projects[projectId]) || undefined;
  const defaultEnvironmentName =
    environments &&
    Object.values(environments).find((e) => e.status != 2)?.name;
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
          {Object.keys(repositories).length ? (
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
          ) : (
            <div className="flex-1 flex flex-col gap-1 justify-center items-center">
              <IconInfoSquareRounded
                size={32}
                strokeWidth={1.5}
                className="text-slate-300/50"
              />
              <p className="text-slate-300 text-lg px-2 max-w-48 text-center leading-tight">
                No repositories registered
              </p>
            </div>
          )}
          <ConnectionStatus
            projectId={projectId!}
            environmentId={environmentId}
            agents={agents}
            environment={environment}
          />
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
