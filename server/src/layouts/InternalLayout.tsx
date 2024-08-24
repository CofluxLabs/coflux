import { Fragment } from "react";
import { Outlet, useParams } from "react-router-dom";
import { SocketProvider, useTopic } from "@topical/react";
import { IconChevronCompactRight } from "@tabler/icons-react";

import Logo from "../components/Logo";
import ProjectSelector from "../components/ProjectSelector";
import * as models from "../models";
import EnvironmentSelector from "../components/EnvironmentSelector";

type HeaderProps = {
  projectId: string | undefined;
};

function Header({ projectId }: HeaderProps) {
  const [projects] = useTopic<Record<string, models.Project>>("projects");
  const [environments] = useTopic<Record<string, models.Environment>>(
    "projects",
    projectId,
    "environments",
  );
  return (
    <div className="flex p-3 items-center bg-cyan-600 gap-1">
      <Logo />
      {projects && (
        <Fragment>
          <IconChevronCompactRight size={16} className="text-white/40" />
          <div className="flex items-center gap-2">
            <ProjectSelector projects={projects} />
            {environments && Object.keys(environments).length > 0 && (
              <EnvironmentSelector environments={environments} />
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
  return (
    <SocketProvider url={`ws://${window.location.host}/topics`}>
      <div className="flex flex-col min-h-screen max-h-screen">
        <Header projectId={projectId} />
        <div className="flex-1 overflow-hidden bg-white flex flex-col">
          <Outlet />
        </div>
      </div>
    </SocketProvider>
  );
}
