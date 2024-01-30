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
  attempt?: number;
  className?: string;
  activeClassName?: string;
  hoveredClassName?: string;
  children: ReactNode;
};

export default function StepLink({
  runId,
  stepId,
  attempt,
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
  const activeAttempt = searchParams.has("attempt")
    ? parseInt(searchParams.get("attempt")!)
    : undefined;
  const { isHovered, setHovered } = useHoverContext();
  const isActive =
    stepId == activeStepId && (!attempt || activeAttempt == attempt);
  const handleMouseOver = useCallback(
    () => setHovered(runId, stepId, attempt),
    [setHovered, runId, stepId, attempt],
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
          attempt: isActive ? undefined : attempt,
        },
      )}
      className={classNames(
        className,
        isActive
          ? activeClassName
          : isHovered(runId, stepId, attempt)
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
