import { useTopic } from "@topical/react";
import { Link, Outlet } from "react-router-dom";

import * as models from "../models";
import { IconBox, IconPlus, IconPyramid } from "@tabler/icons-react";

export default function ProjectsPage() {
  const [projects] = useTopic<Record<string, models.Project>>("projects");
  return (
    <div>
      {projects && (
        <ul className="flex flex-wrap gap-4 p-4">
          {Object.keys(projects).map((projectId) => (
            <li key={projectId} className="flex w-40 h-44">
              <Link
                to={`/projects/${projectId}`}
                className="group flex-1 flex gap-2 flex-col justify-center p-4 pt-8 border border-slate-200 rounded-lg items-center overflow-hidden hover:border-slate-300 hover:shadow hover:bg-slate-100/20"
              >
                <IconPyramid
                  size={50}
                  stroke={1.5}
                  className="text-slate-500 group-hover:text-slate-700"
                />
                <h3 className="font-mono font-bold text-slate-500 group-hover:text-slate-600 max-w-full overflow-hidden text-ellipsis">
                  {projectId}
                </h3>
              </Link>
            </li>
          ))}
          <li className="flex w-44 h-44">
            <Link
              to="/projects/new"
              className="group flex-1 flex gap-2 flex-col justify-center p-4 pt-8 border border-dashed border-slate-200 rounded-lg items-center hover:border-slate-300 hover:bg-slate-100/20"
            >
              <IconPlus
                size={50}
                stroke={1.5}
                className="text-slate-500 group-hover:text-slate-700"
              />
              <h3 className="text-slate-500 group-hover:text-slate-600">
                New project...
              </h3>
            </Link>
          </li>
        </ul>
      )}
      <Outlet />
    </div>
  );
}
