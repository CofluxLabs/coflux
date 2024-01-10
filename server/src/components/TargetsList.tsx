import classNames from "classnames";
import { ComponentType, Fragment } from "react";
import { Link } from "react-router-dom";
import {
  IconSubtask,
  IconCpu,
  TablerIconsProps,
  IconInnerShadowTopLeft,
  IconAlertCircle,
  IconClock,
} from "@tabler/icons-react";
import { DateTime } from "luxon";

import * as models from "../models";
import { buildUrl, formatDiff, pluralise } from "../utils";
import useNow from "../hooks/useNow";

function isTargetOnline(
  agents: Record<string, Record<string, string[]>> | undefined,
  repository: string,
  target: string
) {
  return (
    agents !== undefined &&
    Object.values(agents).some((a) => a[repository]?.includes(target))
  );
}

type TargetProps = {
  url: string;
  icon: ComponentType<TablerIconsProps>;
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
          "block px-2 py-0.5 my-0.5 rounded-md flex gap-1 items-center",
          isOnline ? "text-slate-900" : "text-slate-400",
          isActive ? "bg-slate-200" : "hover:bg-slate-200/50"
        )}
      >
        <Icon size={20} strokeWidth={1} className="text-slate-500 shrink-0" />
        <div className="font-mono flex-1 overflow-hidden text-ellipsis">
          {name}
        </div>
      </Link>
    </li>
  );
}

type Props = {
  projectId: string | undefined;
  environmentName: string | undefined;
  activeTarget: { repository: string; target: string } | undefined;
  repositories: Record<string, models.Repository>;
  agents: Record<string, Record<string, string[]>> | undefined;
};

export default function TargetsList({
  projectId,
  environmentName,
  activeTarget,
  repositories,
  agents,
}: Props) {
  const now = useNow(500);
  return (
    <div className="p-2">
      {Object.entries(repositories).map(([repository, { targets, stats }]) => {
        const nextDueDiff = stats.nextDueAt
          ? DateTime.fromJSDate(now).diff(
              DateTime.fromMillis(stats.nextDueAt),
              ["days", "hours", "minutes", "seconds"]
            )
          : undefined;
        return (
          <Fragment key={repository}>
            <div className="flex items-center mt-4 py-1 px-2 gap-2">
              <h2 className="font-bold uppercase text-slate-400 text-sm">
                {repository}
              </h2>
              {nextDueDiff && nextDueDiff.toMillis() > 1000 ? (
                <span
                  title={`Executions overdue (${formatDiff(nextDueDiff, 1)})`}
                >
                  <IconAlertCircle
                    size={16}
                    className={
                      nextDueDiff.toMillis() > 5000
                        ? "text-red-700"
                        : "text-yellow-600"
                    }
                  />
                </span>
              ) : stats.executing ? (
                <span
                  title={`${pluralise(stats.executing, "execution")} running`}
                >
                  <IconInnerShadowTopLeft
                    size={16}
                    className="text-cyan-400 animate-spin"
                  />
                </span>
              ) : stats.scheduled ? (
                <span
                  title={`${pluralise(stats.scheduled, "execution")} scheduled`}
                >
                  <IconClock size={16} className="text-slate-400" />
                </span>
              ) : undefined}
            </div>
            {Object.keys(targets).length ? (
              <ul>
                {Object.entries(targets).map(([name, target]) => {
                  const isActive =
                    !!activeTarget &&
                    activeTarget.repository == repository &&
                    activeTarget.target == name;
                  return (
                    <Target
                      key={name}
                      name={name}
                      icon={target.type == "sensor" ? IconCpu : IconSubtask}
                      url={buildUrl(
                        `/projects/${projectId}/targets/${repository}/${name}`,
                        { environment: environmentName }
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
          </Fragment>
        );
      })}
    </div>
  );
}
