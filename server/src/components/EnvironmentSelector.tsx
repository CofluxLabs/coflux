import { Fragment, useCallback, useState } from "react";
import { Link, useLocation, useSearchParams } from "react-router-dom";
import classNames from "classnames";
import { Menu, Transition } from "@headlessui/react";
import {
  IconCheck,
  IconChevronDown,
  IconCornerDownRight,
} from "@tabler/icons-react";

import { buildUrl } from "../utils";
import * as models from "../models";
import EnvironmentLabel from "./EnvironmentLabel";
import AddEnvironmentDialog from "./AddEnvironmentDialog";
import { times } from "lodash";

function traverseEnvironments(
  environments: Record<string, models.Environment>,
  parentId: string | null = null,
  depth: number = 0,
): [string, models.Environment, number][] {
  return Object.entries(environments)
    .filter(([_, e]) => e.baseId == parentId && e.status != 1)
    .flatMap(([environmentId, environment]) => [
      [environmentId, environment, depth],
      ...traverseEnvironments(environments, environmentId, depth + 1),
    ]);
}

type Props = {
  projectId: string;
  environments: Record<string, models.Environment>;
  activeEnvironmentId: string | undefined;
};

export default function EnvironmentSelector({
  projectId,
  environments,
  activeEnvironmentId,
}: Props) {
  const location = useLocation();
  const [searchParams] = useSearchParams();
  const activeEnvironment = searchParams.get("environment");
  const [addEnvironmentDialogOpen, setAddEnvironmentDialogOpen] =
    useState(false);
  const handleAddEnvironmentClick = useCallback(() => {
    setAddEnvironmentDialogOpen(true);
  }, []);
  const handleAddEnvironmentDialogClose = useCallback(() => {
    setAddEnvironmentDialogOpen(false);
  }, []);
  return (
    <Fragment>
      <Menu as="div" className="relative">
        <Menu.Button className="flex items-center gap-1">
          {activeEnvironmentId ? (
            <EnvironmentLabel
              projectId={projectId}
              environmentId={activeEnvironmentId}
              interactive={true}
              accessory={
                <IconChevronDown size={14} className="opacity-40 mt-0.5" />
              }
            />
          ) : (
            <span className="flex items-center gap-1 rounded px-2 py-0.5 text-slate-100 hover:bg-white/10 text-sm">
              Select environment...
              <IconChevronDown size={14} className="opacity-40 mt-0.5" />
            </span>
          )}
        </Menu.Button>
        <Transition
          as={Fragment}
          enter="transition ease-in duration-100"
          enterFrom="opacity-0 scale-95"
          enterTo="opacity-100 scale-100"
          leave="transition ease-in duration-100"
          leaveFrom="opacity-100 scale-100"
          leaveTo="opacity-0 scale-95"
        >
          <Menu.Items
            className="absolute z-10 overflow-y-scroll text-base bg-white rounded-md shadow-lg divide-y divide-slate-100 origin-top mt-1"
            static={true}
          >
            {Object.keys(environments).length > 0 && (
              <div className="p-1">
                {traverseEnvironments(environments).map(
                  ([environmentId, environment, depth]) => (
                    <Menu.Item key={environmentId}>
                      {({ active }) => (
                        <Link
                          to={buildUrl(location.pathname, {
                            environment: environment.name,
                          })}
                          className={classNames(
                            "flex items-center gap-1 pl-2 pr-3 py-1 rounded whitespace-nowrap text-sm",
                            active && "bg-slate-100",
                          )}
                        >
                          {environment.name == activeEnvironment ? (
                            <IconCheck size={16} className="mt-0.5" />
                          ) : (
                            <span className="w-[16px]" />
                          )}
                          {times(depth).map((i) =>
                            i == depth - 1 ? (
                              <IconCornerDownRight
                                key={i}
                                size={16}
                                className="text-slate-300"
                              />
                            ) : (
                              <span key={i} className="w-2" />
                            ),
                          )}
                          {environment.name}
                        </Link>
                      )}
                    </Menu.Item>
                  ),
                )}
              </div>
            )}
            <div className="p-1">
              <Menu.Item>
                {({ active }) => (
                  <button
                    className={classNames(
                      "w-full flex px-2 py-1 rounded whitespace-nowrap text-sm",
                      active && "bg-slate-100",
                    )}
                    onClick={handleAddEnvironmentClick}
                  >
                    Add environment...
                  </button>
                )}
              </Menu.Item>
            </div>
          </Menu.Items>
        </Transition>
      </Menu>
      <AddEnvironmentDialog
        open={addEnvironmentDialogOpen}
        onClose={handleAddEnvironmentDialogClose}
      />
    </Fragment>
  );
}
