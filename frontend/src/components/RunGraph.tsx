import { useMemo } from 'react';
import dagre from 'dagre';
import classNames from 'classnames';
import { Link } from 'react-router-dom';

import * as models from '../models';
import { buildUrl } from '../utils';

function buildGraph(run: models.Run, activeStepId: string | undefined, activeAttemptNumber: number | undefined) {
  const g = new dagre.graphlib.Graph();
  g.setGraph({ rankdir: 'LR', ranksep: 40, nodesep: 40 });
  g.setDefaultEdgeLabel(function () { return {}; });

  const initialStep = Object.values(run.steps).find((s) => !s.parent)!;
  let step = activeStepId && run.steps[activeStepId] || initialStep;
  const stepAttempts = { [step.id]: activeStepId && activeAttemptNumber };
  while (step.parent) {
    stepAttempts[step.parent.stepId] = step.parent.attempt;
    step = step.parent && run.steps[step.parent.stepId];
  }

  const traverse = (stepId: string) => {
    const step = run.steps[stepId];
    const attemptNumber = stepAttempts[stepId] || Object.keys(step.attempts).length;
    const nodeId = `${step.id}/${attemptNumber}`;
    g.setNode(nodeId, { width: 160, height: 50 });
    if (step.parent) {
      const parentNodeId = `${step.parent.stepId}/${step.parent.attempt}`;
      g.setEdge(parentNodeId, nodeId);
    }
    step.attempts[attemptNumber]?.runIds.forEach((runId) => {
      g.setNode(runId, { width: 160, height: 50 });
      g.setEdge(nodeId, runId);
    });
    Object.values(run.steps)
      .filter((s) => s.parent?.stepId == step.id && s.parent?.attempt == attemptNumber)
      .forEach((child) => traverse(child.id));
  };

  traverse(step.id);
  dagre.layout(g);
  return g;
}

function classNameForResult(result: models.Result | undefined, isCached: boolean) {
  if (isCached) {
    return 'border-gray-300 bg-gray-50';
  } else if (!result) {
    return 'border-blue-400 bg-blue-100';
  } else if (result.type == 3) {
    return 'border-red-400 bg-red-100';
  } else if (result.type == 4) {
    return 'border-yellow-400 bg-yellow-100'
  } else {
    return 'border-gray-400 bg-gray-100';
  }
}

type StepNodeProps = {
  node: dagre.Node;
  step: models.Step;
  attemptNumber: number;
  projectId: string;
  runId: string;
  environmentName: string | undefined;
  isActive: boolean;
}

function StepNode({ node, step, attemptNumber, projectId, runId, environmentName, isActive }: StepNodeProps) {
  const attempt = step.attempts[attemptNumber];
  return (
    <div
      className="absolute flex items-center"
      style={{ left: node.x - node.width / 2, top: node.y - node.height / 2, width: node.width, height: node.height }}
    >
      <Link
        to={buildUrl(`/projects/${projectId}/runs/${runId}`, { environment: environmentName, step: isActive ? undefined : step.id, attempt: isActive ? undefined : attemptNumber })}
        className={
          classNames(
            'flex-1 items-center border block rounded p-2 truncate',
            classNameForResult(attempt?.result || undefined, !!step.cached),
            isActive && 'ring ring-offset-2',
            { 'font-bold': !step.parent }
          )
        }
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
}

function RunNode({ node, projectId, runId, environmentName }: RunNodeProps) {
  return (
    <div
      className="absolute flex"
      style={{ left: node.x - node.width / 2, top: node.y - node.height / 2, width: node.width, height: node.height }}
    >
      <Link to={buildUrl(`/projects/${projectId}/runs/${runId}`, { environment: environmentName })} className="flex-1 flex items-center border rounded p-2">
        <div className="flex-1 truncate">
          <span className="font-mono">{runId}</span>
        </div>
      </Link>
    </div>
  );
}

type EdgeProps = {
  edge: dagre.GraphEdge;
}

function Edge({ edge }: EdgeProps) {
  const { points: [a, b, c] } = edge;
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
  run: models.Run;
  projectId: string;
  environmentName: string | undefined;
  activeStepId: string | undefined;
  activeAttemptNumber: number | undefined;
}

export default function RunGraph({ run, projectId, environmentName, activeStepId, activeAttemptNumber }: Props) {
  const graph = useMemo(() => buildGraph(run, activeStepId, activeAttemptNumber), [run, activeStepId, activeAttemptNumber]);
  return (
    <div className="relative">
      <svg width={graph.graph().width} height={graph.graph().height} className="absolute">
        {graph.edges().flatMap((edge) => {
          return <Edge key={`${edge.v}-${edge.w}`} edge={graph.edge(edge)} />
        })}
      </svg>
      <div className="absolute">
        {graph.nodes().map((nodeId) => {
          const node = graph.node(nodeId);
          if (node) {
            const parts = nodeId.split('/', 2);
            const step = run.steps[parts[0]];
            if (step) {
              const attemptNumber = parseInt(parts[1], 10);
              return (
                <StepNode
                  key={nodeId}
                  node={node}
                  step={step}
                  attemptNumber={attemptNumber}
                  projectId={projectId}
                  runId={run.id}
                  environmentName={environmentName}
                  isActive={nodeId == `${activeStepId}/${activeAttemptNumber}`}
                />
              );
            } else {
              return (
                <RunNode key={nodeId} node={node} projectId={projectId} runId={nodeId} environmentName={environmentName} />
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