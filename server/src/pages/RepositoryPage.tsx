import { useParams, useSearchParams } from "react-router-dom";
import { useTopic } from "@topical/react";

import * as models from "../models";
import { useTitlePart } from "../components/TitleContext";
import Loading from "../components/Loading";
import { IconBox } from "@tabler/icons-react";
import RepositoryQueue from "../components/RepositoryQueue";

export default function RepositoryPage() {
  const { project: projectId, repository: repositoryName } = useParams();
  const [searchParams] = useSearchParams();
  const environmentName = searchParams.get("environment") || undefined;
  const [executions] = useTopic<Record<string, models.QueuedExecution>>(
    "projects",
    projectId,
    "environments",
    environmentName,
    "repositories",
    repositoryName,
  );
  useTitlePart(repositoryName);
  if (!executions) {
    return <Loading />;
  } else {
    return (
      <div className="p-4">
        <div className="flex">
          <h1 className="flex items-center">
            <IconBox
              size={24}
              strokeWidth={1.5}
              className="text-slate-400 mr-1"
            />
            <span className="text-xl font-bold font-mono">
              {repositoryName}
            </span>
          </h1>
        </div>
        <RepositoryQueue
          projectId={projectId!}
          environmentName={environmentName!}
          executions={executions}
        />
      </div>
    );
  }
}
