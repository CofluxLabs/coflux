import { Fragment } from "react";
import { Link, useParams } from "react-router-dom";
import classNames from "classnames";
import {
  Menu,
  MenuButton,
  MenuItem,
  MenuItems,
  Transition,
} from "@headlessui/react";
import { IconCheck, IconChevronDown } from "@tabler/icons-react";

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
      <MenuButton
        className={classNames(
          "flex items-center gap-1 py-1 px-2 rounded bg-black/10 hover:bg-white/10",
          activeProject ? "text-white" : "text-white/70",
        )}
      >
        <span className="text-sm">
          {activeProject ? activeProject.name : "Select project..."}
        </span>
        <IconChevronDown size={16} className="opacity-40 mt-0.5" />
      </MenuButton>
      <Transition
        as={Fragment}
        enter="transition ease-in duration-100"
        enterFrom="opacity-0 scale-95"
        enterTo="opacity-100 scale-100"
        leave="transition ease-in duration-100"
        leaveFrom="opacity-100 scale-100"
        leaveTo="opacity-0 scale-95"
      >
        <MenuItems
          className="absolute z-10 overflow-y-scroll text-base bg-white rounded-md shadow-lg divide-y divide-slate-100 origin-top mt-1"
          static={true}
        >
          <div className="p-1">
            {Object.entries(projects).map(([projectId, project]) => (
              <MenuItem key={projectId}>
                <Link
                  to={`/projects/${projectId}`}
                  className={classNames(
                    "flex items-center gap-1 pl-2 pr-3 py-1 rounded whitespace-nowrap text-sm data-[active]:bg-slate-100",
                  )}
                >
                  {projectId == activeProjectId ? (
                    <IconCheck size={16} className="mt-0.5" />
                  ) : (
                    <span className="w-[16px]" />
                  )}
                  {project.name}
                </Link>
              </MenuItem>
            ))}
          </div>
          <div className="p-1">
            <MenuItem>
              <Link
                to="/projects"
                className={classNames(
                  "flex px-2 py-1 rounded whitespace-nowrap text-sm data-[active]:bg-slate-100",
                )}
              >
                Manage projects...
              </Link>
            </MenuItem>
          </div>
        </MenuItems>
      </Transition>
    </Menu>
  );
}
