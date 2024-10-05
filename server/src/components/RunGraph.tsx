import {
  Fragment,
  useCallback,
  useState,
  MouseEvent as ReactMouseEvent,
  WheelEvent as ReactWheelEvent,
  useRef,
  useEffect,
} from "react";
import classNames from "classnames";
import {
  IconArrowForward,
  IconArrowUpRight,
  IconBolt,
  IconClock,
  IconPinned,
} from "@tabler/icons-react";

import * as models from "../models";
import StepLink from "./StepLink";
import { useHoverContext } from "./HoverContext";
import buildGraph, { Graph, Edge } from "../graph";
import EnvironmentLabel from "./EnvironmentLabel";

function classNameForExecution(execution: models.Execution) {
  const result = execution.result;
  if (result?.type == "cached" || result?.type == "deferred") {
    return "border-slate-200 bg-slate-50";
  } else if (!result && !execution?.assignedAt) {
    return "border-blue-200 bg-blue-50";
  } else if (!result) {
    return "border-blue-400 bg-blue-100";
  } else if (result.type == "error") {
    return "border-red-400 bg-red-100";
  } else if (result.type == "abandoned" || result.type == "cancelled") {
    return "border-yellow-400 bg-yellow-100";
  } else if (result.type == "suspended") {
    return "border-slate-200 bg-slate-50";
  } else {
    return "border-slate-400 bg-slate-100";
  }
}

type StepNodeProps = {
  projectId: string;
  stepId: string;
  step: models.Step;
  attempt: number;
  runId: string;
  isActive: boolean;
  runEnvironmentId: string;
};

function StepNode({
  projectId,
  stepId,
  step,
  attempt,
  runId,
  isActive,
  runEnvironmentId,
}: StepNodeProps) {
  const execution = step.executions[attempt];
  const { isHovered } = useHoverContext();
  const isDeferred =
    execution?.result?.type == "cached" ||
    execution?.result?.type == "deferred";
  return (
    <Fragment>
      {Object.keys(step.executions).length > 1 && (
        <div
          className={classNames(
            "absolute w-full h-full border border-slate-300 bg-white rounded ring-offset-2",
            isActive || isHovered(runId, stepId, attempt)
              ? "-top-2 -right-2"
              : "-top-1 -right-1",
            isHovered(runId, stepId) &&
              !isHovered(runId, stepId, attempt) &&
              "ring-2 ring-slate-400",
          )}
        ></div>
      )}
      <StepLink
        runId={runId}
        stepId={stepId}
        attempt={attempt}
        className={classNames(
          "absolute w-full h-full flex-1 flex gap-2 items-center border rounded px-2 py-1 ring-offset-2",
          execution && classNameForExecution(execution),
        )}
        activeClassName="ring ring-cyan-400"
        hoveredClassName="ring ring-slate-400"
      >
        <span className="flex-1 flex items-center overflow-hidden">
          <span className="flex-1 flex flex-col gap-0.5 overflow-hidden">
            <span
              className={classNames(
                "truncate text-xs",
                isDeferred ? "text-slate-300" : "text-slate-400",
              )}
            >
              {step.repository} /
            </span>
            <span className="flex gap-1 items-center">
              <span
                className={classNames(
                  "flex-1 truncate text-sm font-mono",
                  !step.parentId && "font-bold",
                  isDeferred && "text-slate-500",
                )}
              >
                {step.target}
              </span>
              {step.isMemoised && (
                <span
                  className="text-slate-500"
                  title="This execution has been memoised"
                >
                  <IconPinned size={12} />
                </span>
              )}
              {execution && execution.environmentId != runEnvironmentId && (
                <EnvironmentLabel
                  projectId={projectId}
                  environmentId={execution.environmentId}
                  size="sm"
                  warning="This execution ran in a different environment"
                  compact
                />
              )}
            </span>
          </span>
        </span>
        {execution && !execution.result && !execution.assignedAt && (
          <span>
            <IconClock size={20} strokeWidth={1.5} />
          </span>
        )}
      </StepLink>
    </Fragment>
  );
}

type ParentNodeProps = {
  parent: models.Reference | null;
};

function ParentNode({ parent }: ParentNodeProps) {
  if (parent) {
    return (
      <StepLink
        runId={parent.runId}
        stepId={parent.stepId}
        attempt={parent.attempt}
        className="flex-1 w-full h-full flex gap-2 items-center px-2 py-1 border border-slate-300 rounded-full bg-white ring-offset-2"
        hoveredClassName="ring ring-slate-400"
      >
        <div className="flex-1 flex flex-col overflow-hidden text-center">
          <span className="text-slate-500 font-bold">{parent.runId}</span>
        </div>
        <IconArrowForward size={20} className="text-slate-400" />
      </StepLink>
    );
  } else {
    return (
      <div
        className="flex-1 w-full h-full flex items-center justify-center border border-slate-300 rounded-full bg-white"
        title="Manual initialisation"
      >
        <IconBolt className="text-slate-500" size={20} />
      </div>
    );
  }
}

