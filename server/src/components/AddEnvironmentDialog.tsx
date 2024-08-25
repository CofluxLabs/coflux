import Dialog from "./common/Dialog";
import CodeBlock from "./CodeBlock";
import { useMemo } from "react";
import { randomName } from "../utils";
import Button from "./common/Button";

type Props = {
  open: boolean;
  onClose: () => void;
};

export default function AddEnvironmentDialog({ open, onClose }: Props) {
  const exampleName = useMemo(() => randomName(), []);
  return (
    <Dialog title="Add environment" open={open} onClose={onClose}>
      <p className="my-2">Use the CLI to add a new environment:</p>
      <CodeBlock
        className="bg-slate-50"
        code={[
          "coflux environment.register \\",
          `  --environment=${exampleName}`,
        ]}
      />
      <p className="my-2">
        And, if you like, set it as your default environment:
      </p>
      <CodeBlock
        className="bg-slate-50"
        code={["coflux configure \\", `  --environment=${exampleName}`]}
      />
      <div className="mt-4">
        <Button
          type="button"
          outline={true}
          variant="secondary"
          onClick={onClose}
        >
          Close
        </Button>
      </div>
    </Dialog>
  );
}
