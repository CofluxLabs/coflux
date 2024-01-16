import { Fragment } from "react";
import { Outlet, useParams } from "react-router-dom";
import { SocketProvider, useTopic } from "@topical/react";
import { IconChevronCompactRight } from "@tabler/icons-react";

import EnvironmentSelector from "../components/EnvironmentSelector";
import Logo from "../components/Logo";
import ProjectSelector from "../components/ProjectSelector";
import * as models from "../models";

type HeaderProps = {
  projectId: string | undefined;
};

function Header({ projectId }: HeaderProps) {
  const [projects] = useTopic<Record<string, models.Project>>("projects");
  return (
    <div className="flex px-3 items-center h-14 flex-none">
      <Logo />
      {projects && (
        <div className="flex items-center gap-1">
          <IconChevronCompactRight size={16} className="text-white/40" />
          <ProjectSelector projects={projects} />
          {projectId && projects[projectId] && (
            <Fragment>
              <IconChevronCompactRight size={16} className="text-white/40" />
              <EnvironmentSelector
                environments={projects[projectId].environments}
              />
            </Fragment>
          )}
        </div>
      )}
      <span className="flex-1"></span>
    </div>
  );
}

export default function InternalLayout() {
  const { project: projectId } = useParams();
  return (
    <SocketProvider url={`ws://${window.location.host}/topics`}>
      <div className="flex flex-col min-h-screen max-h-screen bg-cyan-600">
        <Header projectId={projectId} />
        <div className="flex-1 rounded-md overflow-hidden bg-white shadow-xl mx-2 mb-2 flex flex-col">
          <Outlet />
        </div>
      </div>
    </SocketProvider>
  );
}
