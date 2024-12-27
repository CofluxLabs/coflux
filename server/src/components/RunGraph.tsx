import {
  Fragment,
  useCallback,
  useState,
  PointerEvent as ReactPointerEvent,
  WheelEvent as ReactWheelEvent,
  useRef,
  useEffect,
} from "react";
import classNames from "classnames";
import {
  IconArrowUpRight,
  IconBolt,
  IconClock,
  IconArrowDownRight,
  IconZzz,
  IconArrowBounce,
  IconPin,
  IconAlertCircle,
  IconStackPop,
} from "@tabler/icons-react";

import * as models from "../models";
import StepLink from "./StepLink";
import { useHoverContext } from "./HoverContext";
import buildGraph, { Graph, Edge } from "../graph";
import EnvironmentLabel from "./EnvironmentLabel";
import AssetIcon from "./AssetIcon";
import { truncatePath } from "../utils";
import AssetLink from "./AssetLink";
import { isEqual, maxBy } from "lodash";

function classNameForExecution(execution: models.Execution) {
  const result =
    execution.result?.type == "deferred" ||
    execution.result?.type == "cached" ||
    execution.result?.type == "spawned"
      ? execution.result.result
      : execution.result;
  if (
    execution.result?.type == "cached" ||
    execution.result?.type == "deferred"
  ) {
    return "border-slate-200 bg-slate-50";
  } else if (!result && !execution?.assignedAt) {
    // TODO: handle spawned/etc case
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

function resolveExecutionResult(
  run: models.Run,
  stepId: string,
  attempt: number,
): models.Value | undefined {
  const result = run.steps[stepId].executions[attempt].result;
  switch (result?.type) {
    case "value":
      return result.value;
    case "error":
    case "abandoned":
      return result.retry
        ? resolveExecutionResult(run, stepId, result.retry)
        : undefined;
    case "suspended":
      return resolveExecutionResult(run, stepId, result.successor);
    case "deferred":
    case "cached":
    case "spawned":
      return result.result?.type == "value" ? result.result.value : undefined;
    default:
      return undefined;
  }
}

function isStepStale(
  stepId: string,
  attempt: number,
  run: models.Run,
  activeStepId: string | undefined,
  activeAttempt: number | undefined,
): boolean {
  const execution = run.steps[stepId]?.executions[attempt];
  if (execution) {
    return Object.values(execution.children).some((child) => {
      const childStep = run.steps[child.stepId];
      const initialResult = resolveExecutionResult(
        run,
        child.stepId,
        child.attempt,
      );
      const latestAttempt =
        (child.stepId == activeStepId && activeAttempt) ||
        Math.max(
          ...Object.keys(childStep.executions).map((a) => parseInt(a, 10)),
        );
      const latestResult = resolveExecutionResult(
        run,
        child.stepId,
        latestAttempt,
      );
      return (
        (initialResult &&
          latestResult &&
          !isEqual(initialResult, latestResult)) ||
        isStepStale(
          child.stepId,
          latestAttempt,
          run,
          activeStepId,
          activeAttempt,
        )
      );
    });
  } else {
    return false;
  }
}

type StepNodeProps = {
  projectId: string;
  stepId: string;
  step: models.Step;
  attempt: number;
  runId: string;
  isActive: boolean;
  isStale: boolean;
  runEnvironmentId: string;
};

function StepNode({
  projectId,
  stepId,
  step,
  attempt,
  runId,
  isActive,
  isStale,
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
            isActive || isHovered({ stepId, attempt })
              ? "-top-2 -right-2"
              : "-top-1 -right-1",
            isHovered({ stepId }) &&
              !isHovered({ stepId, attempt }) &&
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
          isStale && "border-opacity-40",
        )}
        activeClassName="ring ring-cyan-400"
        hoveredClassName="ring ring-slate-400"
      >
        <span
          className={classNames(
            "flex-1 flex items-center overflow-hidden",
            isStale && "opacity-30",
          )}
        >
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
        {isStale ? (
          <span title="Stale">
            <IconAlertCircle size={16} className="text-slate-500" />
          </span>
        ) : execution && !execution.result && !execution.assignedAt ? (
          <span title="Assigning...">
            <IconClock size={16} />
          </span>
        ) : execution?.result?.type == "cached" ? (
          <span title="Cache read">
            <IconStackPop size={16} className="text-slate-400" />
          </span>
        ) : execution?.result?.type == "suspended" ? (
          <span title="Suspended">
            <IconZzz size={16} className="text-slate-500" />
          </span>
        ) : execution?.result?.type == "deferred" ? (
          <span title="Deferred">
            <IconArrowBounce size={16} className="text-slate-400" />
          </span>
        ) : step.isMemoised ? (
          <span title="Memoised">
            <IconPin size={16} className="text-slate-500" />
          </span>
        ) : null}
      </StepLink>
    </Fragment>
  );
}

type AssetNodeProps = {
  projectId: string;
  assetId: string;
  asset: models.Asset;
};

