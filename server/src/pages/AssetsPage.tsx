import { useParams } from "react-router-dom";
import { sortBy } from "lodash";

import * as models from "../models";
import { useContext } from "../layouts/RunLayout";
import AssetLink from "../components/AssetLink";
import AssetIcon from "../components/AssetIcon";
import StepLink from "../components/StepLink";
import { getAssetMetadata } from "../assets";

type Item = [
  string,
  models.Step,
  number,
  models.Execution,
  string,
  models.Asset,
];

export default function AssetsPage() {
  const { run } = useContext();
  const { run: runId } = useParams();
  const assets: Item[] = sortBy(
    Object.entries(run.steps).flatMap(([stepId, step]) =>
      Object.entries(step.executions).flatMap(([attempt, execution]) =>
        Object.entries(execution.assets).map(
          ([assetId, asset]) =>
            [
              stepId,
              step,
              parseInt(attempt, 10),
              execution,
              assetId,
              asset,
            ] as Item,
        ),
      ),
    ),
    (item) => item[5].createdAt,
  );
  return (
    <div className="p-4">
      {assets.length ? (
        <table className="w-full">
          <tbody className="divide-y divide-slate-100">
            {assets.map(
              ([stepId, step, attempt, execution, assetId, asset]) => (
                <tr key={assetId}>
                  <td className="py-1">
                    <StepLink
                      runId={runId!}
                      stepId={stepId}
                      attempt={attempt}
                      className="block max-w-full rounded truncate leading-none text-sm ring-offset-1 w-40"
                      activeClassName="ring-2 ring-cyan-400"
                      hoveredClassName="ring-2 ring-slate-300"
                    >
                      <span className="font-mono">{step.target}</span>{" "}
                      <span className="text-slate-500 text-sm">
                        ({step.repository})
                      </span>
                    </StepLink>
                  </td>
                  <td className="py-1">
                    <AssetLink asset={asset} className="flex items-start gap-1">
                      <AssetIcon asset={asset} size={18} className="mt-1" />
                      {asset.path + (asset.type == 1 ? "/" : "")}
                    </AssetLink>
                  </td>
                  <td className="py-1">
                    <span className="text-slate-500 text-sm">
                      {getAssetMetadata(asset).join(", ")}
                    </span>
                  </td>
                </tr>
              ),
            )}
          </tbody>
        </table>
      ) : (
        <p className="italic">None</p>
      )}
    </div>
  );
}
