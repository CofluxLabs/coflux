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
  IconLayoutSidebarLeftCollapse,
  IconPackage,
  IconPlayerPause,
  IconPlayerPlay,
  IconServer,
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
import Header from "../components/Header";
import { Transition } from "@headlessui/react";
import classNames from "classnames";

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
    if (status == "active") {
      api.pauseEnvironment(projectId, environmentId);
    } else if (status == "paused") {
      api.resumeEnvironment(projectId, environmentId);
    }
  }, [environmentId, status]);
  return status == "active" ? (
    <button
      className="text-slate-700 bg-slate-200 rounded p-0.5 hover:bg-slate-300/60"
      title="Pause environment"
      onClick={handleClick}
    >
      <IconPlayerPause strokeWidth={1.5} size={20} />
    </button>
  ) : status == "paused" ? (
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

type SidebarProps = {
  projectId: string;
  environmentName: string;
  active: [string, string | undefined] | undefined;
};

function Sidebar({ projectId, environmentName, active }: SidebarProps) {
  const [hidden, setHidden] = useState(false);
  const [tab, setTab] = useState<"repositories" | "pools">("repositories");
  const environments = useEnvironments(projectId);
  const environmentId = findKey(
    environments,
    (e) => e.name == environmentName && e.status != "archived",
  );
  const environment = environmentId ? environments?.[environmentId] : undefined;
  const repositories = useRepositories(projectId, environmentId);
  const agents = useAgents(projectId, environmentId);
  const handleRepositoriesClick = useCallback(() => setTab("repositories"), []);
  const handlePoolsClick = useCallback(() => setTab("pools"), []);
  const handleHideClick = useCallback(() => setHidden(true), []);
  return (
    <Transition
      as={Fragment}
      show={!hidden}
      leave="transform transition ease-in-out duration-150"
      leaveFrom="translate-x-0"
      leaveTo="-translate-x-full"
    >
      <div className="w-72 bg-slate-100 text-slate-400 border-r border-slate-200 flex-none flex flex-col">
        <div className="flex-1 flex flex-col min-h-0">
          <div className="flex p-3 gap-2 border-b border-slate-200">
            <div className="flex-1 flex gap-1">
              <button
                className={classNames(
                  "p-1 rounded-md",
                  tab == "repositories"
                    ? "bg-slate-200 text-slate-700"
                    : "text-slate-500 hover:text-slate-700",
                )}
                title="Repositories"
                onClick={handleRepositoriesClick}
              >
                <IconPackage size={24} strokeWidth={1.5} />
              </button>
              <button
                className={classNames(
                  "p-1 rounded-md",
                  tab == "pools"
                    ? "bg-slate-200 text-slate-700"
                    : "text-slate-500 hover:text-slate-700",
                )}
                title="Pools"
                onClick={handlePoolsClick}
              >
                <IconServer size={24} strokeWidth={1.5} />
              </button>
            </div>
            <button
              className="p-1 rounded-md hover:text-slate-700"
              title="Hide sidebar"
              onClick={handleHideClick}
            >
              <IconLayoutSidebarLeftCollapse size={24} strokeWidth={1.5} />
            </button>
          </div>
          <div className="flex-1 flex flex-col min-h-0">
            {tab == "repositories" ? (
              <>
                {repositories && Object.keys(repositories).length ? (
                  <div className="flex-1 overflow-auto min-h-0">
                    <TargetsList
                      projectId={projectId!}
                      environmentName={environmentName!}
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
              </>
            ) : tab == "pools" ? (
              <></>
            ) : null}
          </div>
        </div>
        <ConnectionStatus
          projectId={projectId!}
          environmentId={environmentId}
          agents={agents}
          environment={environment}
        />
      </div>
    </Transition>
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
  const project = (projectId && projects && projects[projectId]) || undefined;
  const defaultEnvironmentName =
    environments &&
    Object.values(environments).find((e) => e.status != "archived")?.name;
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
    <Fragment>
      <Header projectId={projectId!} activeEnvironmentName={environmentName} />
      <div className="flex-1 flex min-h-0 bg-white lg:rounded-md overflow-hidden">
        <Sidebar
          projectId={projectId!}
          environmentName={environmentName!}
          active={active}
        />
        <div className="flex-1 flex flex-col min-w-0">
          <Outlet context={{ setActive }} />
        </div>
      </div>
    </Fragment>
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
  }, [setActive, repository, target]);
}
