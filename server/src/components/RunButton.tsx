import { Fragment, useCallback, useState } from "react";

import * as models from "../models";
import RunDialog from "./RunDialog";
import Button from "./common/Button";

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
      <Button onClick={handleRunClick}>Run...</Button>
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