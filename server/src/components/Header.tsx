import { Fragment, useCallback, useState } from "react";
import { useEnvironments, useProjects } from "../topics";
import { findKey } from "lodash";
import Logo from "./Logo";
import {
  IconChevronCompactRight,
  IconMinusVertical,
  IconSettings,
} from "@tabler/icons-react";
import ProjectSelector from "./ProjectSelector";
import EnvironmentSelector from "./EnvironmentSelector";
import ProjectSettingsDialog from "./ProjectSettingsDialog";
import SearchInput from "./SearchInput";

type Props = {
  projectId?: string;
  activeEnvironmentName?: string;
};

export default function Header({ projectId, activeEnvironmentName }: Props) {
  const projects = useProjects();
  const environments = useEnvironments(projectId);
  const [settingsOpen, setSettingsOpen] = useState(false);
  const handleSettingsClose = useCallback(() => setSettingsOpen(false), []);
  const handleSettingsClick = useCallback(() => setSettingsOpen(true), []);
  const activeEnvironmentId = findKey(
    environments,
    (e) => e.name == activeEnvironmentName && e.status != "archived",
  );
  return (
    <>
      <div className="flex p-3 items-center bg-cyan-600 gap-1 h-14">
        <Logo />
        {projects && (
          <Fragment>
            <IconChevronCompactRight size={16} className="text-white/40" />
            <div className="flex items-center gap-2">
              <ProjectSelector projects={projects} />
              {projectId && environments && (
                <EnvironmentSelector
                  projectId={projectId}
                  environments={environments}
                  activeEnvironmentId={activeEnvironmentId}
                />
              )}
            </div>
          </Fragment>
        )}
        <div className="flex-1"></div>
        {projectId && (
          <Fragment>
            {activeEnvironmentId && (
              <Fragment>
                <SearchInput
                  projectId={projectId}
                  environmentId={activeEnvironmentId}
                />
                <IconMinusVertical size={16} className="text-white/40" />
              </Fragment>
            )}
            <ProjectSettingsDialog
              projectId={projectId}
              open={settingsOpen}
              onClose={handleSettingsClose}
            />
            <button
              className="text-slate-100 p-1 rounded hover:bg-slate-100/10"
              title="Settings"
              onClick={handleSettingsClick}
            >
              <IconSettings size={24} strokeWidth={1.5} />
            </button>
          </Fragment>
        )}
      </div>
    </>
  );
}
