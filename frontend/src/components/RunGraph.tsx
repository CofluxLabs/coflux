import React, { Fragment, useEffect, useState } from 'react';
import dagre from 'dagre';
import classNames from 'classnames';
import { Popover, Transition } from '@headlessui/react';

import * as models from '../models';
import StepInfo from './StepInfo';

function buildGraph(run: models.Run) {
  const g = new dagre.graphlib.Graph();
  g.setGraph({ rankdir: 'LR', ranksep: 40, nodesep: 40 });
  g.setDefaultEdgeLabel(function () { return {}; });

  const executionIdToStepId = run.steps.reduce<Record<string, string>>((ess, step) => {
    return step.executions.reduce((ess, e) => ({ ...ess, [e.id]: step.id }), ess);
  }, {});

  run.steps.forEach((step) => {
    g.setNode(step.id, { width: 160, height: 50 });
    if (step.parentId) {
      g.setEdge(executionIdToStepId[step.parentId], step.id, {});
    }
  });

  return g;
}

function classNameForResult(result: models.Result | null) {
  if (!result) {
    return 'border-blue-400 bg-blue-100 hover:bg-blue-200';
  } else if (result.type <= 2) {
    return 'border-gray-400 bg-gray-100 hover:bg-gray-200';
  } else if (result.type == 3) {
    return 'border-red-400 bg-red-100 hover:bg-red-200';
  } else {
    return 'border-yellow-400 bg-yellow-100 hover:bg-yellow-200';
  }
}

type NodeProps = {
  node: dagre.Node;
  step: models.Step;
}

function Node({ node, step }: NodeProps) {
  const latestExecution = step.executions.length ? step.executions[step.executions.length - 1] : null;
  return (
    <Popover
      className={classNames('absolute flex')}
      style={{ left: node.x - node.width / 2, top: node.y - node.height / 2, width: node.width, height: node.height }}
    >
      {({ open }) => (
        <>
          <Popover.Button className={classNames('flex-1 flex items-center shadow border rounded p-2', classNameForResult(latestExecution?.result || null))}>
            <div className={classNames('flex-1 truncate', { 'font-bold': !step.parentId })}>
              <span className="font-mono">{step.target}</span>
            </div>
          </Popover.Button>
          <Transition
            as={Fragment}
            enter="transition ease-out duration-200"
            enterFrom="opacity-0 translate-y-1"
            enterTo="opacity-100 translate-y-0"
            leave="transition ease-in duration-150"
            leaveFrom="opacity-100 translate-y-0"
            leaveTo="opacity-0 translate-y-1"
          >
            <Popover.Panel className="absolute z-10 mt-2 ml-2 w-screen transform max-w-md rounded shadow-2xl border border-gray-400 bg-white overflow-hidden">
              <StepInfo step={step} />
            </Popover.Panel>
          </Transition>
        </>
      )}
    </Popover>
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