function AssetNode({ projectId, assetId, asset }: AssetNodeProps) {
  return (
    <AssetLink
      projectId={projectId}
      assetId={assetId}
      asset={asset}
      className="h-full w-full flex gap-0.5 px-1.5 items-center bg-white rounded-full text-slate-700 text-sm ring-slate-400"
      hoveredClassName="ring-2"
    >
      <AssetIcon
        asset={asset}
        size={16}
        strokeWidth={1.5}
        className="shrink-0"
      />
      <span className="text-ellipsis overflow-hidden whitespace-nowrap">
        {truncatePath(asset.path) + (asset.type == 1 ? "/" : "")}
      </span>
    </AssetLink>
  );
}

type MoreAssetsNodeProps = {
  assetIds: string[];
};

function MoreAssetsNode({ assetIds }: MoreAssetsNodeProps) {
  const { isHovered } = useHoverContext();

  return (
    <span
      className={classNames(
        "h-full w-full px-1.5 items-center bg-white rounded-full text-slate-400 text-sm ring-slate-400 text-ellipsis overflow-hidden whitespace-nowrap",
        assetIds.some((assetId) => isHovered({ assetId })) && "ring-2",
      )}
    >
      (+{assetIds.length} more)
    </span>
  );
}

type ParentNodeProps = {
  parent: models.ExecutionReference | null;
};

function ParentNode({ parent }: ParentNodeProps) {
  if (parent) {
    return (
      <StepLink
        runId={parent.runId}
        stepId={parent.stepId}
        attempt={parent.attempt}
        className="flex-1 w-full h-full flex items-center px-2 py-1 border border-slate-300 rounded-full bg-white ring-offset-2"
        hoveredClassName="ring ring-slate-400"
      >
        <span className="text-slate-500 font-bold flex-1">{parent.runId}</span>
        <IconArrowDownRight size={20} className="text-slate-400" />
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
  child: models.ExecutionReference;
};

function ChildNode({ child }: ChildNodeProps) {
  return (
    <StepLink
      runId={child.runId}
      stepId={child.stepId}
      attempt={child.attempt}
      className="flex-1 w-full h-full flex items-center px-2 py-1 border border-slate-300 rounded-full bg-white ring-offset-2"
      hoveredClassName="ring ring-slate-400"
    >
      <IconArrowUpRight size={20} className="text-slate-400" />
      <span className="text-slate-500 font-bold flex-1 text-end">
        {child.runId}
      </span>
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
      strokeWidth={
        edge.type == "asset"
          ? 1.5
          : highlight || edge.type == "dependency"
            ? 3
            : 2
      }
      strokeDasharray={
        edge.type == "asset" ? "2" : edge.type != "dependency" ? "5" : undefined
      }
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
  const handlePointerDown = useCallback(
    (ev: ReactPointerEvent) => {
      const dragStart = [ev.screenX, ev.screenY];
      let dragging: [number, number] = [offsetX, offsetY];
      const handleMove = (ev: PointerEvent) => {
        dragging = [
          Math.min(0, Math.max(maxDragX, offsetX - dragStart[0] + ev.screenX)),
          Math.min(0, Math.max(maxDragY, offsetY - dragStart[1] + ev.screenY)),
        ];
        setDragging(dragging);
      };
      const handleUp = () => {
        setDragging(undefined);
        setOffsetOverride(dragging);
        window.removeEventListener("pointermove", handleMove);
        window.removeEventListener("pointerup", handleUp);
      };
      window.addEventListener("pointermove", handleMove);
      window.addEventListener("pointerup", handleUp);
    },
    [offsetX, offsetY, maxDragX, maxDragY],
  );
  const handleWheel = useCallback(
    (ev: ReactWheelEvent<HTMLDivElement>) => {
      const pointerX = ev.clientX - containerRef.current!.offsetLeft;
      const pointerY = ev.clientY - containerRef.current!.offsetTop;
      const canvasX = (pointerX - offsetX) / zoom;
      const canvasY = (pointerY - offsetY) / zoom;
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
          onPointerDown={handlePointerDown}
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
              const from = graph.nodes[edge.from];
              const to = graph.nodes[edge.to];
              const highlight =
                (from.type == "parent" &&
                  from.parent &&
                  isHovered({ runId: from.parent.runId })) ||
                (from.type == "child" && isHovered({ runId: from.runId })) ||
                (to.type == "child" && isHovered({ runId: to.runId })) ||
                (from.type == "step" && isHovered({ stepId: from.stepId })) ||
                (to.type == "step" && isHovered({ stepId: to.stepId })) ||
                (to.type == "asset" && isHovered({ assetId: to.assetId })) ||
                (to.type == "assets" &&
                  to.assetIds.some((assetId) => isHovered({ assetId })));
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
                      isStale={isStepStale(
                        node.stepId,
                        node.attempt,
                        run,
                        activeStepId,
                        activeAttempt,
                      )}
                      runEnvironmentId={runEnvironmentId}
                    />
                  ) : node.type == "asset" ? (
                    <AssetNode
                      projectId={projectId}
                      assetId={node.assetId}
                      asset={node.asset}
                    />
                  ) : node.type == "assets" ? (
                    <MoreAssetsNode assetIds={node.assetIds} />
                  ) : node.type == "child" ? (
                    <ChildNode child={node.child} />
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
