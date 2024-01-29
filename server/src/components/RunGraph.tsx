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
import { max, sortBy } from "lodash";
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

type Node =
  | {
      type: "step";
      step: models.Step;
      stepId: string;
      attemptNumber: number;
    }
  | {
      type: "parent";
      parent: models.Reference;
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
  const stepAttempts: Record<string, number | undefined> = {};
  if (activeStepId) {
    stepAttempts[activeStepId] = activeAttemptNumber;
    const process = (stepId: string) => {
      Object.keys(run.steps).forEach((sId) => {
        if (!(sId in stepAttempts)) {
          Object.entries(run.steps[sId].attempts).forEach(([sequence, a]) => {
            if (a.children.includes(stepId)) {
              // TODO: keep as string?
              stepAttempts[sId] = parseInt(sequence, 10);
              process(sId);
            }
          });
        }
      });
    };
    process(activeStepId);
  }
  return stepAttempts;
}

function stepAttemptNumber(
  run: models.Run,
  stepAttempts: Record<string, number | undefined>,
  stepId: string,
) {
  const step = run.steps[stepId];
  return (
    stepAttempts[stepId] ||
    max(Object.keys(step.attempts).map((s) => parseInt(s, 10)))
  );
}

function traverseRun(
  run: models.Run,
  stepAttempts: Record<string, number | undefined>,
  stepId: string,
  callback: (stepId: string, attemptNumber: number) => void,
  seen: Record<string, true> = {},
) {
  const attemptNumber = stepAttemptNumber(run, stepAttempts, stepId);
  if (attemptNumber) {
    callback(stepId, attemptNumber);
    const attempt = run.steps[stepId].attempts[attemptNumber];
    attempt?.children.forEach((child) => {
      if (typeof child == "string" && !(child in seen)) {
        traverseRun(run, stepAttempts, child, callback, {
          ...seen,
          [child]: true,
        });
      }
    });
  }
}

function buildGraph(
  run: models.Run,
  runId: string,
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

  const initialStepId = sortBy(
    Object.keys(run.steps).filter((id) => run.steps[id].isInitial),
    (stepId) => run.steps[stepId].createdAt,
  )[0];

  g.setNode(run.parent?.runId || "start", {
    width: run.parent ? 100 : 30,
    height: 30,
    type: "parent",
    parent: run.parent || null,
  });
  g.setEdge(run.parent?.runId || "start", initialStepId, {
    type: "parent",
    weight: 1000,
  });

  const visibleSteps: Record<string, number> = {};
  traverseRun(
    run,
    stepAttempts,
    initialStepId,
    (stepId: string, attemptNumber: number) => {
      visibleSteps[stepId] = attemptNumber;
    },
  );

  traverseRun(
    run,
    stepAttempts,
    initialStepId,
    (stepId: string, attemptNumber: number) => {
      const step = run.steps[stepId];
      g.setNode(stepId, {
        width: 160,
        height: 50,
        type: "step",
        step,
        stepId,
        attemptNumber,
      });
      const attempt = step.attempts[attemptNumber];
      if (!attempt) {
        return;
      }
      Object.entries(attempt.dependencies).forEach(
        ([dependencyId, dependency]) => {
          if (dependency.runId == runId) {
            if (
              !attempt.children.some(
                (c) =>
                  typeof c == "string" &&
                  Object.values(run.steps[c].attempts).some(
                    (a) => a.isCached && a.executionId == dependencyId,
                  ),
              )
            ) {
              g.setEdge(dependency.stepId, stepId, { type: "dependency" });
            }
          } else {
            // TODO: connect to node for (child/parent) run? (if it exists?)
          }
        },
      );
      attempt.children.forEach((child) => {
        if (typeof child == "string") {
          const childAttemptNumber = stepAttemptNumber(
            run,
            stepAttempts,
            child,
          );
          const childAttempt =
            childAttemptNumber && run.steps[child].attempts[childAttemptNumber];
          if (childAttempt) {
            if (childAttempt.isCached) {
              const cachedExecutionId = childAttempt.executionId;
              const cachedStepId = Object.keys(run.steps).find(
                (sId) =>
                  sId in visibleSteps &&
                  Object.values(run.steps[sId].attempts).some(
                    (a) => !a.isCached && a.executionId == cachedExecutionId,
                  ),
              );
              if (cachedExecutionId in attempt.dependencies) {
                g.setEdge(child, stepId, { type: "dependency" });
                if (cachedStepId) {
                  g.setEdge(cachedStepId, child, { type: "transitive" });
                }
              } else {
                g.setEdge(stepId, child, { type: "child" });
                if (cachedStepId) {
                  g.setEdge(child, cachedStepId, { type: "transitive" });
                }
              }
            } else if (
              !Object.values(attempt.dependencies).some(
                (d) => d.stepId == child,
              )
            ) {
              g.setEdge(stepId, child, { type: "child" });
            }
          } else {
            // TODO
          }
        } else {
          g.setNode(child.runId, {
            width: 160,
            height: 50,
            type: "child",
            child,
            runId: child.runId,
          });
          if (
            Object.values(attempt.dependencies).some(
              (d) => d.runId == child.runId,
            )
          ) {
            g.setEdge(child.runId, stepId, { type: "dependency" });
          } else {
            g.setEdge(stepId, child.runId, { type: "child" });
          }
        }
      });
    },
  );

  dagre.layout(g);
  return g;
}

