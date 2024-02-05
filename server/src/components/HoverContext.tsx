import {
  ReactNode,
  createContext,
  useCallback,
  useContext,
  useState,
} from "react";

type Hovered = [string, string | undefined, number | undefined];

const Context = createContext<
  [Hovered | undefined, (hovered: Hovered | undefined) => void] | undefined
>(undefined);

export function useHoverContext() {
  const value = useContext(Context);
  if (!value) {
    throw new Error("not in hover context");
  }
  const [state, setState] = value;
  const isHovered = useCallback(
    (runId: string, stepId?: string, attempt?: number) => {
      return (
        state &&
        runId == state[0] &&
        (!stepId || stepId == state[1]) &&
        (!attempt || attempt == state[2])
      );
    },
    [state],
  );
  const setHovered = useCallback(
    (runId?: string, stepId?: string, attempt?: number) => {
      setState(runId ? [runId, stepId, attempt] : undefined);
    },
    [],
  );
  return { isHovered, setHovered };
}

type Props = {
  children: ReactNode;
};

export default function HoverContext({ children }: Props) {
  const [state, setState] = useState<Hovered>();
  return (
    <Context.Provider value={[state, setState]}>{children}</Context.Provider>
  );
}
