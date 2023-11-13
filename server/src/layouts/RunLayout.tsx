import classNames from "classnames";
import { Fragment, ReactNode, useCallback } from "react";
import {
  NavLink,
  Outlet,
  useNavigate,
  useOutletContext,
  useParams,
  useSearchParams,
} from "react-router-dom";
import { Transition } from "@headlessui/react";
import useResizeObserver from "use-resize-observer";

import * as models from "../models";
import TaskHeader from "../components/TaskHeader";
import { useSetActiveTarget } from "./ProjectLayout";
import StepDetail from "../components/StepDetail";
import usePrevious from "../hooks/usePrevious";
import { buildUrl } from "../utils";
import Loading from "../components/Loading";
import { useRunTopic, useTaskTopic } from "../topics";

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
        params
      )}
      end={true}
      className={({ isActive }) =>
        classNames(
          "px-2 py-1",
          isActive && "inline-block border-b-4 border-slate-500"
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
  onRerunStep: (stepId: string, environmentName: string) => Promise<number>;
};

function DetailPanel({
  runId,
  stepId,
  attemptNumber,
  run,
  projectId,
  environmentName,
  className,
  onRerunStep,
}: DetailPanelProps) {
  const previousStepId = usePrevious(stepId);
  const stepIdOrPrevious = stepId || previousStepId;
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
          "bg-slate-100 border-l border-slate-200 flex shadow-lg"
        )}
      >
        {stepIdOrPrevious && (
          <StepDetail
            runId={runId}
            stepId={stepIdOrPrevious}
            sequence={attemptNumber || 0}
            run={run}
            projectId={projectId}
            environmentName={environmentName}
            className="flex-1"
            onRerunStep={onRerunStep}
          />
        )}
      </div>
    </Transition>
  );
}

type OutletContext = {
  run: models.Run;
  width: number | undefined;
  height: number | undefined;
};

export default function RunLayout() {
  const { project: projectId, run: runId } = useParams();
  const [searchParams] = useSearchParams();
  const activeStepId = searchParams.get("step") || undefined;
  const activeAttemptNumber = searchParams.has("attempt")
    ? parseInt(searchParams.get("attempt")!, 10)
    : undefined;
  const environmentName = searchParams.get("environment") || undefined;
  const [run, rerunStep] = useRunTopic(projectId, environmentName, runId);
  const initialStep = run && Object.values(run.steps).find((j) => !j.parentId);
  const [task, startRun] = useTaskTopic(
    projectId,
    environmentName,
    initialStep?.repository,
    initialStep?.target
  );
  const navigate = useNavigate();
  // TODO: remove duplication (TaskPage)
  const handleRun = useCallback(
    (parameters: ["json", string][]) => {
      return startRun(parameters).then((runId) => {
        navigate(
          buildUrl(`/projects/${projectId}/runs/${runId}`, {
            environment: environmentName,
          })
        );
      });
    },
    [startRun]
  );
  useSetActiveTarget(task);
  const { ref, width, height } = useResizeObserver<HTMLDivElement>();
  if (!run || !task) {
    return <Loading />;
  } else {
    return (
      <div className="flex flex-1">
        <div className="grow flex flex-col">
          <TaskHeader
            task={task}
            projectId={projectId!}
            runId={runId}
            environmentName={environmentName}
            onRun={handleRun}
          />
          <div className="border-b px-4">
            <Tab page={null}>Graph</Tab>
            <Tab page="timeline">Timeline</Tab>
            <Tab page="logs">Logs</Tab>
          </div>
          <div className="flex-1 basis-0 overflow-auto" ref={ref}>
            <Outlet context={{ run, width, height }} />
          </div>
        </div>
        <DetailPanel
          runId={runId!}
          stepId={activeStepId}
          attemptNumber={activeAttemptNumber}
          run={run}
          projectId={projectId!}
          environmentName={environmentName!}
          className="w-1/3"
          onRerunStep={rerunStep}
        />
      </div>
    );
  }
}

export const useContext = useOutletContext<OutletContext>;
