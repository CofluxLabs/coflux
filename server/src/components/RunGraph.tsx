import {
  Fragment,
  useCallback,
  useMemo,
  useState,
  MouseEvent as ReactMouseEvent,
  WheelEvent as ReactWheelEvent,
  useRef,
} from "react";
import dagre from "@dagrejs/dagre";
import classNames from "classnames";
import { Link } from "react-router-dom";
import { max, sortBy } from "lodash";
import {
  IconArrowForward,
  IconArrowUpRight,
  IconClock,
} from "@tabler/icons-react";

import * as models from "../models";
import { buildUrl } from "../utils";
import StepLink from "./StepLink";
import { useHoverContext } from "./HoverContext";

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
  activeAttemptNumber: number | undefined,
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
        (id) => parentId in run.steps[id].executions,
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
  parentId?: string,
) {
  Object.keys(run.steps)
    .filter((id) => run.steps[id].parentId == parentId)
    .forEach((stepId) => {
      const step = run.steps[stepId];
      const attemptNumber =
        stepAttempts[stepId] ||
        max(Object.values(step.executions).map((e) => e.sequence));
      const executionId = Object.keys(step.executions).find(
        (id) => step.executions[id].sequence == attemptNumber,
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
  activeAttemptNumber: number | undefined,
) {
  const g = new dagre.graphlib.Graph<Node>();
  g.setGraph({ rankdir: "LR", ranksep: 40, nodesep: 40 });

  const stepAttempts = chooseStepAttempts(
    run,
    activeStepId,
    activeAttemptNumber,
  );

  if (run.parent) {
    const initialStepId = sortBy(
      Object.keys(run.steps).filter((id) => !run.steps[id].parentId),
      (stepId) => run.steps[stepId].createdAt,
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
            (id) => dependencyId in run.steps[id].executions,
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
    },
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
          (id) => parentId in run.steps[id].executions,
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
    },
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
    },
  );

  dagre.layout(g);
  return g;
}

function classNameForStep(
  step: models.Step,
  attempt: models.Execution | undefined,
) {
  const result = attempt?.result;
  if (step.cachedExecutionId || result?.type == "duplicated") {
    return "border-slate-200 bg-slate-50";
  } else if (!result && !attempt?.assignedAt) {
    return "border-blue-200 bg-blue-50";
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
  offset: [number, number];
  stepId: string;
  step: models.Step;
  attemptNumber: number | undefined;
  runId: string;
  isActive: boolean;
};

function StepNode({
  node,
  offset,
  stepId,
  step,
  attemptNumber,
  runId,
  isActive,
}: StepNodeProps) {
  const attempt = Object.values(step.executions).find(
    (e) => e.sequence == attemptNumber,
  );
  const { isHovered } = useHoverContext();
  return (
    <div
      className="absolute flex"
      style={{
        left: node.x - node.width / 2 + offset[0],
        top: node.y - node.height / 2 + offset[1],
        width: node.width,
        height: node.height,
      }}
    >
      {Object.keys(step.executions).length > 1 && (
        <div
          className={classNames(
            "absolute w-full h-full border border-slate-300 bg-white rounded ring-offset-2",
            isActive || isHovered(runId, stepId, attemptNumber)
              ? "-top-2 -right-2"
              : "-top-1 -right-1",
            isHovered(runId, stepId) &&
              !isHovered(runId, stepId, attemptNumber) &&
              "ring-2 ring-slate-300",
          )}
        ></div>
      )}
      <StepLink
        runId={runId}
        stepId={stepId}
        attemptNumber={attemptNumber}
        className={classNames(
          "absolute w-full h-full flex-1 flex gap-2 items-center border rounded px-2 py-1 ring-offset-2",
          classNameForStep(step, attempt),
        )}
        activeClassName="ring ring-cyan-400"
        hoveredClassName="ring ring-slate-300"
      >
        <span className="flex-1 flex flex-col truncate">
          <span
            className={classNames(
              "font-mono text-sm",
              !step.parentId && "font-bold",
            )}
          >
            {step.target}
          </span>
          {!step.parentId && (
            <span className="text-xs text-slate-500">{runId}</span>
          )}
        </span>
        {attempt && !attempt.result && !attempt.assignedAt && (
          <span>
            <IconClock size={20} strokeWidth={1.5} />
          </span>
        )}
      </StepLink>
    </div>
  );
}

type ParentNodeProps = {
  node: dagre.Node;
  offset: [number, number];
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
        left: node.x - node.width / 2 + offset[0],
        top: node.y - node.height / 2 + offset[1],
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
  offset: [number, number];
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
        left: node.x - node.width / 2 + offset[0],
        top: node.y - node.height / 2 + offset[1],
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
  offset: [number, number];
};

function Edge({ edge, offset }: EdgeProps) {
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
        d={`M ${points
          .map(({ x, y }) => `${x + offset[0]} ${y + offset[1]}`)
          .join(" ")}`}
      />
      <circle
        cx={points[points.length - 1].x + offset[0]}
        cy={points[points.length - 1].y + offset[1]}
        r={3}
        className={type == "dependency" ? "fill-slate-300" : "fill-slate-200"}
      />
    </Fragment>
  );
}

function calculateMargins(
  containerWidth: number,
  containerHeight: number,
  graphWidth: number,
  graphHeight: number,
) {
  const aspect =
    containerWidth && containerHeight ? containerWidth / containerHeight : 1;
  const marginX =
    Math.max(
      100,
      containerWidth - graphWidth,
      (graphHeight + 100) * aspect - graphWidth,
    ) / 2;
  const marginY =
    Math.max(
      100,
      containerHeight - graphHeight,
      (graphWidth + 100) / aspect - graphHeight,
    ) / 2;
  return [marginX, marginY];
}

type Props = {
  runId: string;
  run: models.Run;
  width: number;
  height: number;
  projectId: string;
  environmentName: string | undefined;
  activeStepId: string | undefined;
  activeAttemptNumber: number | undefined;
  minimumMargin?: number;
};

export default function RunGraph({
  runId,
  run,
  width: containerWidth,
  height: containerHeight,
  projectId,
  environmentName,
  activeStepId,
  activeAttemptNumber,
}: Props) {
  const containerRef = useRef<HTMLDivElement>(null);
  const [offsetOverride, setOffsetOverride] = useState<[number, number]>();
  const [dragging, setDragging] = useState<[number, number]>();
  const [zoomOverride, setZoomOverride] = useState<number>();
  const graph = useMemo(
    () => buildGraph(run, activeStepId, activeAttemptNumber),
    [run, activeStepId, activeAttemptNumber],
  );
  const graphWidth = graph.graph().width || 0;
  const graphHeight = graph.graph().height || 0;
  const [marginX, marginY] = calculateMargins(
    containerWidth,
    containerHeight,
    graphWidth,
    graphHeight,
  );
  const canvasWidth = Math.max(graphWidth + 2 * marginX, containerWidth);
  const canvasHeight = Math.max(graphHeight + 2 * marginY, containerHeight);
  const minZoom = Math.min(
    containerWidth / canvasWidth,
    containerHeight / canvasHeight,
  );
  const zoom = zoomOverride || Math.max(minZoom, 0.6);
  const maxDragX = -(canvasWidth * zoom - containerWidth);
  const maxDragY = -(canvasHeight * zoom - containerHeight);
  const [offsetX, offsetY] = offsetOverride || [maxDragX / 2, maxDragY / 2];
  const handleMouseDown = useCallback(
    (ev: ReactMouseEvent) => {
      const dragStart = [ev.screenX, ev.screenY];
      let dragging: [number, number] = [offsetX, offsetY];
      const handleMove = (ev: MouseEvent) => {
        dragging = [
          Math.min(0, Math.max(maxDragX, offsetX - dragStart[0] + ev.screenX)),
          Math.min(0, Math.max(maxDragY, offsetY - dragStart[1] + ev.screenY)),
        ];
        setDragging(dragging);
      };
      const handleUp = () => {
        setDragging(undefined);
        setOffsetOverride(dragging);
        window.removeEventListener("mousemove", handleMove);
        window.removeEventListener("mouseup", handleUp);
      };
      window.addEventListener("mousemove", handleMove);
      window.addEventListener("mouseup", handleUp);
    },
    [offsetX, offsetY, maxDragX, maxDragY],
  );
  const handleWheel = useCallback(
    (ev: ReactWheelEvent<HTMLDivElement>) => {
      const mouseX = ev.clientX - containerRef.current!.offsetLeft;
      const mouseY = ev.clientY - containerRef.current!.offsetTop;
      const canvasX = (mouseX - offsetX) / zoom;
      const canvasY = (mouseY - offsetY) / zoom;
      const newZoom = Math.max(
        minZoom,
        Math.min(1.5, zoom * (1 + ev.deltaY / -500)),
      );
      const delta = newZoom - zoom;
      setZoomOverride(newZoom);
      setOffsetOverride([
        Math.min(0, Math.max(maxDragX, offsetX - canvasX * delta)),
        Math.min(0, Math.max(maxDragY, offsetY - canvasY * delta)),
      ]);
    },
    [offsetX, offsetY, zoom, minZoom, maxDragX, maxDragY],
  );
  const [dx, dy] = dragging || [offsetX, offsetY];
  return (
    <div
      className="relative w-full h-full overflow-hidden"
      ref={containerRef}
      onWheel={handleWheel}
    >
      <div
        style={{
          transformOrigin: "0 0",
          transform: `translate(${dx}px, ${dy}px) scale(${zoom})`,
        }}
        className="relative will-change-transform"
      >
        <svg
          width={canvasWidth}
          height={canvasHeight}
          className={classNames(
            "absolute",
            dragging
              ? "cursor-grabbing"
              : zoom > minZoom
              ? "cursor-grab"
              : undefined,
          )}
          onMouseDown={handleMouseDown}
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
                offset={[marginX, marginY]}
                edge={graph.edge(edge)}
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
                    stepId={node.stepId}
                    step={node.step}
                    attemptNumber={node.attemptNumber}
                    runId={runId}
                    isActive={nodeId == activeStepId}
                    offset={[marginX, marginY]}
                  />
                );
              case "parent":
                return (
                  <ParentNode
                    key={nodeId}
                    node={node}
                    projectId={projectId}
                    parent={node.parent}
                    environmentName={environmentName}
                    offset={[marginX, marginY]}
                  />
                );
              case "child":
                return (
                  <ChildNode
                    key={nodeId}
                    node={node}
                    projectId={projectId}
                    runId={node.runId}
                    child={node.child}
                    environmentName={environmentName}
                    offset={[marginX, marginY]}
                  />
                );
            }
          })}
        </div>
      </div>
      <div className="absolute flex right-1 bottom-1 bg-white/90 rounded-xl px-2 py-1">
        <input
          type="range"
          value={zoom}
          min={Math.floor(minZoom * 100) / 100}
          max={1.5}
          step={0.01}
          className="w-24 accent-cyan-500 cursor-pointer"
          onChange={(ev) => setZoomOverride(parseFloat(ev.target.value))}
        />
      </div>
    </div>
  );
}
