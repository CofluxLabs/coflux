import { useMemo } from "react";
import { useTopic } from "@topical/react";
import { useParams, useSearchParams } from "react-router-dom";
import classNames from "classnames";

import * as models from "../models";
import { choose } from "../utils";

type CodeBlockProps = {
  code: string[];
};

function CodeBlock({ code }: CodeBlockProps) {
  return (
    <code className="block whitespace-pre bg-white shadow-inner rounded-md p-2 my-2 text-sm">
      {code.join("\n")}
    </code>
  );
}
const adjectives = [
  "bewitching",
  "captivating",
  "charming",
  "clever",
  "enchanting",
  "funny",
  "goofy",
  "happy",
  "jolly",
  "lucky",
  "majestic",
  "mysterious",
  "mystical",
  "playful",
  "quirky",
  "silly",
  "sleepy",
  "soothing",
  "whimsical",
  "witty",
  "zany",
];

const properNames = [
  "banshee",
  "centaur",
  "chimera",
  "chupacabra",
  "cyclops",
  "djinn",
  "dragon",
  "fairy",
  "gargoyle",
  "genie",
  "gnome",
  "goblin",
  "griffin",
  "grizzly",
  "gryphon",
  "hydra",
  "kraken",
  "leprechaun",
  "mermaid",
  "minotaur",
  "mothman",
  "nymph",
  "ogre",
  "oracle",
  "pegasus",
  "phantom",
  "phoenix",
  "pixie",
  "sasquatch",
  "satyr",
  "shapeshifter",
  "siren",
  "sorcerer",
  "spectre",
  "sphinx",
  "troll",
  "unicorn",
  "vampire",
  "warlock",
  "werewolf",
  "wizard",
  "yeti",
];

function randomEnvironmentName(): string {
  return `${choose(adjectives)}_${choose(properNames)}`;
}

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
  const exampleEnvironmentName = useMemo(() => randomEnvironmentName(), []);
  const exampleRepositoryName = `${packageName}.repo`;
  const agentConnected = agents && Object.keys(agents).length > 0;
  return (
    <div className="bg-slate-50 border border-slate-100 rounded-lg m-auto w-2/3 p-3 text-slate-600">
      <h1 className="text-3xl my-2">Your project is ready</h1>
      <p className="my-2">Next, define an environment using the CLI.</p>
      <ol className="list-decimal pl-8 my-4">
        <li
          className={classNames(
            "my-4",
            environmentName && "line-through text-slate-400",
          )}
        >
          Install the CLI:
          <CodeBlock code={["pip install coflux"]} />
        </li>
        <li
          className={classNames(
            "my-4",
            environmentName && "line-through text-slate-400",
          )}
        >
          Register an environment with the server, using the CLI:
          <CodeBlock
            code={[
              "coflux environment.define \\",
              `  --host=${window.location.host} \\`,
              `  --project=${projectId} \\`,
              `  ${environmentName || exampleEnvironmentName}`,
            ]}
          />
          <span className="text-sm">
            This will create an empty configuration file at{" "}
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
            code={[`mkdir -p ${packageName}`, `touch ${packageName}/repo.py`]}
          />
        </li>
        <li
          className={classNames(
            "my-4",
            agentConnected && "line-through text-slate-400",
          )}
        >
          Run the agent (watching for changes):
          <CodeBlock
            code={[
              `coflux agent.run \\`,
              `  --host=${window.location.host} \\`,
              `  --project=${projectId} \\`,
              `  --environment=${environmentName || exampleEnvironmentName} \\`,
              `  ${exampleRepositoryName} --reload`,
            ]}
          />
        </li>
        <li className="my-4">
          Edit <code className="text-sm">{`${packageName}/repo.py`}</code> to
          add a workflow to your repository:
          <CodeBlock
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
