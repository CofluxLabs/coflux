import ELK from "elkjs/lib/elk.bundled.js";
import { max, minBy } from "lodash";

import * as models from "./models";
import { truncatePath } from "./utils";

type BaseNode = (
  | {
      type: "step";
      step: models.Step;
      stepId: string;
      attempt: number;
    }
  | {
      type: "parent";
      parent: models.ExecutionReference | null;
    }
  | {
      type: "child";
      child: models.ExecutionReference;
      runId: string;
    }
  | {
      type: "asset";
      stepId: string;
      assetId: string;
      asset: models.Asset;
    }
  | {
      type: "assets";
      stepId: string;
      assetIds: string[];
    }
) & {
  width: number;
  height: number;
};

export type Node = BaseNode & {
  x: number;
  y: number;
};

export type Edge = {
  from: string;
  to: string;
  path: { x: number; y: number }[];
  type: "dependency" | "child" | "transitive" | "parent" | "asset";
};

export type Graph = {
  width: number;
  height: number;
  nodes: Record<string, Node>;
  edges: Record<string, Edge>;
};

function chooseStepAttempts(
  run: models.Run,
  activeStepId: string | undefined,
  activeAttempt: number | undefined,
) {
  const stepAttempts: Record<string, number | undefined> = {};
  if (activeStepId) {
    stepAttempts[activeStepId] = activeAttempt;
    const process = (stepId: string) => {
      Object.keys(run.steps).forEach((sId) => {
        if (!(sId in stepAttempts)) {
          Object.entries(run.steps[sId].executions).forEach(
            ([attempt, execution]) => {
              if (execution.children.includes(stepId)) {
                // TODO: keep as string?
                stepAttempts[sId] = parseInt(attempt, 10);
                process(sId);
              }
            },
          );
        }
      });
    };
    process(activeStepId);
  }
  return stepAttempts;
}

function getStepAttempt(
  run: models.Run,
  stepAttempts: Record<string, number | undefined>,
  stepId: string,
) {
  const step = run.steps[stepId];
  return (
    stepAttempts[stepId] ||
    max(Object.keys(step.executions).map((a) => parseInt(a, 10)))
  );
}

function traverseRun(
  run: models.Run,
  stepAttempts: Record<string, number | undefined>,
  stepId: string,
  callback: (stepId: string, attempt: number) => void,
  seen: Record<string, true> = {},
) {
  const attempt = getStepAttempt(run, stepAttempts, stepId);
  if (attempt) {
    callback(stepId, attempt);
    const execution = run.steps[stepId].executions[attempt];
    execution?.children.forEach((child) => {
      if (!(child in seen)) {
        traverseRun(run, stepAttempts, child, callback, {
          ...seen,
          [child]: true,
        });
      }
    });
  }
}

let canvas: HTMLCanvasElement | undefined;

function getTextWidth(text: string, font = "14px system-ui") {
  canvas = canvas || document.createElement("canvas");
  const context = canvas.getContext("2d")!;
  context.font = font;
  return context.measureText(text).width;
}

function truncateList<T>(array: T[], limit: number): [T[], T[]] {
  if (array.length <= limit) {
    return [array, []];
  } else {
    const adjustedLimit = Math.max(0, limit - 1);
    return [array.slice(0, adjustedLimit), array.slice(adjustedLimit)];
  }
}

