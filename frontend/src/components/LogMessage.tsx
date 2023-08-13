import classNames from "classnames";

import * as models from "../models";

function classForLevel(level: 0 | 1 | 2 | 3): string {
  switch (level) {
    case 0:
      return "border-gray-200";
    case 1:
      return "border-blue-300";
    case 2:
      return "border-yellow-300";
    case 3:
      return "border-red-400";
  }
}

type Props = {
  message: models.LogMessage;
  size?: number;
  className?: string;
};

export default function LogMessage({ message, size = 16, className }: Props) {
  return (
    <div
      className={classNames(
        className,
        "border-l-4 pl-2",
        classForLevel(message.level)
      )}
    >
      {message.message}
    </div>
  );
}
