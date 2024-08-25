import { useMemo } from "react";
import { useTopic } from "@topical/react";
import { useParams, useSearchParams } from "react-router-dom";
import classNames from "classnames";

import * as models from "../models";
import { randomName } from "../utils";
import CodeBlock from "../components/CodeBlock";

function generatePackageName(projectName: string | undefined) {
  return projectName?.replace(/[^a-z0-9_]/gi, "").toLowerCase() || "my_package";
}

type GettingStartedProps = {
  projectId: string;
  environmentName: string | undefined;
};

function GettingStarted({ projectId, environmentName }: GettingStartedProps) {
  const [projects] = useTopic<Record<string, models.Project>>("projects");
  const [agents] = useTopic<Record<string, Record<string, string[]>>>(
    "projects",
    projectId,
    "agents",
    environmentName,
  );
  const project = (projectId && projects && projects[projectId]) || undefined;
  const packageName = generatePackageName(project?.name);
  const exampleEnvironmentName = useMemo(() => randomName(), []);
  const exampleRepositoryName = `${packageName}.repo`;
  const agentConnected = agents && Object.keys(agents).length > 0;
  return (
    <div className="bg-slate-50 border border-slate-100 rounded-lg m-auto w-2/3 p-3 text-slate-600">
      <h1 className="text-3xl my-2">Your project is ready</h1>
      <p className="my-2">
        Follow these steps to setup an environment and repository:
      </p>
      <ol className="list-decimal pl-8 my-4">
        <li
          className={classNames(
            "my-4",
            environmentName && "line-through text-slate-400",
          )}
        >
          Install the CLI:
          <CodeBlock className="bg-white" code={["pip install coflux"]} />
        </li>
        <li
          className={classNames(
            "my-4",
            environmentName && "line-through text-slate-400",
          )}
        >
          Use the CLI to populate the configuration file:
          <CodeBlock
            className="bg-white"
            code={[
              "coflux configure \\",
              `  --host=${window.location.host} \\`,
              `  --project=${projectId} \\`,
              `  --environment=${environmentName || exampleEnvironmentName}`,
            ]}
          />
          <span className="text-sm">
            This will create a configuration file at{" "}
            <code className="text-xs">coflux.yaml</code>.
          </span>
        </li>
        <li
          className={classNames(
            "my-4",
            environmentName && "line-through text-slate-400",
          )}
        >
          Register an environment with the server, using the CLI:
          <CodeBlock
            className="bg-white"
            code={["coflux environment.register"]}
          />
          <span className="text-sm">
            This will create an empty environment file for the environment
            configured in the previous step, at{" "}
            <code className="text-xs">
              environments/{environmentName || exampleEnvironmentName}.yaml
            </code>
            , which can be edited and re-registered as needed.
          </span>
        </li>
        <li
          className={classNames(
            "my-4",
            agentConnected && "line-through text-slate-400",
          )}
        >
          Initalise an empty repository:
          <CodeBlock
            className="bg-white"
            code={[`mkdir -p ${packageName}`, `touch ${packageName}/repo.py`]}
          />
        </li>
        <li
          className={classNames(
            "my-4",
            agentConnected && "line-through text-slate-400",
          )}
        >
          Run the agent (watching for changes to the repository):
          <CodeBlock
            className="bg-white"
            code={[`coflux agent.run ${exampleRepositoryName} --reload`]}
          />
        </li>
        <li className="my-4">
          Edit <code className="text-sm">{`${packageName}/repo.py`}</code> to
          add a workflow to your repository:
          <CodeBlock
            className="bg-white"
            code={[
              "import coflux as cf",
              "",
              "@cf.workflow()",
              "def hello(name: str):",
              '    cf.log_info("Hello, {name}", name=name)',
              "    return 42",
            ]}
          />
        </li>
      </ol>
    </div>
  );
}

export default function ProjectPage() {
  const { project: projectId } = useParams();
  const [searchParams] = useSearchParams();
  const environmentName = searchParams.get("environment") || undefined;
  const [repositories] = useTopic<Record<string, models.Repository>>(
    "projects",
    projectId,
    "repositories",
    environmentName,
  );
  if (
    projectId &&
    (!environmentName ||
      (repositories &&
        !Object.values(repositories).some(
          (r) => Object.keys(r.targets).length,
        )))
  ) {
    return (
      <GettingStarted projectId={projectId} environmentName={environmentName} />
    );
  } else {
    return <div></div>;
  }
}
