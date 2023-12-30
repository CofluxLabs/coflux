import classNames from "classnames";

import * as models from "../models";

function classForLevel(level: 0 | 1 | 2 | 3 | 4 | 5) {
  switch (level) {
    case 0:
      return ["Debug", "border-l-4 pl-1 border-gray-400"];
    case 1:
      return ["Stdout", "text-gray-600 font-mono text-sm"];
    case 2:
      return ["Info", "border-l-4 pl-1 border-blue-400"];
    case 3:
      return ["Stderr", "text-red-400 font-mono text-sm"];
    case 4:
      return ["Warning", "border-l-4 pl-1 border-yellow-400"];
    case 5:
      return ["Error", "border-l-4 pl-1 border-red-400"];
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
      className={classNames(className, "whitespace-pre", levelClassName)}
      title={level}
    >
      {message[3]}
    </div>
  );
}
