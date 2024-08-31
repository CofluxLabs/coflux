import { Fragment } from "react";
import { Outlet, useParams, useSearchParams } from "react-router-dom";
import { SocketProvider } from "@topical/react";
import { IconChevronCompactRight } from "@tabler/icons-react";
import { findKey } from "lodash";

import Logo from "../components/Logo";
import ProjectSelector from "../components/ProjectSelector";
import EnvironmentSelector from "../components/EnvironmentSelector";
import { useEnvironments, useProjects } from "../topics";

type HeaderProps = {
  projectId: string;
  activeEnvironmentName: string | undefined;
};

function Header({ projectId, activeEnvironmentName }: HeaderProps) {
  const projects = useProjects();
  const environments = useEnvironments(projectId);
  const activeEnvironmentId = findKey(
    environments,
    (e) => e.name == activeEnvironmentName && e.status != 1,
  );
  return (
    <div className="flex p-3 items-center bg-cyan-600 gap-1">
      <Logo />
      {projects && (
        <Fragment>
          <IconChevronCompactRight size={16} className="text-white/40" />
          <div className="flex items-center gap-2">
            <ProjectSelector projects={projects} />
            {environments && (
              <EnvironmentSelector
                projectId={projectId}
                environments={environments}
                activeEnvironmentId={activeEnvironmentId}
              />
            )}
          </div>
        </Fragment>
      )}
      <span className="flex-1"></span>
    </div>
  );
}

export default function InternalLayout() {
  const { project: projectId } = useParams();
  const [searchParams] = useSearchParams();
  const activeEnvironmentName = searchParams.get("environment") || undefined;
  return (
    <SocketProvider url={`ws://${window.location.host}/topics`}>
      <div className="flex flex-col min-h-screen max-h-screen">
        <Header
          projectId={projectId!}
          activeEnvironmentName={activeEnvironmentName}
        />
        <div className="flex-1 overflow-hidden bg-white flex flex-col">
          <Outlet />
        </div>
      </div>
    </SocketProvider>
  );
}