type ChildNodeProps = {
  runId: string;
  child: models.Child;
};

function ChildNode({ runId, child }: ChildNodeProps) {
  return (
    <StepLink
      runId={runId}
      stepId={child.stepId}
      attempt={1}
      className="flex-1 flex w-full h-full gap-2 items-center border border-slate-300 rounded px-2 py-1 bg-white ring-offset-2"
      hoveredClassName="ring ring-slate-400"
    >
      <div className="flex-1 flex flex-col overflow-hidden">
        <span className="text-slate-400 truncate text-xs">
          {child.repository} /
        </span>
        <span className="truncate text-slate-700 text-sm font-mono">
          {child.target}
        </span>
      </div>
      <IconArrowUpRight size={20} className="text-slate-400" />
    </StepLink>
  );
}

function buildEdgePath(edge: Edge, offset: [number, number]): string {
  const formatPoint = ({ x, y }: { x: number; y: number }) =>
    `${x + offset[0]},${y + offset[1]}`;

  return [
    `M ${formatPoint(edge.path[0])}`,
    ...edge.path.slice(1).map((p) => `L ${formatPoint(p)}`),
  ].join(" ");
}

type EdgePathProps = {
  edge: Edge;
  offset: [number, number];
  highlight?: boolean;
};

function EdgePath({ edge, offset, highlight }: EdgePathProps) {
  return (
    <path
      className={
        highlight
          ? "stroke-slate-400"
          : edge.type == "transitive"
            ? "stroke-slate-100"
            : "stroke-slate-200"
      }
      fill="none"
      strokeWidth={highlight || edge.type == "dependency" ? 3 : 2}
      strokeDasharray={edge.type != "dependency" ? "5" : undefined}
      d={buildEdgePath(edge, offset)}
    />
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
  projectId: string;
  runId: string;
  run: models.Run;
  width: number;
  height: number;
  activeStepId: string | undefined;
  activeAttempt: number | undefined;
  runEnvironmentId: string;
};

export default function RunGraph({
  projectId,
  runId,
  run,
  width: containerWidth,
  height: containerHeight,
  activeStepId,
  activeAttempt,
  runEnvironmentId,
}: Props) {
  const containerRef = useRef<HTMLDivElement>(null);
  const [offsetOverride, setOffsetOverride] = useState<[number, number]>();
  const [dragging, setDragging] = useState<[number, number]>();
  const [zoomOverride, setZoomOverride] = useState<number>();
  const { isHovered } = useHoverContext();
  const [graph, setGraph] = useState<Graph>();
  useEffect(() => {
    buildGraph(run, runId, activeStepId, activeAttempt)
      .then(setGraph)
      .catch(() => setGraph(undefined));
  }, [run, runId, activeStepId, activeAttempt]);
  const graphWidth = graph?.width || 0;
  const graphHeight = graph?.height || 0;
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
          {graph &&
            Object.entries(graph.edges).flatMap(([edgeId, edge]) => {
              const highlight =
                isHovered(edge.from) ||
                isHovered(edge.to) ||
                isHovered(runId, edge.from) ||
                isHovered(runId, edge.to);
              return (
                <EdgePath
                  key={edgeId}
                  offset={[marginX, marginY]}
                  edge={edge}
                  highlight={highlight}
                />
              );
            })}
        </svg>
        <div className="absolute">
          {graph &&
            Object.entries(graph.nodes).map(([nodeId, node]) => {
              return (
                <div
                  key={nodeId}
                  className="absolute flex"
                  style={{
                    left: node.x + marginX,
                    top: node.y + marginY,
                    width: node.width,
                    height: node.height,
                  }}
                >
                  {node.type == "parent" ? (
                    <ParentNode parent={node.parent} />
                  ) : node.type == "step" ? (
                    <StepNode
                      projectId={projectId}
                      stepId={node.stepId}
                      step={node.step}
                      attempt={node.attempt}
                      runId={runId}
                      isActive={node.stepId == activeStepId}
                      runEnvironmentId={runEnvironmentId}
                    />
                  ) : node.type == "child" ? (
                    <ChildNode runId={node.runId} child={node.child} />
                  ) : undefined}
                </div>
              );
            })}
        </div>
      </div>
      <div className="absolute flex right-1 bottom-1 bg-white/90 rounded-xl px-2 py-1 mb-1">
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
