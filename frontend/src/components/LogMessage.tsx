import classNames from "classnames";

import * as models from "../models";

function classForLevel(level: 0 | 1 | 2 | 3 | 4 | 5) {
  switch (level) {
    case 0:
      return ["Stdout", "text-gray-200"];
    case 1:
      return ["Stderr", "text-red-200"];
    case 2:
      return ["Debug", "border-gray-400"];
    case 3:
      return ["Info", "border-blue-400"];
    case 4:
      return ["Warning", "border-yellow-400"];
    case 5:
      return ["Error", "border-red-400"];
  }
}

type Props = {
  message: models.LogMessage;
  className?: string;
};

export default function LogMessage({ message, className }: Props) {
  const [level, levelClassName] = classForLevel(message[2]);
  return (
    <div
      className={classNames(className, "border-l-4 pl-2", levelClassName)}
      title={level}
    >
      {message[3]}
    </div>
  );
}
