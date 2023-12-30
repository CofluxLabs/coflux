import classNames from "classnames";

import * as models from "../models";
import {
  IconAlertTriangle,
  IconInfoCircle,
  IconAlertHexagon,
} from "@tabler/icons-react";

function classForLevel(level: models.LogMessageLevel) {
  switch (level) {
    case 1:
      return "text-gray-600 font-mono text-sm";
    case 3:
      return "text-red-800 font-mono text-sm";
    default:
      return null;
  }
}

function iconForLevel(
  level: models.LogMessageLevel,
  className: string,
  size = 20
) {
  switch (level) {
    case 2:
      return (
        <IconInfoCircle
          size={size}
          className={classNames(className, "text-blue-400")}
        />
      );
    case 4:
      return (
        <IconAlertTriangle
          size={size}
          className={classNames(className, "text-yellow-600")}
        />
      );
    case 5:
      return (
        <IconAlertHexagon
          size={size}
          className={classNames(className, "text-red-600")}
        />
      );
    default:
      return null;
  }
}

type Props = {
  level: models.LogMessageLevel;
  content: string;
  className?: string;
};

export default function LogMessage({ level, content, className }: Props) {
  return (
    <div
      className={classNames(className, "leading-tight", classForLevel(level))}
    >
      {iconForLevel(level, "inline-block mr-0.5 -mt-px")}
      <span className="whitespace-pre-wrap">{content}</span>
    </div>
  );
}
