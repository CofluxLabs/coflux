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
      g.setEdge(executionIdToStepId[step.parentId], step.id);
    }
  });

  return g;
}

function classNameForResult(result: models.Result | null, isCached: boolean, open: boolean) {
  if (isCached) {
    return 'border-gray-300 bg-gray-50';
  } else {
    const color = !result ? 'blue' : result.type <= 2 ? 'gray' : result.type == 3 ? 'red' : 'yellow';
    return classNames(`shadow border-${color}-400 `, open ? `bg-${color}-200` : `bg-${color}-100 hover:bg-${color}-200`);
  }
}

type ArrowProps = {
  nodeWidth: number;
  size: number;
}

function Arrow({ nodeWidth, size }: ArrowProps) {
  const left = nodeWidth / 2 - size + 20;
  return (
    <Fragment>
      <div className="absolute" style={{ left: left, top: -size, borderWidth: `0 ${size}px ${size}px`, borderColor: '#fff transparent', width: 0, zIndex: 1 }} />
      <div className="absolute" style={{ left: left - 1, top: -size - 1, borderWidth: `0 ${size + 1}px ${size + 1}px`, borderColor: '#9ca3af transparent', width: 0, zIndex: 0 }} />
    </Fragment>
  );
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
          <Popover.Button className={classNames('flex-1 flex items-center border rounded p-2', classNameForResult(latestExecution?.result || null, !!step.cachedStep, open))}>
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
            <Popover.Panel
              className="absolute z-10 w-screen transform max-w-md rounded shadow-2xl border border-gray-400 bg-white"
              style={{ marginTop: node.height + 8, marginLeft: -20 }}
            >
              <Arrow nodeWidth={node.width} size={12} />
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
  const { points: [a, b, c] } = edge;
  return (
    <path
      className="stroke-current text-gray-400"
      fill="none"
      d={`M ${a.x} ${a.y} Q ${b.x} ${b.y} ${c.x} ${c.y}`}
    />
  );
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