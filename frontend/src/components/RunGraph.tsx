import React, { useEffect, useState } from 'react';
import dagre from 'dagre';
import classNames from 'classnames';
import Link from 'next/link';

import * as models from '../models';

function buildGraph(run: models.Run, activeStepId: string | null, activeAttemptNumber: number | null) {
  const g = new dagre.graphlib.Graph();
  g.setGraph({ rankdir: 'LR', ranksep: 40, nodesep: 40 });
  g.setDefaultEdgeLabel(function () { return {}; });

  const seen: string[] = [];

  const traverse = (stepId: string, attemptNumber: number) => {
    if (seen.indexOf(stepId) < 0) {
      seen.push(stepId);
      const step = run.steps[stepId];
      const nodeId = `${step.id}/${attemptNumber}`;
      g.setNode(nodeId, { width: 160, height: 50 });
      if (step.parent) {
        g.setEdge(`${step.parent.stepId}/${step.parent.attempt}`, nodeId);
      }
      Object.values(step.attempts).forEach((attempt) => {
        attempt.runIds.forEach((runId) => {
          g.setNode(runId, { width: 160, height: 50 });
          g.setEdge(nodeId, runId);
        });
      });
      if (step.parent) {
        traverse(step.parent.stepId, step.parent.attempt);
      }
      Object.values(run.steps)
        .filter((s) => s.parent?.stepId == step.id && s.parent?.attempt == attemptNumber)
        .forEach((child) => {
          const childAttemptNumber = child.id == activeStepId && activeAttemptNumber || Object.keys(child.attempts).length;
          traverse(child.id, childAttemptNumber);
        });
    }
  };

  const step = activeStepId && run.steps[activeStepId] || Object.values(run.steps).find((s) => !s.parent)!;
  const attemptNumber = step.id == activeStepId && activeAttemptNumber || Object.keys(step.attempts).length;
  traverse(step.id, attemptNumber);

  return g;
}

function classNameForResult(result: models.Result | null, isCached: boolean) {
  if (isCached) {
    return 'border-gray-300 bg-gray-50';
  } else {
    const color = !result ? 'blue' : result.type == 3 ? 'red' : result.type == 4 ? 'yellow' : 'gray';
    return `shadow border-${color}-400 bg-${color}-100`;
  }
}

type StepNodeProps = {
  node: dagre.Node;
  step: models.Step;
  attemptNumber: number;
  runId: string;
  isActive: boolean;
}

function StepNode({ node, step, attemptNumber, runId, isActive }: StepNodeProps) {
  const attempt = step.attempts[attemptNumber];
  return (
    <div
      className="absolute flex items-center"
      style={{ left: node.x - node.width / 2, top: node.y - node.height / 2, width: node.width, height: node.height }}
    >
      <Link href={`/projects/project_1/runs/${runId}${isActive ? '' : `#${step.id}/${attemptNumber}`}`}>
        <a
          className={
            classNames(
              'flex-1 items-center border block rounded p-2 truncate',
              classNameForResult(attempt?.result || null, !!step.cached),
              isActive && 'ring ring-offset-2',
              { 'font-bold': !step.parent }
            )
          }
        >
          <span className="font-mono">{step.target}</span>
        </a>
      </Link>
    </div>
  );
}

type RunNodeProps = {
  node: dagre.Node;
  runId: string;
}

function RunNode({ node, runId }: RunNodeProps) {
  return (
    <div
      className="absolute flex"
      style={{ left: node.x - node.width / 2, top: node.y - node.height / 2, width: node.width, height: node.height }}
    >
      <Link href={`/projects/project_1/runs/${runId}`}>
        <a className="flex-1 flex items-center border rounded p-2">
          <div className="flex-1 truncate">
            <span className="font-mono">{runId}</span>
          </div>
        </a>
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
  activeStepId: string | null;
  activeAttemptNumber: number | null;
}

export default function RunGraph({ run, activeStepId, activeAttemptNumber }: Props) {
  const [graph, setGraph] = useState<dagre.graphlib.Graph>();
  useEffect(() => {
    const graph = buildGraph(run, activeStepId, activeAttemptNumber);
    dagre.layout(graph);
    setGraph(graph);
  }, [run, activeStepId, activeAttemptNumber]);
  if (graph) {
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
                    runId={run.id}
                    isActive={nodeId == `${activeStepId}/${activeAttemptNumber}`}
                  />
                );
              } else {
                return (
                  <RunNode key={nodeId} node={node} runId={nodeId} />
                );
              }
            } else {
              return null;
            }
          })}
        </div>
      </div>
    );
  } else {
    return <p>Loading...</p>;
  }
}