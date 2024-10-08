import classNames from "classnames";
import { ComponentType } from "react";
import { Link } from "react-router-dom";
import {
  IconSubtask,
  IconCpu,
  IconProps,
  IconInnerShadowTopLeft,
  IconAlertCircle,
  IconClock,
} from "@tabler/icons-react";
import { DateTime } from "luxon";

import * as models from "../models";
import { buildUrl, pluralise } from "../utils";
import useNow from "../hooks/useNow";

function isTargetOnline(
  agents: Record<string, Record<string, string[]>> | undefined,
  repository: string,
  target: string,
) {
  return (
    agents !== undefined &&
    Object.values(agents).some((a) => a[repository]?.includes(target))
  );
}

type TargetProps = {
  url: string;
  icon: ComponentType<IconProps>;
  name: string;
  isActive: boolean;
  isOnline: boolean;
};

function Target({ url, icon: Icon, name, isActive, isOnline }: TargetProps) {
  return (
    <li>
      <Link
        to={url}
        className={classNames(
          "block px-1 py-0.5 my-0.5 rounded-md flex gap-1 items-center",
          isOnline ? "text-slate-900" : "text-slate-400",
          isActive ? "bg-slate-200" : "hover:bg-slate-200/50",
        )}
      >
        <Icon size={20} strokeWidth={1} className="text-slate-500 shrink-0" />
        <div className="font-mono flex-1 overflow-hidden text-sm text-ellipsis">
          {name}
        </div>
      </Link>
    </li>
  );
}

type Props = {
  projectId: string | undefined;
  environmentName: string | undefined;
  activeRepository: string | undefined;
  activeTarget: string | undefined;
  repositories: Record<string, models.Repository>;
  agents: Record<string, Record<string, string[]>> | undefined;
};

export default function TargetsList({
  projectId,
  environmentName,
  activeRepository,
  activeTarget,
  repositories,
  agents,
}: Props) {
  const now = useNow(500);
  return (
    <div className="p-2">
      {Object.entries(repositories).map(
        ([
          repository,
          { workflows, sensors, executing, nextDueAt, scheduled },
        ]) => {
          const nextDueDiff = nextDueAt
            ? DateTime.fromMillis(nextDueAt).diff(now, [
                "days",
                "hours",
                "minutes",
                "seconds",
              ])
            : undefined;
          const isActive = activeRepository == repository && !activeTarget;
          return (
            <div key={repository} className="py-2">
              <Link
                to={buildUrl(
                  `/projects/${projectId}/repositories/${encodeURIComponent(
                    repository,
                  )}`,
                  { environment: environmentName },
                )}
                className={classNames(
                  "block rounded-md",
                  isActive ? "bg-slate-200" : "hover:bg-slate-200/50",
                )}
              >
                <div className="flex items-center py-1 px-1 gap-2">
                  <h2 className="font-bold uppercase text-slate-400 text-sm">
                    {repository}
                  </h2>
                  {nextDueDiff && nextDueDiff.toMillis() < -1000 ? (
                    <span
                      title={`Executions overdue (${nextDueDiff
                        .rescale()
                        .toHuman({
                          unitDisplay: "short",
                        })})`}
                    >
                      <IconAlertCircle
                        size={16}
                        className={
                          nextDueDiff.toMillis() < -5000
                            ? "text-red-700"
                            : "text-yellow-600"
                        }
                      />
                    </span>
                  ) : executing ? (
                    <span
                      title={`${pluralise(executing, "execution")} running`}
                    >
                      <IconInnerShadowTopLeft
                        size={16}
                        className="text-cyan-400 animate-spin"
                      />
                    </span>
                  ) : scheduled ? (
                    <span
                      title={`${pluralise(scheduled, "execution")} scheduled${
                        nextDueDiff
                          ? ` (${nextDueDiff.rescale().toHuman({ unitDisplay: "narrow" })})`
                          : ""
                      }`}
                    >
                      <IconClock size={16} className="text-slate-400" />
                    </span>
                  ) : undefined}
                </div>
              </Link>
              {workflows.length || sensors.length ? (
                <ul>
                  {workflows.map((name) => {
                    const isActive =
                      activeRepository == repository && activeTarget == name;
                    return (
                      <Target
                        key={name}
                        name={name}
                        icon={IconSubtask}
                        url={buildUrl(
                          `/projects/${projectId}/workflows/${encodeURIComponent(
                            repository,
                          )}/${name}`,
                          { environment: environmentName },
                        )}
                        isActive={isActive}
                        isOnline={isTargetOnline(agents, repository, name)}
                      />
                    );
                  })}
                  {sensors.map((name) => {
                    const isActive =
                      activeRepository == repository && activeTarget == name;
                    return (
                      <Target
                        key={name}
                        name={name}
                        icon={IconCpu}
                        url={buildUrl(
                          `/projects/${projectId}/sensors/${encodeURIComponent(
                            repository,
                          )}/${name}`,
                          { environment: environmentName },
                        )}
                        isActive={isActive}
                        isOnline={isTargetOnline(agents, repository, name)}
                      />
                    );
                  })}
                </ul>
              ) : (
                <p className="text-slate-300 italic px-2 text-sm">No targets</p>
              )}
            </div>
          );
        },
      )}
    </div>
  );
}
