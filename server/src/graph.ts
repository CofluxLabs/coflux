import ELK from "elkjs/lib/elk.bundled.js";
import { max, sortBy } from "lodash";

import * as models from "./models";

type BaseNode = (
  | {
      type: "step";
      step: models.Step;
      stepId: string;
      attempt: number;
    }
  | {
      type: "parent";
      parent: models.Reference | null;
    }
  | {
      type: "child";
      child: models.Child;
      runId: string;
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
  type: "dependency" | "child" | "transitive" | "parent";
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
    max(Object.keys(step.executions).map((s) => parseInt(s, 10)))
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
      if (typeof child == "string" && !(child in seen)) {
        traverseRun(run, stepAttempts, child, callback, {
          ...seen,
          [child]: true,
        });
      }
    });
  }
}

export default function buildGraph(
  run: models.Run,
  runId: string,
  activeStepId: string | undefined,
  activeAttempt: number | undefined,
): Promise<Graph> {
  const stepAttempts = chooseStepAttempts(run, activeStepId, activeAttempt);

  const initialStepId = sortBy(
    Object.keys(run.steps).filter((id) => !run.steps[id].parentId),
    (stepId) => run.steps[stepId].createdAt,
  )[0];

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

  traverseRun(
    run,
    stepAttempts,
    initialStepId,
    (stepId: string, attempt: number) => {
      const step = run.steps[stepId];
      nodes[stepId] = {
        type: "step",
        step: step,
        stepId,
        attempt,
        width: 160,
        height: 50,
      };
      const execution = step.executions[attempt];
      if (!execution) {
        return;
      }
      Object.entries(execution.dependencies).forEach(
        ([dependencyId, dependency]) => {
          if (dependency.runId == runId) {
            if (
              !execution.children.some(
                (c) =>
                  typeof c == "string" &&
                  Object.values(run.steps[c].executions).some(
                    (e) =>
                      e.result?.type == "cached" &&
                      e.executionId == dependencyId,
                  ),
              )
            ) {
              edges[`${dependency.stepId}-${stepId}`] = {
                from: dependency.stepId,
                to: stepId,
                type: "dependency",
              };
            }
          } else {
            // TODO: connect to node for (child/parent) run? (if it exists?)
          }
        },
      );
      execution.children.forEach((child) => {
        if (typeof child == "string") {
          const childAttempt = getStepAttempt(run, stepAttempts, child);
          const childExecution =
            childAttempt && run.steps[child].executions[childAttempt];
          if (childExecution) {
            if (childExecution.result?.type == "cached") {
              const cachedExecutionId = childExecution.executionId;
              const cachedStepId = Object.keys(run.steps).find(
                (sId) =>
                  sId in visibleSteps &&
                  Object.values(run.steps[sId].executions).some(
                    (e) =>
                      e.result?.type != "cached" &&
                      e.executionId == cachedExecutionId,
                  ),
              );
              if (cachedExecutionId in execution.dependencies) {
                edges[`${child}-${stepId}`] = {
                  from: child,
                  to: stepId,
                  type: "dependency",
                };
                if (cachedStepId) {
                  edges[`${cachedStepId}-${child}`] = {
                    from: cachedStepId,
                    to: child,
                    type: "transitive",
                  };
                }
              } else {
                edges[`${stepId}-${child}`] = {
                  from: stepId,
                  to: child,
                  type: "child",
                };
                if (cachedStepId) {
                  edges[`${child}-${cachedStepId}`] = {
                    from: child,
                    to: cachedStepId,
                    type: "transitive",
                  };
                }
              }
            } else if (
              !Object.values(execution.dependencies).some(
                (d) => d.stepId == child,
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
        } else {
          nodes[child.runId] = {
            type: "child",
            child,
            runId: child.runId,
            width: 160,
            height: 50,
          };
          if (
            Object.values(execution.dependencies).some(
              (d) => d.runId == child.runId,
            )
          ) {
            edges[`${child.runId}-${stepId}`] = {
              from: child.runId,
              to: stepId,
              type: "dependency",
            };
          } else {
            edges[`${stepId}-${child.runId}`] = {
              from: stepId,
              to: child.runId,
              type: "child",
            };
          }
        }
      });
    },
  );

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

  return new ELK()
    .layout({
      id: "root",
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
      layoutOptions: {
        "elk.edgeRouting": "ORTHOGONAL",
        "elk.layered.nodePlacement.strategy": "NETWORK_SIMPLEX",
      },
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
