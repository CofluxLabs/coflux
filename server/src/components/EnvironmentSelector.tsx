import { Fragment, useCallback, useState } from "react";
import { Link, useParams, useSearchParams } from "react-router-dom";
import classNames from "classnames";
import { Menu, Transition } from "@headlessui/react";
import { IconCheck, IconChevronDown } from "@tabler/icons-react";

import { buildUrl } from "../utils";
import AddEnvironmentDialog from "./AddEnvironmentDialog";

function classNameForEnvironment(name: string) {
  if (name.startsWith("stag")) {
    return "bg-yellow-300/90 text-yellow-700 hover:bg-yellow-300/80";
  } else if (name.startsWith("prod")) {
    return "bg-fuchsia-300/90 text-fuchsia-700 hover:bg-fuchsia-300/80";
  } else {
    return "bg-slate-300/90 text-slate-700 hover:bg-slate-300/80";
  }
}

type Props = {
  environments: string[];
};

export default function EnvironmentSelector({ environments }: Props) {
  const { project: activeProjectId } = useParams();
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
        <Menu.Button>
          {activeEnvironment ? (
            <span
              className={classNames(
                "flex items-center gap-1 rounded px-1.5 py-0.5 text-sm",
                classNameForEnvironment(activeEnvironment)
              )}
            >
              {activeEnvironment}
              <IconChevronDown size={14} className="opacity-40 mt-0.5" />
            </span>
          ) : null}
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
            <div className="p-1">
              {environments.map((environmentName) => (
                <Menu.Item key={`${activeProjectId}/${environmentName}`}>
                  {({ active }) => (
                    <Link
                      to={buildUrl(`/projects/${activeProjectId}`, {
                        environment: environmentName,
                      })}
                      className={classNames(
                        "flex items-center gap-1 pl-2 pr-3 py-1 rounded whitespace-nowrap text-sm",
                        active && "bg-slate-100"
                      )}
                    >
                      {environmentName == activeEnvironment ? (
                        <IconCheck size={16} className="mt-0.5" />
                      ) : (
                        <span className="w-[16px]" />
                      )}
                      {environmentName}
                    </Link>
                  )}
                </Menu.Item>
              ))}
            </div>
            <div className="p-1">
              <Menu.Item>
                {({ active }) => (
                  <button
                    className={classNames(
                      "flex px-2 py-1 rounded whitespace-nowrap text-sm",
                      active && "bg-slate-100"
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
