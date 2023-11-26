import { ReactNode, createContext, useContext, useId } from "react";

const Context = createContext("");

type Props = {
  label: ReactNode;
  hint?: ReactNode;
  children: ReactNode;
};

export default function Field({ label, hint, children }: Props) {
  const id = useId();
  return (
    <Context.Provider value={id}>
      <div className="my-3">
        <div className="mb-1">
          <label className="font-medium" htmlFor={id}>
            {label}
            {hint && (
              <span className="text-slate-400 ml-1 text-sm">({hint})</span>
            )}
          </label>
        </div>
        <div>{children}</div>
      </div>
    </Context.Provider>
  );
}

export function useFieldId() {
  const id = useContext(Context);
  return id || undefined;
}
