import { Fragment, useCallback, useState } from "react";

import * as models from "../models";
import RunDialog from "./RunDialog";

type Props = {
  task: models.Task;
  onRun: (parameters: ["json", string][]) => Promise<void>;
};

export default function RunButton({ task, onRun }: Props) {
  const [starting, setStarting] = useState(false);
  const [runDialogOpen, setRunDialogOpen] = useState(false);
  const handleRunClick = useCallback(() => {
    setRunDialogOpen(true);
  }, []);
  const handleRun = useCallback((parameters: ["json", string][]) => {
    setStarting(true);
    onRun(parameters).then(() => {
      setStarting(false);
      setRunDialogOpen(false);
    });
  }, []);
  const handleRunDialogClose = useCallback(() => setRunDialogOpen(false), []);
  return (
    <Fragment>
      <button
        className="px-2 py-1 m-2 border border-slate-400 text-slate-500 rounded font-bold hover:bg-slate-100"
        onClick={handleRunClick}
      >
        Run...
      </button>
      <RunDialog
        parameters={task.parameters}
        open={runDialogOpen}
        starting={starting}
        onRun={handleRun}
        onClose={handleRunDialogClose}
      />
    </Fragment>
  );
}
