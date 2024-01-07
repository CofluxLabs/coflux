import { ReactNode, useCallback } from "react";
import { Link, useLocation, useSearchParams } from "react-router-dom";
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
    [setHovered, runId, stepId, attemptNumber]
  );
  const handleMouseOut = useCallback(() => setHovered(undefined), []);
  return (
    <Link
      to={buildUrl(location.pathname, {
        environment: environmentName,
        step: isActive ? undefined : stepId,
        attempt: isActive ? undefined : attemptNumber,
      })}
      className={classNames(
        className,
        isActive
          ? activeClassName
          : isHovered(runId, stepId, attemptNumber)
          ? hoveredClassName
          : undefined
      )}
      onMouseOver={handleMouseOver}
      onMouseOut={handleMouseOut}
    >
      {children}
    </Link>
  );
}
