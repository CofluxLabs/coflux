import { Outlet, useParams, useSearchParams } from "react-router-dom";
import { SocketProvider } from "@topical/react";
import { findKey } from "lodash";

import Logo from "../components/Logo";
import ProjectSelector from "../components/ProjectSelector";
import EnvironmentSelector from "../components/EnvironmentSelector";
import { useEnvironments, useProjects } from "../topics";

export default function InternalLayout() {
  const { project: projectId } = useParams();
  const [searchParams] = useSearchParams();
  const activeEnvironmentName = searchParams.get("environment") || undefined;
  return (
    <SocketProvider url={`ws://${window.location.host}/topics`}>
      <div className="flex flex-col min-h-screen max-h-screen overflow-hidden">
        <Outlet />
      </div>
    </SocketProvider>
  );
}
