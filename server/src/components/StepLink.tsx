import { ReactNode, useCallback } from "react";
import {
  Link,
  useLocation,
  useParams,
  useSearchParams,
} from "react-router-dom";
import classNames from "classnames";

import { buildUrl } from "../utils";
import { useHoverContext } from "./HoverContext";

type Props = {
  runId: string;
  stepId: string;
  attemptNumber?: number;
  className?: string;
  activeClassName?: string;
  hoveredClassName?: string;
  children: ReactNode;
};

export default function StepLink({
  runId,
  stepId,
  attemptNumber,
  className,
  activeClassName,
  hoveredClassName,
  children,
}: Props) {
  const location = useLocation();
  const { project: projectId } = useParams();
  const [searchParams] = useSearchParams();
  const environmentName = searchParams.get("environment") || undefined;
  const activeStepId = searchParams.get("step") || undefined;
  const activeAttemptNumber = searchParams.has("attempt")
    ? parseInt(searchParams.get("attempt")!)
    : undefined;
  const { isHovered, setHovered } = useHoverContext();
  const isActive =
    stepId == activeStepId &&
    (!attemptNumber || activeAttemptNumber == attemptNumber);
  const handleMouseOver = useCallback(
    () => setHovered(runId, stepId, attemptNumber),
    [setHovered, runId, stepId, attemptNumber],
  );
  const handleMouseOut = useCallback(() => setHovered(undefined), []);
  // TODO: better way to determine page
  // TODO: switch back to graph page if changing run?
  const parts = location.pathname.split("/");
  const page = parts.length == 6 ? parts[5] : undefined;
  return (
    <Link
      to={buildUrl(
        `/projects/${projectId}/runs/${runId}${page ? "/" + page : ""}`,
        {
          environment: environmentName,
          step: isActive ? undefined : stepId,
          attempt: isActive ? undefined : attemptNumber,
        },
      )}
      className={classNames(
        className,
        isActive
          ? activeClassName
          : isHovered(runId, stepId, attemptNumber)
          ? hoveredClassName
          : undefined,
      )}
      onMouseOver={handleMouseOver}
      onMouseOut={handleMouseOut}
    >
      {children}
    </Link>
  );
}
