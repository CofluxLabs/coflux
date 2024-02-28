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
import Loading from "../components/Loading";
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

type CodeBlockProps = {
  code: string;
};

function CodeBlock({ code }: CodeBlockProps) {
  return (
    <code className="block whitespace-pre bg-white shadow-inner rounded-md p-2 my-1">
      {code}
    </code>
  );
}

function generatePackageName(projectName: string | undefined) {
  return projectName?.replace(/[^a-zA-Z0-9_]/g, "") || "my_package";
}

type OutletContext = {
  setActiveTarget: (target: Target | undefined) => void;
};

export default function ProjectLayout() {
  const { project: projectId } = useParams();
  const [searchParams] = useSearchParams();
  const navigate = useNavigate();
  const environmentName = searchParams.get("environment") || undefined;
  const [activeTarget, setActiveTarget] = useState<Target>();
  const [projects] = useTopic<Record<string, models.Project>>("projects");
  const [repositories] = useTopic<Record<string, models.Repository>>(
    "projects",
    projectId,
    "environments",
    environmentName,
    "repositories",
  );
  const [agents] = useTopic<Record<string, Record<string, string[]>>>(
    "projects",
    projectId,
    "environments",
    environmentName,
    "agents",
  );
  const currentEnvironment = searchParams.get("environment") || undefined;
  const project = (projectId && projects && projects[projectId]) || undefined;
  const defaultEnvironment = project?.environments[0];
  useEffect(() => {
    if (projectId && !currentEnvironment && defaultEnvironment) {
      // TODO: retain current url?
      navigate(`/projects/${projectId}?environment=${defaultEnvironment}`, {
        replace: true,
      });
    }
  }, [navigate, projectId, currentEnvironment, defaultEnvironment]);
  useTitlePart(
    project && environmentName && `${project.name} (${environmentName})`,
  );
  if (!repositories) {
    return <Loading />;
  } else if (!Object.keys(repositories).length) {
    const packageName = generatePackageName(project?.name);
    return (
      <div className="bg-slate-50 border border-slate-100 rounded-lg m-auto w-2/3 p-3 text-slate-600">
        <h1 className="text-3xl my-2">Your project is ready</h1>
        <p className="my-2">
          Next, connect your agent. If you don't already have one setup, here's
          what you can do:
        </p>
        <ol className="list-decimal pl-8 my-4">
          <li className="my-4">
            Install the Python client:
            <CodeBlock code="pip install coflux" />
          </li>
          <li className="my-4">
            Create a config file and initialise the Python packge:
            <CodeBlock
              code={`coflux init \\\n  --host=${window.location.host} \\\n  --project=${projectId} \\\n  --environment=${environmentName} \\\n  --repo=${packageName}.repo`}
            />
          </li>
          <li className="my-4">
            Run the agent (watching for changes):
            <CodeBlock code={`coflux agent.run ${packageName}.repo --reload`} />
          </li>
          <li className="my-4">
            Edit <code>{`${packageName}/repo.py`}</code> to add a workflow to
            your repository:
            <CodeBlock
              code={`import coflux as cf\n\n@cf.workflow()\ndef hello(name: str):\n    cf.context.log_info(f"Hello, {name}")\n    return 42`}
            />
          </li>
        </ol>
      </div>
    );
  } else {
    return (
      <div className="flex-auto flex overflow-hidden">
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
        <div className="flex-1 flex flex-col">
          <Outlet context={{ setActiveTarget }} />
        </div>
      </div>
    );
  }
}

export function useSetActiveTarget(target: Target | undefined) {
  const { setActiveTarget } = useOutletContext<OutletContext>();
  useEffect(() => {
    setActiveTarget(target);
    return () => setActiveTarget(undefined);
  }, [setActiveTarget, target]);
}
