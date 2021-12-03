import React, { Fragment, useEffect, useState } from 'react';
import dagre from 'dagre';
import classNames from 'classnames';
import { Popover, Transition } from '@headlessui/react';
import { maxBy } from 'lodash';
import Link from 'next/link';

import * as models from '../models';
import StepInfo from './StepInfo';

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

function classNameForResult(result: models.Result | null, isCached: boolean, open: boolean) {
  if (isCached) {
    return 'border-gray-300 bg-gray-50';
  } else {
    const color = !result ? 'blue' : result.type == 3 ? 'red' : result.type == 4 ? 'yellow' : 'gray';
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
    <Popover
      className={classNames('absolute flex')}
      style={{ left: node.x - node.width / 2, top: node.y - node.height / 2, width: node.width, height: node.height }}
    >
      <Link href={`/projects/project_1/runs/${runId}${open ? '' : `#${step.id}`}`} passHref={true}>
        <a className={classNames('flex-1 flex items-center border rounded p-2', classNameForResult(latestAttempt?.result || null, !!step.cached, open))}>
          <div className={classNames('flex-1 truncate', { 'font-bold': !step.parent })}>
            <span className="font-mono">{step.target}</span>
          </div>
        </a>
      </Link>
      <Transition
        as={Fragment}
        enter="transition ease-out duration-200"
        enterFrom="opacity-0 translate-y-1"
        enterTo="opacity-100 translate-y-0"
        leave="transition ease-in duration-150"
        leaveFrom="opacity-100 translate-y-0"
        leaveTo="opacity-0 translate-y-1"
        show={open}
      >
        <Popover.Panel
          className="absolute z-10 w-screen transform max-w-md rounded shadow-2xl border border-gray-400 bg-white"
          style={{ marginTop: node.height + 8, marginLeft: -20 }}
          static={true}
        >
          <Arrow nodeWidth={node.width} size={12} />
          <StepInfo step={step} />
        </Popover.Panel>
      </Transition>
    </Popover>
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