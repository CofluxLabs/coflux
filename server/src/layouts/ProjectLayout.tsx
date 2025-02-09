import { Fragment, useEffect, useState } from "react";
import {
  Outlet,
  useOutletContext,
  useParams,
  useSearchParams,
} from "react-router-dom";
import { IconInfoSquareRounded } from "@tabler/icons-react";
import { findKey } from "lodash";

import TargetsList from "../components/TargetsList";
import { useTitlePart } from "../components/TitleContext";
import {
  useEnvironments,
  usePools,
  useProjects,
  useRepositories,
  useSessions,
} from "../topics";
import Header from "../components/Header";
import AgentsList from "../components/AgentsList";

type SidebarProps = {
  projectId: string;
  environmentName: string;
  active: Active;
};

function Sidebar({ projectId, environmentName, active }: SidebarProps) {
  const environments = useEnvironments(projectId);
  const environmentId = findKey(
    environments,
    (e) => e.name == environmentName && e.state != "archived",
  );
  const repositories = useRepositories(projectId, environmentId);
  const pools = usePools(projectId, environmentId);
  const sessions = useSessions(projectId, environmentId);
  return (
    <div className="w-72 bg-slate-100 text-slate-400 border-r border-slate-200 flex-none flex flex-col">
      <div className="flex-1 flex flex-col min-h-0">
        <div className="flex-1 flex flex-col min-h-0 divide-y divide-slate-200">
          <div className="flex-1 flex flex-col overflow-auto">
            {repositories ? (
              Object.keys(repositories).length ? (
                <div className="flex-1 overflow-auto min-h-0">
                  <TargetsList
                    projectId={projectId}
                    environmentName={environmentName}
                    activeRepository={
                      active?.[0] == "repository" || active?.[0] == "target"
                        ? active?.[1]
                        : undefined
                    }
                    activeTarget={
                      active?.[0] == "target" ? active?.[2] : undefined
                    }
                    repositories={repositories}
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
                    No workflows registered
                  </p>
                </div>
              )
            ) : null}
          </div>
          <div className="flex flex-col max-h-[1/3] overflow-auto">
            <AgentsList
              pools={pools}
              projectId={projectId}
              environmentName={environmentName}
              activePool={active?.[0] == "pool" ? active?.[1] : undefined}
              sessions={sessions}
            />
          </div>
        </div>
      </div>
    </div>
  );
}

type Active =
  | ["repository", string]
  | ["target", string, string]
  | ["pool", string]
  | undefined;

type OutletContext = {
  setActive: (active: Active) => void;
};

export default function ProjectLayout() {
  const { project: projectId } = useParams();
  const [searchParams] = useSearchParams();
  const environmentName = searchParams.get("environment") || undefined;
  const [active, setActive] = useState<Active>();
  const projects = useProjects();
  const project = (projectId && projects && projects[projectId]) || undefined;
  useTitlePart(
    project && environmentName && `${project.name} (${environmentName})`,
  );
  return (
    <Fragment>
      <Header projectId={projectId!} activeEnvironmentName={environmentName} />
      <div className="flex-1 flex min-h-0 bg-white overflow-hidden">
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

export function useSetActive(active: Active) {
  const { setActive } = useOutletContext<OutletContext>();
  useEffect(() => {
    setActive(active);
    return () => setActive(undefined);
  }, [setActive, JSON.stringify(active)]);
}
