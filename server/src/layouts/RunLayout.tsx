import classNames from "classnames";
import { Fragment, ReactNode, useCallback } from "react";
import {
  NavLink,
  Outlet,
  useOutletContext,
  useParams,
  useSearchParams,
} from "react-router-dom";
import { Transition } from "@headlessui/react";
import useResizeObserver from "use-resize-observer";
import { findKey } from "lodash";

import * as models from "../models";
import * as api from "../api";
import { useSetActiveTarget } from "./ProjectLayout";
import StepDetail from "../components/StepDetail";
import usePrevious from "../hooks/usePrevious";
import { buildUrl } from "../utils";
import Loading from "../components/Loading";
import { useEnvironments, useRun } from "../topics";
import HoverContext from "../components/HoverContext";
import { useTitlePart } from "../components/TitleContext";
import WorkflowHeader from "../components/WorkflowHeader";
import SensorHeader from "../components/SensorHeader";

type TabProps = {
  page: string | null;
  children: ReactNode;
};

function Tab({ page, children }: TabProps) {
  const { project: projectId, run: runId } = useParams();
  const [searchParams] = useSearchParams();
  return (
    <NavLink
      to={buildUrl(
        `/projects/${projectId}/runs/${runId}${page ? "/" + page : ""}`,
        Object.fromEntries(searchParams),
      )}
      end={true}
      className={({ isActive }) =>
        classNames(
          "px-2 py-1 text-sm",
          isActive && "inline-block border-b-2 border-cyan-500 font-semibold",
        )
      }
    >
      {children}
    </NavLink>
  );
}

type DetailPanelProps = {
  runId: string;
  stepId: string | undefined;
  attemptNumber: number | undefined;
  run: models.Run;
  projectId: string;
  activeEnvironmentId: string;
  className?: string;
};

function DetailPanel({
  runId,
  stepId,
  attemptNumber,
  run,
  projectId,
  activeEnvironmentId,
  className,
}: DetailPanelProps) {
  const previousStepId = usePrevious(stepId);
  const previousAttemptNumber = usePrevious(attemptNumber);
  const stepIdOrPrevious = stepId || previousStepId;
  const attemptNumberOrPrevious = attemptNumber || previousAttemptNumber;
  const handleRerunStep = useCallback(
    (stepId: string, environmentName: string) => {
      return api.rerunStep(projectId, stepId, environmentName);
    },
    [projectId],
  );
  return (
    <Transition
      as={Fragment}
      show={!!stepId}
      enter="transform transition ease-in-out duration-150"
      enterFrom="translate-x-full"
      enterTo="translate-x-0"
      leave="transform transition ease-in-out duration-300"
      leaveFrom="translate-x-0"
      leaveTo="translate-x-full"
    >
      <div className={classNames(className, "pt-2 pr-2 pb-2 flex")}>
        <div className="bg-slate-100 border border-slate-200 rounded-md flex flex-1 max-w-full">
          {stepIdOrPrevious && (
            <StepDetail
              runId={runId}
              stepId={stepIdOrPrevious}
              attempt={attemptNumberOrPrevious || 1}
              run={run}
              projectId={projectId}
              activeEnvironmentId={activeEnvironmentId}
              className="flex-1"
              onRerunStep={handleRerunStep}
            />
          )}
        </div>
      </div>
    </Transition>
  );
}

type OutletContext = {
  run: models.Run;
  width: number;
  height: number;
};

export default function RunLayout() {
  const { project: projectId, run: runId } = useParams();
  const [searchParams] = useSearchParams();
  const activeStepId = searchParams.get("step") || undefined;
  const activeAttemptNumber = searchParams.has("attempt")
    ? parseInt(searchParams.get("attempt")!, 10)
    : undefined;
  const activeEnvironmentName = searchParams.get("environment") || undefined;
  const environments = useEnvironments(projectId);
  const activeEnvironmentId = findKey(
    environments,
    (e) => e.name == activeEnvironmentName && e.status != 1,
  );
  const run = useRun(projectId, runId, activeEnvironmentId);
  const initialStep = run && Object.values(run.steps).find((s) => !s.parentId);
  useTitlePart(
    initialStep && `${initialStep.target} (${initialStep.repository})`,
  );
  useSetActiveTarget(initialStep?.repository, initialStep?.target);
  const { ref, width, height } = useResizeObserver<HTMLDivElement>();
  if (!run || !initialStep) {
    return <Loading />;
  } else {
    return (
      <HoverContext>
        <div
          className={classNames(
            "flex-1 flex flex-col relative",
            activeStepId && "pr-[400px]",
          )}
        >
          {run.recurrent ? (
            <SensorHeader
              repository={initialStep.repository}
              target={initialStep.target}
              projectId={projectId!}
              runId={runId}
              activeEnvironmentId={activeEnvironmentId}
              activeEnvironmentName={activeEnvironmentName}
            />
          ) : (
            <WorkflowHeader
              repository={initialStep.repository}
              target={initialStep.target}
              projectId={projectId!}
              runId={runId}
              activeEnvironmentId={activeEnvironmentId}
              activeEnvironmentName={activeEnvironmentName}
            />
          )}
          <div className="grow flex flex-col">
            <div className="border-b px-4">
              {run.recurrent ? (
                <Tab page="runs">Runs</Tab>
              ) : (
                <Fragment>
                  <Tab page="graph">Graph</Tab>
                  <Tab page="timeline">Timeline</Tab>
                </Fragment>
              )}
              <Tab page="logs">Logs</Tab>
              {!run.recurrent && <Tab page="assets">Assets</Tab>}
            </div>
            <div className="flex-1 basis-0 overflow-auto" ref={ref}>
              <Outlet
                context={{ run, width: width || 0, height: height || 0 }}
              />
            </div>
          </div>
          <DetailPanel
            runId={runId!}
            stepId={activeStepId}
            attemptNumber={activeAttemptNumber}
            run={run}
            projectId={projectId!}
            activeEnvironmentId={activeEnvironmentId!}
            className="absolute right-0 top-0 bottom-0 w-[400px]"
          />
        </div>
      </HoverContext>
    );
  }
}

export const useContext = useOutletContext<OutletContext>;
