import { Fragment, useMemo } from "react";
import dagre from "@dagrejs/dagre";
import classNames from "classnames";
import { Link } from "react-router-dom";
import { max, sortBy } from "lodash";
import { IconArrowForward, IconArrowUpRight } from "@tabler/icons-react";

import * as models from "../models";
import { buildUrl } from "../utils";

type Node =
  | {
      type: "step";
      step: models.Step;
      stepId: string;
      attemptNumber: number | undefined;
    }
  | {
      type: "parent";
      parent: models.Parent;
    }
  | {
      type: "child";
      child: models.Child;
      runId: string;
    };

function chooseStepAttempts(
  run: models.Run,
  activeStepId: string | undefined,
  activeAttemptNumber: number | undefined
) {
  const stepAttempts: Record<string, number> = {};
  if (activeStepId && activeAttemptNumber) {
    if (activeAttemptNumber) {
      stepAttempts[activeStepId] = activeAttemptNumber;
    }
    let stepId = activeStepId;
    while (run.steps[stepId].parentId) {
      const parentId = run.steps[stepId].parentId!;
      stepId = Object.keys(run.steps).find(
        (id) => parentId in run.steps[id].executions
      )!;
      stepAttempts[stepId] = run.steps[stepId].executions[parentId].sequence;
    }
  }
  return stepAttempts;
}

function traverseRun(
  run: models.Run,
  stepAttempts: Record<string, number>,
  callback: (stepId: string, executionId: string | undefined) => void,
  parentId?: string
) {
  Object.keys(run.steps)
    .filter((id) => run.steps[id].parentId == parentId)
    .forEach((stepId) => {
      const step = run.steps[stepId];
      const attemptNumber =
        stepAttempts[stepId] ||
        max(Object.values(step.executions).map((e) => e.sequence));
      const executionId = Object.keys(step.executions).find(
        (id) => step.executions[id].sequence == attemptNumber
      );
      callback(stepId, executionId);
      if (executionId) {
        traverseRun(run, stepAttempts, callback, executionId);
      }
    });
}

function buildGraph(
  run: models.Run,
  activeStepId: string | undefined,
  activeAttemptNumber: number | undefined
) {
  const g = new dagre.graphlib.Graph<Node>();
  g.setGraph({ rankdir: "LR", ranksep: 40, nodesep: 40 });

  const stepAttempts = chooseStepAttempts(
    run,
    activeStepId,
    activeAttemptNumber
  );

  if (run.parent) {
    const initialStepId = sortBy(
      Object.keys(run.steps).filter((id) => !run.steps[id].parentId),
      (stepId) => run.steps[stepId].createdAt
    )[0];
    g.setNode(run.parent.runId, {
      width: 160,
      height: 50,
      type: "parent",
      parent: run.parent,
    });
    g.setEdge(run.parent.runId, initialStepId, {
      type: "parent",
      weight: 1000,
    });
  }

  traverseRun(
    run,
    stepAttempts,
    (stepId: string, executionId: string | undefined) => {
      const step = run.steps[stepId];
      const execution = executionId ? step.executions[executionId] : undefined;
      if (execution) {
        execution.dependencies.forEach((dependencyId) => {
          const dependencyStepId = Object.keys(run.steps).find(
            (id) => dependencyId in run.steps[id].executions
          );
          if (dependencyStepId) {
            g.setEdge(dependencyStepId, stepId, {
              type: "dependency",
              weight: 100,
            });
          } else {
            // TODO: handle other dependency?
          }
        });
      }
    }
  );

  traverseRun(
    run,
    stepAttempts,
    (stepId: string, executionId: string | undefined) => {
      const step = run.steps[stepId];
      const execution = executionId ? step.executions[executionId] : undefined;
      g.setNode(stepId, {
        width: 160,
        height: 50,
        type: "step",
        step,
        stepId: stepId,
        attemptNumber: execution?.sequence,
      });
      if (step.parentId) {
        const parentId = step.parentId;
        const parentStepId = Object.keys(run.steps).find(
          (id) => parentId in run.steps[id].executions
        )!;
        const parent = run.steps[parentStepId].executions[parentId];
        if (
          step.cachedExecutionId &&
          parent.dependencies.includes(step.cachedExecutionId)
        ) {
          g.setEdge(stepId, parentStepId, {
            type: "dependency",
            weight: 100,
          });
        } else if (executionId && !parent.dependencies.includes(executionId)) {
          g.setEdge(parentStepId, stepId, {
            type: "parent",
            weight: 1,
          });
        }
      }
    }
  );

  traverseRun(
    run,
    stepAttempts,
    (stepId: string, executionId: string | undefined) => {
      const step = run.steps[stepId];
      const execution = executionId ? step.executions[executionId] : undefined;
      if (execution) {
        const children = execution.children;
        if (children && Object.keys(children).length) {
          Object.entries(children).forEach(([runId, child]) => {
            g.setNode(runId, {
              width: 160,
              height: 50,
              type: "child",
              child,
              runId,
            });
            if (
              child.executionId &&
              execution.dependencies.includes(child.executionId)
            ) {
              g.setEdge(runId, stepId, { type: "dependency", weight: 2 });
            } else {
              g.setEdge(stepId, runId, { type: "child", weight: 2 });
            }
          });
        }
      }
    }
  );

  dagre.layout(g);
  return g;
}