export default function buildGraph(
  run: models.Run,
  runId: string,
  activeStepId: string | undefined,
  activeAttempt: number | undefined,
): Promise<Graph> {
  const stepAttempts = chooseStepAttempts(run, activeStepId, activeAttempt);

  const initialStepId = minBy(
    Object.keys(run.steps).filter((id) => !run.steps[id].parentId),
    (stepId) => run.steps[stepId].createdAt,
  )!;

  const visibleSteps: Record<string, number> = {};
  traverseRun(
    run,
    stepAttempts,
    initialStepId,
    (stepId: string, attempt: number) => {
      visibleSteps[stepId] = attempt;
    },
  );

  const nodes: Record<string, BaseNode> = {};
  const edges: Record<string, Omit<Edge, "path">> = {};

  nodes[run.parent?.runId || "start"] = {
    type: "parent",
    parent: run.parent || null,
    width: run.parent ? 100 : 30,
    height: 30,
  };
  edges["start"] = {
    from: run.parent?.runId || "start",
    to: initialStepId,
    type: "parent",
  };

  traverseRun(
    run,
    stepAttempts,
    initialStepId,
    (stepId: string, attempt: number) => {
      const step = run.steps[stepId];
      nodes[stepId] = {
        type: "step",
        step,
        stepId,
        attempt,
        width: 160,
        height: 50,
      };
      const execution = step.executions[attempt];
      if (!execution) {
        return;
      }
      const [assets, rest] = truncateList(Object.entries(execution.assets), 3);
      assets.forEach(([assetId, asset]) => {
        const text = truncatePath(asset.path) + (asset.type == 1 ? "/" : "");
        nodes[`asset:${assetId}`] = {
          type: "asset",
          stepId,
          assetId,
          asset,
          width: Math.min(getTextWidth(text) + 32, 140),
          height: 20,
        };
        edges[`${stepId}-asset:${assetId}`] = {
          from: stepId,
          to: `asset:${assetId}`,
          type: "asset",
        };
      });
      if (rest.length) {
        const nodeId = `assets:${rest.map(([id]) => id).join(",")}`;
        const text = `(+${rest.length} more)`;
        nodes[nodeId] = {
          type: "assets",
          stepId,
          assetIds: rest.map(([id]) => id),
          width: Math.min(getTextWidth(text) + 14, 100),
          height: 20,
        };
        edges[`${stepId}-${nodeId}`] = {
          from: stepId,
          to: nodeId,
          type: "asset",
        };
      }

      Object.entries(execution.dependencies).forEach(
        ([dependencyId, dependency]) => {
          if (dependency.execution.runId == runId) {
            edges[`${dependency.execution.stepId}-${stepId}`] = {
              from: dependency.execution.stepId,
              to: stepId,
              type: "dependency",
            };
          } else {
            // TODO: ?
          }
        },
      );
      execution.children.forEach((child) => {
        const childAttempt = getStepAttempt(run, stepAttempts, child);
        const childExecution =
          childAttempt && run.steps[child].executions[childAttempt];
        if (childExecution) {
          if (
            !Object.values(execution.dependencies).some(
              (d) => d.execution.stepId == child,
            )
          ) {
            edges[`${stepId}-${child}`] = {
              from: stepId,
              to: child,
              type: "child",
            };
          }
        } else {
          // TODO
        }
      });
      const result = execution?.result;
      if (
        result?.type == "deferred" ||
        result?.type == "cached" ||
        result?.type == "spawned"
      ) {
        const childRunId = result.execution.runId;
        if (childRunId != runId) {
          nodes[result.execution.runId] = {
            type: "child",
            child: result.execution,
            runId: childRunId,
            width: 100,
            height: 30,
          };
          if (
            Object.values(execution.dependencies).some(
              (d) => d.execution.runId == childRunId,
            )
          ) {
            edges[`${childRunId}-${stepId}`] = {
              from: childRunId,
              to: stepId,
              type: "dependency",
            };
          } else {
            edges[`${stepId}-${childRunId}`] = {
              from: stepId,
              to: childRunId,
              type: "child",
            };
          }
        } else {
          const childStepId = result.execution.stepId;
          // TODO: fix/remove this dependency check?
          if (
            Object.values(execution.dependencies).some(
              (d) => d.execution.stepId == childStepId,
            )
          ) {
            edges[`${childStepId}-${stepId}`] = {
              from: childStepId,
              to: stepId,
              type: "dependency",
            };
          } else {
            edges[`${stepId}-${childStepId}`] = {
              from: stepId,
              to: childStepId,
              type: "child",
            };
          }
        }
      }
    },
  );

  return new ELK()
    .layout({
      id: "root",
      layoutOptions: {
        "elk.spacing.nodeNode": "10",
        "elk.layered.considerModelOrder.strategy": "NODES_AND_EDGES",
      },
      children: Object.entries(nodes).map(([id, { width, height }]) => ({
        id,
        width,
        height,
      })),
      edges: Object.entries(edges).map(([id, { from, to }]) => ({
        id,
        sources: [from],
        targets: [to],
      })),
    })
    .then((graph) => {
      const nodes_ = graph.children!.reduce((result, child) => {
        const node = { ...nodes[child.id], x: child.x!, y: child.y! };
        return { ...result, [child.id]: node };
      }, {});
      const edges_ = graph.edges!.reduce((result, edge) => {
        // TODO: support multiple sections?
        const { startPoint, bendPoints, endPoint } = edge.sections![0];
        const path = [startPoint, ...(bendPoints || []), endPoint];
        const edge_ = { ...edges[edge.id], path };
        return { ...result, [edge.id]: edge_ };
      }, {});

      return {
        nodes: nodes_,
        edges: edges_,
        width: graph.width!,
        height: graph.height!,
      };
    });
}