function classNameForAttempt(attempt: models.Attempt) {
  const result = attempt.result;
  if (attempt.isCached || result?.type == "deferred") {
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
  stepId: string;
  step: models.Step;
  attemptNumber: number;
  runId: string;
  isActive: boolean;
};

function StepNode({
  stepId,
  step,
  attemptNumber,
  runId,
  isActive,
}: StepNodeProps) {
  const attempt = step.attempts[attemptNumber];
  const { isHovered } = useHoverContext();
  const isDeferred = attempt?.isCached || attempt?.result?.type == "deferred";
  return (
    <Fragment>
      {Object.keys(step.attempts).length > 1 && (
        <div
          className={classNames(
            "absolute w-full h-full border border-slate-300 bg-white rounded ring-offset-2",
            isActive || isHovered(runId, stepId, attemptNumber)
              ? "-top-2 -right-2"
              : "-top-1 -right-1",
            isHovered(runId, stepId) &&
              !isHovered(runId, stepId, attemptNumber) &&
              "ring-2 ring-slate-400",
          )}
        ></div>
      )}
      <StepLink
        runId={runId}
        stepId={stepId}
        attemptNumber={attemptNumber}
        className={classNames(
          "absolute w-full h-full flex-1 flex gap-2 items-center border rounded px-2 py-1 ring-offset-2",
          attempt && classNameForAttempt(attempt),
        )}
        activeClassName="ring ring-cyan-400"
        hoveredClassName="ring ring-slate-400"
      >
        <span className="flex-1 flex items-center overflow-hidden">
          <span className="flex-1 truncate text-sm">
            <span
              className={classNames(
                "font-mono",
                step.isInitial && "font-bold",
                isDeferred && "text-slate-500",
              )}
            >
              {step.target}
            </span>{" "}
            <span
              className={classNames(
                "text-xs",
                isDeferred ? "text-slate-400" : "text-slate-500",
              )}
            >
              ({step.repository})
            </span>
          </span>
          {step.isMemoised && (
            <span className="text-slate-500" title="Memoised">
              <IconPinned size={12} />
            </span>
          )}
        </span>
        {attempt &&
          !attempt.isCached &&
          !attempt.result &&
          !attempt.assignedAt && (
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
        attemptNumber={parent.sequence}
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
      attemptNumber={1}
      className="flex-1 flex w-full h-full gap-2 items-center border border-slate-300 rounded px-2 py-1 bg-white ring-offset-2"
      hoveredClassName="ring ring-slate-400"
    >
      <div className="flex-1 flex flex-col overflow-hidden">
        <span className="truncate text-slate-700 text-sm">
          <span className="font-mono">{child.target}</span>{" "}
          <span className="text-slate-500 text-xs">({child.repository})</span>
        </span>
      </div>
      <IconArrowUpRight size={20} className="text-slate-400" />
    </StepLink>
  );
}

function buildPath(points: { x: number; y: number }[]): string {
  const parts = [`M ${points[0].x} ${points[0].y}`];

  if (points.length === 2) {
    parts.push(`L ${points[1].x} ${points[1].y}`);
  } else if (points.length === 3) {
    parts.push(`Q ${points[1].x} ${points[1].y} ${points[2].x} ${points[2].y}`);
  } else {
    for (let i = 1; i < points.length - 2; i++) {
      const p0 = points[i - 1];
      const p1 = points[i];
      const p2 = points[i + 1];
      const p3 = points[i + 2];

      const x1 = p1.x + (p2.x - p0.x) / 6;
      const y1 = p1.y + (p2.y - p0.y) / 6;

      const x2 = p2.x - (p3.x - p1.x) / 6;
      const y2 = p2.y - (p3.y - p1.y) / 6;

      parts.push(`C ${x1} ${y1} ${x2} ${y2} ${p2.x} ${p2.y}`);
    }

    const q0 = points[points.length - 2];
    const q1 = points[points.length - 1];
    parts.push(`S ${q0.x} ${q0.y} ${q1.x} ${q1.y}`);
  }

  return parts.join(" ");
}
type EdgeProps = {
  edge: dagre.GraphEdge;
  offset: [number, number];
  highlight?: boolean;
};

function Edge({ edge, offset, highlight }: EdgeProps) {
  const { points, type } = edge;
  return (
    <path
      className={
        highlight
          ? "stroke-slate-400"
          : type == "transitive"
          ? "stroke-slate-100"
          : "stroke-slate-200"
      }
      fill="none"
      strokeWidth={highlight ? 3 : 3}
      strokeDasharray={type != "dependency" ? "5" : undefined}
      d={buildPath(
        points.map(({ x, y }) => ({ x: x + offset[0], y: y + offset[1] })),
      )}
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
  runId: string;
  run: models.Run;
  width: number;
  height: number;
  activeStepId: string | undefined;
  activeAttemptNumber: number | undefined;
  minimumMargin?: number;
};

export default function RunGraph({
  runId,
  run,
  width: containerWidth,
  height: containerHeight,
  activeStepId,
  activeAttemptNumber,
}: Props) {
  const containerRef = useRef<HTMLDivElement>(null);
  const [offsetOverride, setOffsetOverride] = useState<[number, number]>();
  const [dragging, setDragging] = useState<[number, number]>();
  const [zoomOverride, setZoomOverride] = useState<number>();
  const { isHovered } = useHoverContext();
  const graph = useMemo(
    () => buildGraph(run, runId, activeStepId, activeAttemptNumber),
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
            const highlight =
              isHovered(edge.v) ||
              isHovered(edge.w) ||
              isHovered(runId, edge.v) ||
              isHovered(runId, edge.w);
            return (
              <Edge
                key={`${edge.v}-${edge.w}`}
                offset={[marginX, marginY]}
                edge={graph.edge(edge)}
                highlight={highlight}
              />
            );
          })}
        </svg>
        <div className="absolute">
          {graph.nodes().map((nodeId) => {
            const node = graph.node(nodeId);
            return (
              <div
                key={nodeId}
                className="absolute flex"
                style={{
                  left: node.x - node.width / 2 + marginX,
                  top: node.y - node.height / 2 + marginY,
                  width: node.width,
                  height: node.height,
                }}
              >
                {node.type == "step" ? (
                  <StepNode
                    stepId={node.stepId}
                    step={node.step}
                    attemptNumber={node.attemptNumber}
                    runId={runId}
                    isActive={nodeId == activeStepId}
                  />
                ) : node.type == "parent" ? (
                  <ParentNode parent={node.parent} />
                ) : node.type == "child" ? (
                  <ChildNode runId={node.runId} child={node.child} />
                ) : undefined}
              </div>
            );
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