function classNameForResult(
  result: models.Result | undefined,
  isCached: boolean
) {
  if (isCached) {
    return "border-slate-200 bg-slate-50";
  } else if (result?.type == "duplicated") {
    return "border-slate-200 bg-slate-50";
  } else if (!result) {
    return "border-blue-400 bg-blue-100";
  } else if (result.type == "error") {
    return "border-red-400 bg-red-100";
  } else if (result.type == "abandoned" || result.type == "cancelled") {
    return "border-yellow-400 bg-yellow-100";
  } else {
    return "border-slate-400 bg-slate-100";
  }
}

type StepNodeProps = {
  node: dagre.Node;
  offset: number;
  stepId: string;
  step: models.Step;
  attemptNumber: number | undefined;
  projectId: string;
  runId: string;
  environmentName: string | undefined;
  isActive: boolean;
};

function StepNode({
  node,
  offset,
  stepId,
  step,
  attemptNumber,
  projectId,
  runId,
  environmentName,
  isActive,
}: StepNodeProps) {
  const attempt = Object.values(step.executions).find(
    (e) => e.sequence == attemptNumber
  );
  return (
    <div
      className="absolute"
      style={{
        left: node.x - node.width / 2 + offset,
        top: node.y - node.height / 2 + offset,
        width: node.width,
        height: node.height,
      }}
    >
      {Object.keys(step.executions).length > 1 && (
        <div className="absolute w-full h-full border border-slate-300 bg-white rounded -top-1 -right-1"></div>
      )}
      <Link
        to={buildUrl(`/projects/${projectId}/runs/${runId}/graph`, {
          environment: environmentName,
          step: isActive ? undefined : stepId,
          attempt: isActive ? undefined : attemptNumber,
        })}
        className={classNames(
          "absolute w-full h-full flex flex-col border rounded px-2 py-1 truncate ring-offset-2 ",
          classNameForResult(
            attempt?.result || undefined,
            !!step.cachedExecutionId
          ),
          isActive ? "ring ring-cyan-400" : "hover:ring hover:ring-slate-200"
        )}
      >
        <span
          className={classNames(
            "font-mono text-sm",
            !step.parentId && "font-bold"
          )}
        >
          {step.target}
        </span>
        {!step.parentId && (
          <span className="text-xs text-slate-500">{runId}</span>
        )}
      </Link>
    </div>
  );
}

type ParentNodeProps = {
  node: dagre.Node;
  offset: number;
  projectId: string;
  parent: models.Parent;
  environmentName: string | undefined;
};

function ParentNode({
  node,
  offset,
  projectId,
  parent,
  environmentName,
}: ParentNodeProps) {
  return (
    <div
      className="absolute flex"
      style={{
        left: node.x - node.width / 2 + offset,
        top: node.y - node.height / 2 + offset,
        width: node.width,
        height: node.height,
      }}
    >
      <Link
        to={buildUrl(`/projects/${projectId}/runs/${parent.runId}`, {
          environment: environmentName,
        })}
        className="flex-1 flex gap-2 items-center border border-dashed border-slate-300 rounded px-2 py-1 bg-white"
      >
        <div className="flex-1 flex flex-col truncate">
          <span className="font-mono font-bold text-slate-400 text-sm">
            {parent.target}
          </span>
          <span className="text-xs text-slate-400">{parent.runId}</span>
        </div>
        <IconArrowForward size={20} className="text-slate-400" />
      </Link>
    </div>
  );
}

