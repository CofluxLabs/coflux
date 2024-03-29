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

import * as models from "../models";
import * as api from "../api";
import { useSetActiveTarget } from "./ProjectLayout";
import StepDetail from "../components/StepDetail";
import usePrevious from "../hooks/usePrevious";
import { buildUrl } from "../utils";
import Loading from "../components/Loading";
import { useRunTopic, useTargetTopic } from "../topics";
import TargetHeader from "../components/TargetHeader";
import HoverContext from "../components/HoverContext";
import { useTitlePart } from "../components/TitleContext";

type TabProps = {
  page: string | null;
  children: ReactNode;
};

function Tab({ page, children }: TabProps) {
  const { project: projectId, run: runId } = useParams();
  const [searchParams] = useSearchParams();
  // TODO: tidy
  const params = {
    step: searchParams.get("step"),
    attempt: searchParams.get("attempt"),
    environment: searchParams.get("environment"),
  };
  return (
    <NavLink
      to={buildUrl(
        `/projects/${projectId}/runs/${runId}${page ? "/" + page : ""}`,
        params,
      )}
      end={true}
      className={({ isActive }) =>
        classNames(
          "px-2 py-1",
          isActive && "inline-block border-b-4 border-cyan-500",
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
  environmentName: string;
  className?: string;
};

function DetailPanel({
  runId,
  stepId,
  attemptNumber,
  run,
  projectId,
  environmentName,
  className,
}: DetailPanelProps) {
  const previousStepId = usePrevious(stepId);
  const previousAttemptNumber = usePrevious(attemptNumber);
  const stepIdOrPrevious = stepId || previousStepId;
  const attemptNumberOrPrevious = attemptNumber || previousAttemptNumber;
  const handleRerunStep = useCallback(
    (stepId: string) => {
      return api.rerunStep(projectId, environmentName, stepId);
    },
    [projectId, environmentName],
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
      <div
        className={classNames(
          className,
          "bg-slate-100 border-l border-slate-200 flex shadow-lg",
        )}
      >
        {stepIdOrPrevious && (
          <StepDetail
            runId={runId}
            stepId={stepIdOrPrevious}
            attempt={attemptNumberOrPrevious || 1}
            run={run}
            projectId={projectId}
            environmentName={environmentName}
            className="flex-1"
            onRerunStep={handleRerunStep}
          />
        )}
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
  const environmentName = searchParams.get("environment") || undefined;
  const run = useRunTopic(projectId, environmentName, runId);
  const initialStep = run && Object.values(run.steps).find((s) => !s.parentId);
  const target = useTargetTopic(
    projectId,
    environmentName,
    initialStep?.repository,
    initialStep?.target,
  );
  useTitlePart(
    initialStep && `${initialStep.target} (${initialStep.repository})`,
  );
  useSetActiveTarget(target);
  const { ref, width, height } = useResizeObserver<HTMLDivElement>();
  if (!run || !target) {
    return <Loading />;
  } else {
    const isRunning = Object.values(run.steps).some((s) =>
      Object.values(s.executions).some((e) => !e.result),
    );
    return (
      <HoverContext>
        <div className="flex flex-1 overflow-hidden">
          <div className="grow flex flex-col">
            <TargetHeader
              target={target}
              projectId={projectId!}
              runId={runId}
              environmentName={environmentName}
              isRunning={isRunning}
            />
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
            environmentName={environmentName!}
            className="w-[400px] shrink-0"
          />
        </div>
      </HoverContext>
    );
  }
}

export const useContext = useOutletContext<OutletContext>;
