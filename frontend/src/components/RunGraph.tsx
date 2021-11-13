import React, { useEffect, useState } from 'react';
import dagre from 'dagre';

import * as models from '../models';

function buildGraph(run: models.Run) {
  const g = new dagre.graphlib.Graph();
  g.setGraph({ rankdir: 'LR', ranksep: 40, nodesep: 40 });
  g.setDefaultEdgeLabel(function() { return {}; });

  const executionIdToStepId = run.steps.reduce<Record<string, string>>((ess, step) => {
    return step.executions.reduce((ess, e) => ({ ...ess, [e.id]: step.id }), ess);
  }, {});

  run.steps.forEach((step) => {
    g.setNode(step.id, { width: 140, height: 50 });
    if (step.parentId) {
      g.setEdge(executionIdToStepId[step.parentId], step.id, {  });
    }
  });

  return g;
}

function classNameForResult(result: models.Result | null) {
  if (!result) {
    return 'bg-blue-100 border-blue-400 ';
  } else if (result.type <= 2) {
    return 'bg-gray-100 border-gray-400';
  } else if (result.type == 3) {
    return 'bg-red-100 border-red-400';
  } else {
    return 'bg-yellow-100 border-yellow-400';
  }
}

type NodeProps = {
  node: dagre.Node;
  step: models.Step;
}

function Node({ node, step }: NodeProps) {
  const execution = step.executions.length ? step.executions[step.executions.length - 1] : null;
  const color = classNameForResult(execution?.result || null);
  return (
    <div
      className={`absolute flex items-center justify-center shadow border ${color} rounded p-2`}
      style={{ left: node.x - node.width / 2, top: node.y - node.height / 2, width: node.width, height: node.height}}
    >
      <p className={`truncate ${!step.parentId ? 'font-bold' : ''}`}>
        {step.target}
      </p>
    </div>
  );
}

type EdgeProps = {
  edge: dagre.GraphEdge;
}

function Edge({ edge }: EdgeProps) {
  return (
    <polyline
      className="stroke-current text-gray-400"
      fill="none"
      points={edge.points.map(({ x, y }) => `${x},${y}`).join(' ')}
    />
  )
}

type Props = {
  run: models.Run;
}

export default function RunGraph({ run }: Props) {
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
            const step = run.steps.find((s) => s.id == nodeId);
            return <Node key={nodeId} node={graph.node(nodeId)} step={step!} />
          })}
        </div>
      </div>
    );
  } else {
    return <p>Loading...</p>;
  }
}