type ChildNodeProps = {
  node: dagre.Node;
  offset: number;
  projectId: string;
  runId: string;
  child: models.Child;
  environmentName: string | undefined;
};

function ChildNode({
  node,
  offset,
  projectId,
  runId,
  child,
  environmentName,
}: ChildNodeProps) {
  return (
    <div
      className="absolute flex"
      style={{
        left: node.x - node.width / 2 + offset,
        top: node.y - node.height / 2 + offset,
        width: node.width,
        height: node.height,
      }}
    >
      <Link
        to={buildUrl(`/projects/${projectId}/runs/${runId}/graph`, {
          environment: environmentName,
        })}
        className="flex-1 flex gap-2 items-center border border-slate-300 rounded px-2 py-1 bg-white"
      >
        <div className="flex-1 flex flex-col truncate">
          <span className="font-mono font-bold text-slate-500 text-sm">
            {child.target}
          </span>
          <span className="text-xs text-slate-400">{runId}</span>
        </div>
        <IconArrowUpRight size={20} className="text-slate-400" />
      </Link>
    </div>
  );
}

type EdgeProps = {
  edge: dagre.GraphEdge;
  offset: number;
};

function Edge({ edge, offset: o }: EdgeProps) {
  const { points, type } = edge;
  return (
    <Fragment>
      <path
        className={
          type == "dependency" ? "stroke-slate-300" : "stroke-slate-200"
        }
        fill="none"
        strokeWidth={type == "dependency" ? 2 : 2}
        strokeDasharray={type == "dependency" ? undefined : "5"}
        d={`M ${points.map(({ x, y }) => `${x + o} ${y + o}`).join(" ")}`}
      />
      <circle
        cx={points[points.length - 1].x + o}
        cy={points[points.length - 1].y + o}
        r={3}
        className={type == "dependency" ? "fill-slate-300" : "fill-slate-200"}
      />
    </Fragment>
  );
}

type Props = {
  runId: string;
  run: models.Run;
  width: number | undefined;
  height: number | undefined;
  projectId: string;
  environmentName: string | undefined;
  activeStepId: string | undefined;
  activeAttemptNumber: number | undefined;
  offset?: number;
};

export default function RunGraph({
  runId,
  run,
  width,
  height,
  projectId,
  environmentName,
  activeStepId,
  activeAttemptNumber,
  offset = 20,
}: Props) {
  const graph = useMemo(
    () => buildGraph(run, activeStepId, activeAttemptNumber),
    [run, activeStepId, activeAttemptNumber]
  );
  return (
    <div className="relative">
      <svg
        width={Math.max(graph.graph().width! + 2 * offset, width || 0)}
        height={Math.max(graph.graph().height! + 2 * offset, height || 0)}
        className="absolute"
      >
        <defs>
          <pattern
            id="grid"
            width={16}
            height={16}
            patternUnits="userSpaceOnUse"
          >
            <circle cx={10} cy={10} r={0.5} className="fill-slate-400" />
          </pattern>
        </defs>
        <rect width="100%" height="100%" fill="url(#grid)" />
        {graph.edges().flatMap((edge) => {
          return (
            <Edge
              key={`${edge.v}-${edge.w}`}
              edge={graph.edge(edge)}
              offset={offset}
            />
          );
        })}
      </svg>
      <div className="absolute">
        {graph.nodes().map((nodeId) => {
          const node = graph.node(nodeId);
          switch (node.type) {
            case "step":
              return (
                <StepNode
                  key={nodeId}
                  node={node}
                  offset={offset}
                  stepId={node.stepId}
                  step={node.step}
                  attemptNumber={node.attemptNumber}
                  projectId={projectId}
                  runId={runId}
                  environmentName={environmentName}
                  isActive={nodeId == activeStepId}
                />
              );
            case "parent":
              return (
                <ParentNode
                  key={nodeId}
                  node={node}
                  offset={offset}
                  projectId={projectId}
                  parent={node.parent}
                  environmentName={environmentName}
                />
              );
            case "child":
              return (
                <ChildNode
                  key={nodeId}
                  node={node}
                  offset={offset}
                  projectId={projectId}
                  runId={node.runId}
                  child={node.child}
                  environmentName={environmentName}
                />
              );
          }
        })}
      </div>
    </div>
  );
}
