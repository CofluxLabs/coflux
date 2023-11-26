import { Fragment, useCallback } from "react";
import { Link, useParams, useSearchParams } from "react-router-dom";
import { useTopic } from "@topical/react";

import * as models from "../models";
import Loading from "../components/Loading";
import { buildUrl } from "../utils";
import TargetHeader from "../components/TargetHeader";
import { DateTime } from "luxon";
import { useSetActiveTarget } from "../layouts/ProjectLayout";
import Button from "../components/common/Button";

type HeaderProps = {
  sensor: models.Sensor;
  onActivate: () => void;
  onDeactivate: () => void;
};

function Header({ sensor, onDeactivate, onActivate }: HeaderProps) {
  return (
    <TargetHeader repository={sensor.repository} target={sensor.target}>
      <div className="flex-1 flex justify-end">
        {sensor.activated ? (
          <Button onClick={onDeactivate}>Deactivate</Button>
        ) : (
          <Button onClick={onActivate}>Activate</Button>
        )}
      </div>
    </TargetHeader>
  );
}

export default function SensorPage() {
  const { project: projectId, repository, sensor: sensorName } = useParams();
  const [searchParams] = useSearchParams();
  const environmentName = searchParams.get("environment") || undefined;
  const [sensor, { execute }] = useTopic<models.Sensor>(
    "projects",
    projectId,
    "environments",
    environmentName,
    "sensors",
    repository,
    sensorName
  );
  const handleActivateClick = useCallback(() => {
    execute("activate").then(() => {});
  }, []);
  const handleDeactivateClick = useCallback(() => {
    execute("deactivate").then(() => {});
  }, []);
  useSetActiveTarget(sensor);
  if (!sensor) {
    return <Loading />;
  } else {
    return (
      <Fragment>
        <Header
          sensor={sensor}
          onActivate={handleActivateClick}
          onDeactivate={handleDeactivateClick}
        />
        <div className="flex-1 overflow-auto p-4">
          {Object.keys(sensor.runs).length ? (
            <table className="w-full">
              <tbody>
                {Object.entries(sensor.runs).map(([runId, run]) => {
                  const createdAt = DateTime.fromMillis(run.createdAt);
                  return (
                    <tr key={runId}>
                      <td>
                        {createdAt.toLocaleString(
                          DateTime.DATETIME_FULL_WITH_SECONDS
                        )}
                      </td>
                      <td>
                        <Link
                          to={buildUrl(`/projects/${projectId}/runs/${runId}`, {
                            environment: environmentName,
                          })}
                        >
                          <span className="font-mono">{run.target}</span>{" "}
                          <span className="text-gray-500 text-sm">
                            ({run.repository})
                          </span>
                        </Link>
                      </td>
                    </tr>
                  );
                })}
              </tbody>
            </table>
          ) : (
            <p>No runs</p>
          )}
        </div>
      </Fragment>
    );
  }
}
