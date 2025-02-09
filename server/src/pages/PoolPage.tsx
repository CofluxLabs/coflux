import { useCallback } from "react";
import { useParams, useSearchParams } from "react-router-dom";
import { useEnvironments, usePool } from "../topics";
import { findKey, sortBy, omitBy } from "lodash";
import { useSetActive } from "../layouts/ProjectLayout";
import { IconLayoutGrid, IconBrandDocker } from "@tabler/icons-react";
import TagSet from "../components/TagSet";
import Loading from "../components/Loading";
import Badge from "../components/Badge";
import Button from "../components/common/Button";
import * as models from "../models";
import * as api from "../api";
import { DateTime } from "luxon";

type AgentRowProps = {
  projectId: string;
  environmentName: string;
  agentId: string;
  agent: models.Agent;
};

function AgentRow({
  projectId,
  environmentName,
  agentId,
  agent,
}: AgentRowProps) {
  const handleStopClick = useCallback(() => {
    api.stopAgent(projectId, environmentName, agentId).catch(() => {
      alert("Failed to stop agent. Please try again.");
    });
  }, [projectId, environmentName, agentId]);
  const handleResumeClick = useCallback(() => {
    api.resumeAgent(projectId, environmentName, agentId).catch(() => {
      alert("Failed to resume agent. Please try again.");
    });
  }, []);
  const startingAt = DateTime.fromMillis(agent.startingAt);
  return (
    <tr className="border-b border-slate-100">
      <td>{startingAt.toLocaleString(DateTime.DATETIME_SHORT_WITH_SECONDS)}</td>
      <td>
        {agent.startError ? (
          <Badge intent="danger" label="Start error" />
        ) : agent.stopError ? (
          <Badge intent="danger" label="Stop error" />
        ) : !agent.startedAt && !agent.deactivatedAt ? (
          <Badge intent="info" label="Starting..." />
        ) : agent.stoppedAt || agent.deactivatedAt ? (
          <Badge intent="none" label="Stopped" />
        ) : agent.stoppingAt ? (
          <Badge intent="info" label="Stopping" />
        ) : agent.state == "paused" ? (
          <Badge intent="info" label="Paused" />
        ) : agent.state == "draining" ? (
          <Badge intent="info" label="Draining" />
        ) : agent.connected === null ? (
          <Badge intent="none" label="Connecting..." />
        ) : agent.connected ? (
          <Badge intent="success" label="Connected" />
        ) : (
          <Badge intent="warning" label="Disconnected" />
        )}
      </td>
      <td>
        {agent.startedAt &&
          !agent.stoppingAt &&
          !agent.deactivatedAt &&
          (agent.state == "active" ? (
            <Button
              onClick={handleStopClick}
              size="sm"
              variant="secondary"
              outline={true}
            >
              Stop
            </Button>
          ) : (
            <Button onClick={handleResumeClick} size="sm">
              Resume
            </Button>
          ))}
      </td>
    </tr>
  );
}

type AgentsTableProps = {
  projectId: string;
  environmentName: string;
  title: string;
  agents: Record<string, models.Agent>;
};

function AgentsTable({
  projectId,
  environmentName,
  title,
  agents,
}: AgentsTableProps) {
  return (
    <div>
      <h1 className="text-xl font-semibold text-slate-700 my-1">{title}</h1>
      {Object.keys(agents).length ? (
        <table className="w-full table-fixed">
          <thead className="[&_th]:py-1">
            <tr className="border-b border-slate-100">
              {["Created at", "Status"].map((title, index) => (
                <th
                  key={index}
                  className="text-left text-sm text-slate-400 font-normal"
                >
                  {title}
                </th>
              ))}
              <th></th>
            </tr>
          </thead>
          <tbody className="[&_td]:py-1">
            {sortBy(
              Object.entries(agents),
              ([_, agent]) => -agent.startingAt,
            ).map(([agentId, agent]) => (
              <AgentRow
                key={agentId}
                projectId={projectId}
                environmentName={environmentName}
                agentId={agentId}
                agent={agent}
              />
            ))}
          </tbody>
        </table>
      ) : (
        <p className="italic">None</p>
      )}
    </div>
  );
}

type LauncherTypeProps = {
  launcher: models.Pool["launcher"];
};

function LauncherType({ launcher }: LauncherTypeProps) {
  switch (launcher?.type) {
    case "docker":
      return (
        <span className="rounded-md bg-blue-400/20 text-xs text-slate-600 inline-flex gap-1 px-1 py-px items-center">
          <IconBrandDocker size={16} strokeWidth={1.5} />
          Docker
        </span>
      );
    case undefined:
      return <span className="italic text-xs text-slate-400">Unmanaged</span>;
  }
}

export default function PoolPage() {
  const { project: projectId, pool: poolName } = useParams();
  const [searchParams] = useSearchParams();
  const environmentName = searchParams.get("environment") || undefined;
  const environments = useEnvironments(projectId);
  const environmentId = findKey(
    environments,
    (e) => e.name == environmentName && e.state != "archived",
  );

  const pool = usePool(projectId, environmentId, poolName);
  useSetActive(poolName ? ["pool", poolName] : undefined);

  if (!pool) {
    return <Loading />;
  } else {
    const activeAgents = omitBy(pool.agents, "deactivatedAt");
    return (
      <>
        <div className="flex-1 flex flex-col min-h-0">
          <div className="p-5 flex items-baseline gap-1 border-b border-slate-200">
            <IconLayoutGrid
              size={26}
              strokeWidth={1.5}
              className="text-slate-500 shrink-0 self-start"
            />
            <h1 className="text-lg font-mono">{poolName}</h1>
          </div>
          <div className="flex-1 flex min-h-0">
            <div className="p-5 flex-1 flex flex-col gap-6 overflow-auto">
              <AgentsTable
                projectId={projectId!}
                environmentName={environmentName!}
                title="Agents"
                agents={activeAgents}
              />
            </div>
            <div className="p-5 max-w-[400px] min-w-[200px] w-[30%] border-l border-slate-200 flex flex-col gap-3">
              {pool.pool && (
                <>
                  {pool.pool.launcher && (
                    <div>
                      <h3 className="uppercase text-sm font-bold text-slate-400">
                        Launcher
                      </h3>
                      <LauncherType launcher={pool.pool.launcher} />
                    </div>
                  )}
                  <div>
                    <h3 className="uppercase text-sm font-bold text-slate-400">
                      Repositories
                    </h3>
                    <ul className="list-disc ml-5 marker:text-slate-600">
                      {pool.pool.repositories.map((repository) => (
                        <li key={repository}>{repository}</li>
                      ))}
                    </ul>
                  </div>
                  <div>
                    <h3 className="uppercase text-sm font-bold text-slate-400">
                      Provides
                    </h3>
                    <TagSet tagSet={pool.pool.provides} />
                  </div>
                </>
              )}
            </div>
          </div>
        </div>
      </>
    );
  }
}
