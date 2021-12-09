import React, { useEffect, useState } from 'react';
import dagre from 'dagre';
import classNames from 'classnames';
import { maxBy } from 'lodash';
import Link from 'next/link';

import * as models from '../models';

function buildGraph(run: models.Run) {
  const g = new dagre.graphlib.Graph();
  g.setGraph({ rankdir: 'LR', ranksep: 40, nodesep: 40 });
  g.setDefaultEdgeLabel(function () { return {}; });

  const attemptToStepId = Object.values(run.steps).reduce<Record<string, string>>((ess, step) => {
    return Object.values(step.attempts).reduce((ess, a) => ({ ...ess, [`${step.id}:${a.number}`]: step.id }), ess);
  }, {});

  Object.values(run.steps).forEach((step) => {
    g.setNode(step.id, { width: 160, height: 50 });
    if (step.parent) {
      g.setEdge(attemptToStepId[`${step.parent.stepId}:${step.parent.attempt}`], step.id);
    }
    Object.values(step.attempts).forEach((attempt) => {
      attempt.runIds.forEach((runId) => {
        g.setNode(runId, { width: 160, height: 50 });
        g.setEdge(step.id, runId);
      });
    });
  });

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
  runId: string;
  activeStepId: string | null;
}

function StepNode({ node, step, runId, activeStepId }: StepNodeProps) {
  const latestAttempt = maxBy(Object.values(step.attempts), 'number')
  const open = step.id == activeStepId;
  return (
    <div
      className="absolute flex items-center"
      style={{ left: node.x - node.width / 2, top: node.y - node.height / 2, width: node.width, height: node.height }}
    >
      <Link href={`/projects/project_1/runs/${runId}${open ? '' : `#${step.id}`}`}>
        <a
          className={
            classNames(
              'flex-1 items-center border block rounded p-2 truncate',
              classNameForResult(latestAttempt?.result || null, !!step.cached),
              open && 'ring ring-offset-2',
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
}

export default function RunGraph({ run, activeStepId }: Props) {
  const [graph, setGraph] = useState<dagre.graphlib.Graph>();
  useEffect(() => {
    const graph = buildGraph(run);
    dagre.layout(graph);
    setGraph(graph);
  }, [run]);
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
            const step = run.steps[nodeId];
            if (step) {
              return (
                <StepNode
                  key={nodeId}
                  node={graph.node(nodeId)}
                  step={run.steps[nodeId]}
                  runId={run.id}
                  activeStepId={activeStepId}
                />
              );
            } else {
              return (
                <RunNode key={nodeId} node={graph.node(nodeId)} runId={nodeId} />
              );
            }
          })}
        </div>
      </div>
    );
  } else {
    return <p>Loading...</p>;
  }
}