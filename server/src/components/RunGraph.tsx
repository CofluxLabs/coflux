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
  IconClock,
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
) {
  const attemptNumber = stepAttemptNumber(run, stepAttempts, stepId);
  if (attemptNumber) {
    callback(stepId, attemptNumber);
    const execution = run.steps[stepId].attempts[attemptNumber];
    execution.children.forEach((child) => {
      if (typeof child == "string") {
        traverseRun(run, stepAttempts, child, callback);
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
    Object.keys(run.steps).filter((id) => run.steps[id].type == 0),
    (stepId) => run.steps[stepId].createdAt,
  )[0];

  if (run.parent) {
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
    initialStepId,
    (stepId: string, attemptNumber: number) => {
      const step = run.steps[stepId];
      const attempt = step.attempts[attemptNumber];
      g.setNode(stepId, {
        width: 160,
        height: 50,
        type: "step",
        step,
        stepId,
        attemptNumber,
      });
      Object.entries(attempt.dependencies).forEach(
        ([dependencyId, dependency]) => {
          if (dependency.runId == runId) {
            if (
              !attempt.children.some(
                (c) =>
                  typeof c == "string" &&
                  Object.values(run.steps[c].attempts).some(
                    (a) => a.type == 1 && a.executionId == dependencyId,
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
          if (childAttemptNumber) {
            const childAttempt = run.steps[child].attempts[childAttemptNumber];
            if (childAttempt.type == 1) {
              const cachedExecutionId = childAttempt.executionId;
              const cachedStepId = Object.keys(run.steps).find((sId) =>
                Object.values(run.steps[sId].attempts).some(
                  (a) => a.type == 0 && a.executionId == cachedExecutionId,
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
          if (child.executionId && child.executionId in attempt.dependencies) {
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
  if (attempt.type == 1 || result?.type == "duplicated") {
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
          classNameForAttempt(attempt),
        )}
        activeClassName="ring ring-cyan-400"
        hoveredClassName="ring ring-slate-400"
      >
        <span className="flex-1 flex flex-col truncate">
          <span
            className={classNames(
              "font-mono text-sm",
              step.type == 0 && "font-bold",
            )}
          >
            {step.target}
          </span>
          {step.type == 0 && (
            <span className="text-xs text-slate-500">{runId}</span>
          )}
        </span>
        {attempt &&
          attempt.type == 0 &&
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
  parent: models.Reference;
};

function ParentNode({ parent }: ParentNodeProps) {
  return (
    <StepLink
      runId={parent.runId}
      stepId={parent.stepId}
      attemptNumber={parent.sequence}
      className="flex-1 flex gap-2 items-center border border-dashed border-slate-300 rounded px-2 py-1 bg-white ring-offset-2"
      hoveredClassName="ring ring-slate-400"
    >
      <div className="flex-1 flex flex-col truncate">
        <span className="font-mono font-bold text-slate-400 text-sm">
          {parent.target}
        </span>
        <span className="text-xs text-slate-400">{parent.runId}</span>
      </div>
      <IconArrowForward size={20} className="text-slate-400" />
    </StepLink>
  );
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
      className="flex-1 flex gap-2 items-center border border-slate-300 rounded px-2 py-1 bg-white ring-offset-2"
      hoveredClassName="ring ring-slate-400"
    >
      <div className="flex-1 flex flex-col truncate">
        <span className="font-mono font-bold text-slate-500 text-sm">
          {child.target}
        </span>
        <span className="text-xs text-slate-400">{runId}</span>
      </div>
      <IconArrowUpRight size={20} className="text-slate-400" />
    </StepLink>
  );
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
      strokeDasharray={type == "child" ? "5" : undefined}
      d={`M ${points
        .map(({ x, y }) => `${x + offset[0]} ${y + offset[1]}`)
        .join(" ")}`}
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
                    key={nodeId}
                    stepId={node.stepId}
                    step={node.step}
                    attemptNumber={node.attemptNumber}
                    runId={runId}
                    isActive={nodeId == activeStepId}
                  />
                ) : node.type == "parent" ? (
                  <ParentNode key={nodeId} parent={node.parent} />
                ) : node.type == "child" ? (
                  <ChildNode
                    key={nodeId}
                    runId={node.runId}
                    child={node.child}
                  />
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
