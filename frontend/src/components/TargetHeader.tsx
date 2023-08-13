import { ReactNode } from "react";

type Props = {
  repository: string;
  target: string;
  children?: ReactNode;
};

export default function TargetHeader({ repository, target, children }: Props) {
  return (
    <div className="p-4 flex">
      <h1 className="flex items-center">
        <span className="text-xl font-bold font-mono">{target}</span>
        <span className="ml-2 text-gray-500">({repository})</span>
      </h1>
      {children}
    </div>
  );
}
