import { useMemo } from "react";
import dagre from "dagre";
import classNames from "classnames";
import { Link } from "react-router-dom";
import { max } from "lodash";
import { IconArrowForward, IconArrowForwardUp } from "@tabler/icons-react";

import * as models from "../models";
import { buildUrl } from "../utils";

function buildGraph(
  run: models.Run,
  activeStepId: string | undefined,
  activeAttemptNumber: number | undefined
) {
  const g = new dagre.graphlib.Graph();
  g.setGraph({ rankdir: "LR", ranksep: 40, nodesep: 40 });
  g.setDefaultEdgeLabel(function () {
    return {};
  });

  const initialStepId = Object.keys(run.steps).find(
    (id) => !run.steps[id].parentId
  )!;
  let stepId = activeStepId || initialStepId;
  const stepAttempts = { [stepId]: activeStepId && activeAttemptNumber };
  while (run.steps[stepId].parentId) {
    const parentId = run.steps[stepId].parentId!;
    stepId = Object.keys(run.steps).find(
      (id) => parentId in run.steps[id].executions
    )!;
    stepAttempts[stepId] = run.steps[stepId].executions[parentId].sequence;
  }

  if (run.parent) {
    const step = run.steps[stepId];
    const attemptNumber =
      stepAttempts[stepId] ||
      max(Object.values(step.executions).map((e) => e.sequence));
    const nodeId = attemptNumber ? `${stepId}/${attemptNumber}` : stepId;

    g.setNode(run.parent.runId, { width: 160, height: 50 });
    g.setEdge(run.parent.runId, nodeId);
  }

  const traverse = (stepId: string) => {
    const step = run.steps[stepId];
    const attemptNumber =
      stepAttempts[stepId] ||
      max(Object.values(step.executions).map((e) => e.sequence));
    const nodeId = attemptNumber ? `${stepId}/${attemptNumber}` : stepId;
    g.setNode(nodeId, { width: 160, height: 50 });
    if (step.parentId) {
      const parentId = step.parentId;
      const parentStepId = Object.keys(run.steps).find(
        (id) => parentId in run.steps[id].executions
      )!;
      const parentSequence =
        run.steps[parentStepId].executions[parentId].sequence;
      const parentNodeId = `${parentStepId}/${parentSequence}`;
      g.setEdge(parentNodeId, nodeId);
    }
    const executionId = Object.keys(step.executions).find(
      (id) => step.executions[id].sequence == attemptNumber
    );
    if (executionId) {
      const children = step.executions[executionId].children;
      if (children && Object.keys(children).length) {
        Object.entries(children).forEach(([runId, target]) => {
          g.setNode(runId, { width: 160, height: 50 });
          g.setEdge(nodeId, runId);
        });
      }
      Object.keys(run.steps)
        .filter((stepId) => run.steps[stepId].parentId == executionId)
        .forEach((stepId) => traverse(stepId));
    }
  };

  traverse(stepId);
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
      className="absolute flex items-center"
      style={{
        left: node.x - node.width / 2 + offset,
        top: node.y - node.height / 2 + offset,
        width: node.width,
        height: node.height,
      }}
    >
      <Link
        to={buildUrl(`/projects/${projectId}/runs/${runId}`, {
          environment: environmentName,
          step: isActive ? undefined : stepId,
          attempt: isActive ? undefined : attemptNumber,
        })}
        className={classNames(
          "flex-1 items-center border block rounded p-2 truncate",
          classNameForResult(
            attempt?.result || undefined,
            !!step.cachedExecutionId
          ),
          isActive && "ring ring-offset-2 ring-cyan-400",
          { "font-bold": !step.parentId }
        )}
      >
        <span className="font-mono">{step.target}</span>
      </Link>
    </div>
  );
}

type RunNodeProps = {
  node: dagre.Node;
  offset: number;
  projectId: string;
  runId: string;
  environmentName: string | undefined;
  direction: "in" | "out";
};

function RunNode({
  node,
  offset,
  projectId,
  runId,
  environmentName,
  direction,
}: RunNodeProps) {
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
        to={buildUrl(`/projects/${projectId}/runs/${runId}`, {
          environment: environmentName,
        })}
        className="flex-1 flex gap-1 items-center border rounded p-2 bg-white"
      >
        {direction == "out" && <IconArrowForwardUp size={20} />}
        <div className="flex-1 truncate">
          <span className="font-mono">{runId}</span>
        </div>
        {direction == "in" && <IconArrowForward size={20} />}
      </Link>
    </div>
  );
}

type EdgeProps = {
  edge: dagre.GraphEdge;
  offset: number;
};

function Edge({ edge, offset: o }: EdgeProps) {
  const {
    points: [a, b, c],
  } = edge;
  return (
    <path
      className="stroke-slate-200"
      fill="none"
      strokeWidth={5}
      d={`M ${a.x + o} ${a.y + o} Q ${b.x + o} ${b.y + o} ${c.x + o} ${
        c.y + o
      }`}
    />
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
          if (node) {
            const parts = nodeId.split("/", 2);
            const stepId = parts[0];
            const step = run.steps[stepId];
            if (step) {
              const attemptNumber =
                parts.length > 1 ? parseInt(parts[1], 10) : undefined;
              return (
                <StepNode
                  key={nodeId}
                  node={node}
                  offset={offset}
                  stepId={stepId}
                  step={step}
                  attemptNumber={attemptNumber}
                  projectId={projectId}
                  runId={runId}
                  environmentName={environmentName}
                  isActive={
                    nodeId ==
                    (activeAttemptNumber
                      ? `${activeStepId}/${activeAttemptNumber}`
                      : activeStepId)
                  }
                />
              );
            } else {
              return (
                <RunNode
                  key={nodeId}
                  node={node}
                  offset={offset}
                  projectId={projectId}
                  runId={nodeId}
                  environmentName={environmentName}
                  direction={nodeId == run.parent?.runId ? "in" : "out"}
                />
              );
            }
          } else {
            return null;
          }
        })}
      </div>
    </div>
  );
}
