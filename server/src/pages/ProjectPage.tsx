import { useTopic } from "@topical/react";
import { useParams, useSearchParams } from "react-router-dom";

import * as models from "../models";

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
  return projectName?.replace(/[^a-z0-9_]/gi, "").toLowerCase() || "my_package";
}

type GettingStartedProps = {
  projectId: string;
  environmentName: string;
};

function GettingStarted({ projectId, environmentName }: GettingStartedProps) {
  const [projects] = useTopic<Record<string, models.Project>>("projects");
  const project = (projectId && projects && projects[projectId]) || undefined;
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
          Edit <code>{`${packageName}/repo.py`}</code> to add a workflow to your
          repository:
          <CodeBlock
            code={`import coflux as cf\n\n@cf.workflow()\ndef hello(name: str):\n    cf.context.log_info(f"Hello, {name}")\n    return 42`}
          />
        </li>
      </ol>
    </div>
  );
}

export default function ProjectPage() {
  const { project: projectId } = useParams();
  const [searchParams] = useSearchParams();
  const environmentName = searchParams.get("environment") || "development";
  const [repositories] = useTopic<Record<string, models.Repository>>(
    "projects",
    projectId,
    "repositories",
    environmentName,
  );
  if (projectId && repositories && !Object.keys(repositories).length) {
    return (
      <GettingStarted projectId={projectId} environmentName={environmentName} />
    );
  } else {
    return <div></div>;
  }
}
