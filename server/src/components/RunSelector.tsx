import { Fragment } from "react";
import { Menu, Transition } from "@headlessui/react";
import { sortBy } from "lodash";
import classNames from "classnames";
import { Link, useLocation } from "react-router-dom";
import { DateTime } from "luxon";
import {
  IconChevronDown,
  IconChevronLeft,
  IconChevronRight,
} from "@tabler/icons-react";

import * as models from "../models";
import { buildUrl } from "../utils";

function getRunUrl(
  projectId: string,
  runId: string,
  environmentName: string | undefined,
  pathname: string
) {
  // TODO: better way to determine page
  const parts = pathname.split("/");
  const page = parts.length == 6 ? parts[5] : undefined;
  return buildUrl(
    `/projects/${projectId}/runs/${runId}${page ? "/" + page : ""}`,
    {
      environment: environmentName,
    }
  );
}

type OptionsProps = {
  runs: Record<string, Pick<models.Run, "createdAt">>;
  projectId: string | null;
  environmentName: string | undefined;
  selectedRunId: string;
};

function Options({
  runs,
  projectId,
  environmentName,
  selectedRunId,
}: OptionsProps) {
  const location = useLocation();
  if (!Object.keys(runs).length) {
    return <p>No runs for {environmentName}</p>;
  } else {
    return (
      <Fragment>
        {sortBy(Object.keys(runs), (runId) => runs[runId].createdAt)
          .reverse()
          .map((runId) => {
            const createdAt = DateTime.fromMillis(runs[runId].createdAt);
            return (
              <Menu.Item key={runId}>
                {({ active }) => (
                  <Link
                    to={getRunUrl(
                      projectId!,
                      runId,
                      environmentName,
                      location.pathname
                    )}
                    className={classNames(
                      "block p-2",
                      active && "bg-slate-100"
                    )}
                  >
                    <h3
                      className={classNames(
                        "font-mono",
                        runId == selectedRunId && "font-bold"
                      )}
                    >
                      {runId}
                    </h3>
                    <p
                      className="text-xs text-slate-500 whitespace-nowrap"
                      title={createdAt.toLocaleString(
                        DateTime.DATETIME_SHORT_WITH_SECONDS
                      )}
                    >
                      {createdAt.toRelative()} ago
                    </p>
                  </Link>
                )}
              </Menu.Item>
            );
          })}
      </Fragment>
    );
  }
}

function getNextPrevious(
  ids: string[],
  currentId: string,
  direction: "next" | "previous"
) {
  const index = ids.indexOf(currentId);
  if (index >= 0) {
    if (direction == "next") {
      if (index < ids.length - 1) {
        return ids[index + 1];
      }
    } else {
      if (index > 0) {
        return ids[index - 1];
      }
    }
  }

  return null;
}

type NextPreviousButtonProps = {
  projectId: string | null;
  environmentName: string | undefined;
  runs: Record<string, Pick<models.Run, "createdAt">>;
  currentRunId: string;
  direction: "next" | "previous";
};

function NextPreviousButton({
  projectId,
  environmentName,
  runs,
  currentRunId,
  direction,
}: NextPreviousButtonProps) {
  const location = useLocation();
  // TODO: move to parent?
  const runIds = sortBy(Object.keys(runs), (runId) => runs[runId].createdAt);
  const runId = getNextPrevious(runIds, currentRunId, direction);
  const Icon = direction == "next" ? IconChevronRight : IconChevronLeft;
  const className = classNames(
    "p-1 bg-white border border-slate-300 flex items-center",
    runId ? "hover:bg-slate-100 text-slate-500" : "text-slate-200",
    direction == "next" ? "rounded-r-md -ml-px" : "rounded-l-md -mr-px"
  );
  if (runId) {
    return (
      <Link
        to={getRunUrl(projectId!, runId, environmentName, location.pathname)}
        className={className}
      >
        <Icon size={16} />
      </Link>
    );
  } else {
    return (
      <span className={className}>
        <Icon size={16} />
      </span>
    );
  }
}

type Props = {
  runs: Record<string, Pick<models.Run, "createdAt">>;
  projectId: string | null;
  runId: string;
  environmentName: string | undefined;
  className?: string;
};

export default function RunSelector({
  runs,
  projectId,
  runId,
  environmentName,
  className,
}: Props) {
  return (
    <div className={classNames(className, "flex shadow-sm")}>
      <NextPreviousButton
        direction="previous"
        projectId={projectId}
        environmentName={environmentName}
        runs={runs}
        currentRunId={runId}
      />
      <Menu>
        {({ open }) => (
          <div className="relative">
            <Menu.Button className="flex items-center w-full py-1 px-2 gap-1 bg-white border border-slate-300 hover:bg-slate-50">
              <span className="font-mono text-sm">{runId}</span>
              <span className="text-slate-400">
                <IconChevronDown size={16} />
              </span>
            </Menu.Button>
            <Transition
              as={Fragment}
              leave="transition ease-in duration-100"
              leaveFrom="opacity-100"
              leaveTo="opacity-0"
            >
              <Menu.Items
                className="absolute z-10 overflow-y-scroll text-base bg-white rounded shadow-lg max-h-60"
                static={true}
              >
                {open && (
                  <Options
                    runs={runs}
                    projectId={projectId}
                    environmentName={environmentName}
                    selectedRunId={runId}
                  />
                )}
              </Menu.Items>
            </Transition>
          </div>
        )}
      </Menu>
      <NextPreviousButton
        direction="next"
        projectId={projectId}
        environmentName={environmentName}
        runs={runs}
        currentRunId={runId}
      />
    </div>
  );
}
