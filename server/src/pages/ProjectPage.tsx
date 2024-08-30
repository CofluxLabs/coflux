import { ReactNode, useMemo } from "react";
import { useParams, useSearchParams } from "react-router-dom";
import classNames from "classnames";
import { findKey } from "lodash";

import { randomName } from "../utils";
import CodeBlock from "../components/CodeBlock";
import {
  useAgents,
  useEnvironments,
  useProjects,
  useRepositories,
} from "../topics";
import { Disclosure } from "@headlessui/react";
import { IconChevronDown, IconInfoCircle } from "@tabler/icons-react";

function generatePackageName(projectName: string | undefined) {
  return projectName?.replace(/[^a-z0-9_]/gi, "").toLowerCase() || "my_package";
}

type HintProps = {
  children: ReactNode;
};

function Hint({ children }: HintProps) {
  return (
    <div className="text-sm flex gap-1 text-slate-400 mb-2">
      <IconInfoCircle size={16} className="mt-0.5" />
      {children}
    </div>
  );
}

type StepProps = {
  title: string;
  children: ReactNode;
};

function Step({ title, children }: StepProps) {
  return (
    <Disclosure as="li" className="my-4" defaultOpen={true}>
      {({ open }) => (
        <div className="flex flex-col">
          <Disclosure.Button className="text-left flex items-center gap-1">
            {title}
            <IconChevronDown
              size={16}
              className={classNames("text-slate-400", open && "rotate-180")}
            />
          </Disclosure.Button>
          <Disclosure.Panel>{children}</Disclosure.Panel>
        </div>
      )}
    </Disclosure>
  );
}

type GettingStartedProps = {
  projectId: string;
  environmentId: string | undefined;
};

function GettingStarted({ projectId, environmentId }: GettingStartedProps) {
  const projects = useProjects();
  const agents = useAgents(projectId, environmentId);
  const project = (projectId && projects && projects[projectId]) || undefined;
  const packageName = generatePackageName(project?.name);
  const environments = useEnvironments(projectId);
  const environmentName = environmentId && environments?.[environmentId].name;
  const exampleEnvironmentName = useMemo(() => randomName(), []);
  const exampleRepositoryName = `${packageName}.repo`;
  const agentConnected = agents && Object.keys(agents).length > 0;
  if (environments && Object.keys(environments).length > 0) {
    return (
      <div className="overflow-auto">
        <div className="bg-slate-50 border border-slate-100 rounded-lg mx-auto my-6 w-2/3 p-3 text-slate-600">
          <h1 className="text-3xl my-2">Your project is ready</h1>
          <p className="my-2">
            Follow these steps to create your first workflow:
          </p>
          <ol className="list-decimal pl-8 my-5">
            <Step title="Install the CLI">
              <CodeBlock
                className="bg-slate-100"
                prompt="$"
                code={["pip install coflux"]}
              />
            </Step>
            <Step title="Populate the configuration file">
              <CodeBlock
                className="bg-slate-100"
                prompt="$"
                code={[
                  `coflux configure \\\n  --host=${window.location.host} \\\n  --project=${projectId} \\\n  --environment=${environmentName || exampleEnvironmentName}`,
                ]}
              />
              <Hint>
                <p>
                  This will create a configuration file at{" "}
                  <code className="bg-slate-100">coflux.yaml</code>.
                </p>
              </Hint>
            </Step>
            <Step title="Initialise an empty repository">
              <CodeBlock
                className="bg-slate-100"
                prompt="$"
                code={[
                  `mkdir -p ${packageName}`,
                  `touch ${packageName}/__init__.py`,
                  `touch ${packageName}/repo.py`,
                ]}
              />
            </Step>
            <Step title="Run the agent">
              <CodeBlock
                className="bg-slate-100"
                prompt="$"
                code={[`coflux agent.run ${exampleRepositoryName} --reload`]}
              />
              <Hint>
                <p>
                  The <code className="bg-slate-100">--reload</code> flag means
                  that the agent will automatically restart when changes to the
                  source code are detected.
                </p>
              </Hint>
            </Step>
            <Step title="Add a workflow to your repository">
              <CodeBlock
                header={`${packageName}/repo.py`}
                className="bg-slate-100"
                code={[
                  "import coflux as cf",
                  "",
                  "@cf.workflow()",
                  "def hello(name: str):",
                  '    cf.log_info("Hello, {name}", name=name)',
                  "    return 42",
                ]}
              />
              <Hint>
                <p>
                  When you save the file, the workspace will automatically
                  appear in the sidebar.
                </p>
              </Hint>
            </Step>
          </ol>
        </div>
      </div>
    );
  } else {
    return null;
  }
}

export default function ProjectPage() {
  const { project: projectId } = useParams();
  const [searchParams] = useSearchParams();
  const environmentName = searchParams.get("environment") || undefined;
  const environments = useEnvironments(projectId);
  const environmentId = findKey(
    environments,
    (e) => e.name == environmentName && e.status != 1,
  );
  const repositories = useRepositories(projectId, environmentId);
  if (
    projectId &&
    (!environmentName ||
      (repositories &&
        !Object.values(repositories).some(
          (r) => Object.keys(r.targets).length,
        )))
  ) {
    return (
      <GettingStarted projectId={projectId} environmentId={environmentId} />
    );
  } else {
    return <div></div>;
  }
}
