import { useMemo } from "react";
import dagre from "dagre";
import classNames from "classnames";
import { Link } from "react-router-dom";

import * as models from "../models";
import { buildUrl } from "../utils";
import { max } from "lodash";

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
    // step.attempts[attemptNumber]?.runIds.forEach((runId) => {
    //   g.setNode(runId, { width: 160, height: 50 });
    //   g.setEdge(nodeId, runId);
    // });
    const executionId = Object.keys(step.executions).find(
      (id) => step.executions[id].sequence == attemptNumber
    );
    if (executionId) {
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
    return "border-gray-300 bg-gray-50";
  } else if (!result) {
    return "border-blue-400 bg-blue-100";
  } else if (result.type == "error") {
    return "border-red-400 bg-red-100";
  } else if (result.type == "abandoned") {
    return "border-yellow-400 bg-yellow-100";
  } else {
    return "border-gray-400 bg-gray-100";
  }
}

type StepNodeProps = {
  node: dagre.Node;
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
        left: node.x - node.width / 2,
        top: node.y - node.height / 2,
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
          isActive && "ring ring-offset-2",
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
  projectId: string;
  runId: string;
  environmentName: string | undefined;
};

function RunNode({ node, projectId, runId, environmentName }: RunNodeProps) {
  return (
    <div
      className="absolute flex"
      style={{
        left: node.x - node.width / 2,
        top: node.y - node.height / 2,
        width: node.width,
        height: node.height,
      }}
    >
      <Link
        to={buildUrl(`/projects/${projectId}/runs/${runId}`, {
          environment: environmentName,
        })}
        className="flex-1 flex items-center border rounded p-2"
      >
        <div className="flex-1 truncate">
          <span className="font-mono">{runId}</span>
        </div>
      </Link>
    </div>
  );
}

type EdgeProps = {
  edge: dagre.GraphEdge;
};

function Edge({ edge }: EdgeProps) {
  const {
    points: [a, b, c],
  } = edge;
  return (
    <path
      className="stroke-current text-gray-200"
      fill="none"
      strokeWidth={5}
      d={`M ${a.x} ${a.y} Q ${b.x} ${b.y} ${c.x} ${c.y}`}
    />
  );
}

type Props = {
  runId: string;
  run: models.Run;
  projectId: string;
  environmentName: string | undefined;
  activeStepId: string | undefined;
  activeAttemptNumber: number | undefined;
};

export default function RunGraph({
  runId,
  run,
  projectId,
  environmentName,
  activeStepId,
  activeAttemptNumber,
}: Props) {
  const graph = useMemo(
    () => buildGraph(run, activeStepId, activeAttemptNumber),
    [run, activeStepId, activeAttemptNumber]
  );
  return (
    <div className="relative">
      <svg
        width={graph.graph().width}
        height={graph.graph().height}
        className="absolute"
      >
        {graph.edges().flatMap((edge) => {
          return <Edge key={`${edge.v}-${edge.w}`} edge={graph.edge(edge)} />;
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
                  projectId={projectId}
                  runId={nodeId}
                  environmentName={environmentName}
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
