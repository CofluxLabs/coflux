import { Fragment } from "react";
import { Link, useParams } from "react-router-dom";
import classNames from "classnames";
import { Menu, Transition } from "@headlessui/react";
import { IconChevronDown } from "@tabler/icons-react";

import * as models from "../models";

type Props = {
  projects: Record<string, models.Project>;
};

export default function ProjectSelector({ projects }: Props) {
  const { project: activeProjectId } = useParams();
  const activeProject =
    projects && activeProjectId ? projects[activeProjectId] : undefined;
  return (
    <Menu as="div" className="relative">
      <Menu.Button className="flex items-center gap-1 py-1 px-2 text-white rounded bg-black/10 hover:bg-white/10">
        {activeProject ? (
          <span className="text-sm">{activeProject.name}</span>
        ) : (
          <span>Select project...</span>
        )}
        <IconChevronDown size={20} className="text-white/50" />
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
            {Object.entries(projects).map(([projectId, project]) => (
              <Menu.Item key={projectId}>
                {({ active }) => (
                  <Link
                    to={`/projects/${projectId}`}
                    className={classNames(
                      "flex px-2 py-1 rounded whitespace-nowrap text-sm",
                      active && "bg-slate-100"
                    )}
                  >
                    {project.name}
                  </Link>
                )}
              </Menu.Item>
            ))}
          </div>
          <div className="p-1">
            <Menu.Item>
              {({ active }) => (
                <Link
                  to="/projects"
                  className={classNames(
                    "flex px-2 py-1 rounded whitespace-nowrap text-sm",
                    active && "bg-slate-100"
                  )}
                >
                  Manage projects...
                </Link>
              )}
            </Menu.Item>
          </div>
        </Menu.Items>
      </Transition>
    </Menu>
  );
}
