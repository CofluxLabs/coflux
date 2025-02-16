import { Fragment, useCallback, useState } from "react";
import { useEnvironments, useProjects } from "../topics";
import { findKey } from "lodash";
import Logo from "./Logo";
import {
  IconChevronCompactRight,
  IconMinusVertical,
  IconSettings,
  IconPlayerPauseFilled,
  IconPlayerPlayFilled,
} from "@tabler/icons-react";
import ProjectSelector from "./ProjectSelector";
import EnvironmentSelector from "./EnvironmentSelector";
import ProjectSettingsDialog from "./ProjectSettingsDialog";
import SearchInput from "./SearchInput";
import * as api from "../api";
import * as models from "../models";

type PlayPauseButtonProps = {
  projectId: string;
  environmentId: string;
  environment: models.Environment;
};

function PlayPauseButton({
  projectId,
  environmentId,
  environment,
}: PlayPauseButtonProps) {
  const { state } = environment;
  const handleClick = useCallback(() => {
    // TODO: handle error
    if (state == "active") {
      api.pauseEnvironment(projectId, environmentId);
    } else if (state == "paused") {
      api.resumeEnvironment(projectId, environmentId);
    }
  }, [environmentId, state]);
  return state == "active" ? (
    <button
      className="text-slate-100 bg-cyan-800/30 rounded p-1 hover:bg-cyan-800/60"
      title="Pause environment"
      onClick={handleClick}
    >
      <IconPlayerPauseFilled size={16} />
    </button>
  ) : state == "paused" ? (
    <button
      className="text-slate-100 bg-cyan-800/30 rounded p-1 hover:bg-cyan-800/60"
      title="Resume environment"
      onClick={handleClick}
    >
      <IconPlayerPlayFilled size={16} className="animate-pulse" />
    </button>
  ) : null;
}

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
    (e) => e.name == activeEnvironmentName && e.state != "archived",
  );
  return (
    <div className="flex p-3 items-center justify-between gap-5 h-14">
      <div className="flex items-center gap-1">
        <Logo />
        {projects && (
          <Fragment>
            <IconChevronCompactRight
              size={16}
              className="text-white/40 shrink-0"
            />
            <div className="flex items-center gap-2">
              <ProjectSelector projects={projects} />
              <IconChevronCompactRight
                size={16}
                className="text-white/40 shrink-0"
              />
              {projectId && environments && (
                <Fragment>
                  <EnvironmentSelector
                    projectId={projectId}
                    environments={environments}
                    activeEnvironmentId={activeEnvironmentId}
                  />
                  {activeEnvironmentId && (
                    <PlayPauseButton
                      projectId={projectId}
                      environmentId={activeEnvironmentId}
                      environment={environments[activeEnvironmentId]}
                    />
                  )}
                </Fragment>
              )}
            </div>
          </Fragment>
        )}
      </div>
      <div className="flex items-center gap-1">
        {projectId && (
          <Fragment>
            {activeEnvironmentId && (
              <Fragment>
                <SearchInput
                  projectId={projectId}
                  environmentId={activeEnvironmentId}
                />
                <IconMinusVertical
                  size={16}
                  className="text-white/40 shrink-0"
                />
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
    </div>
  );
}
