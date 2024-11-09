import { ReactNode, createContext, useContext } from "react";
import useLocalStorage from "../hooks/useLocalStorage";
import * as settings from "../settings";

const Context = createContext<string | undefined>(undefined);

const defaultSettings: settings.Settings = {
  blobStores: [
    {
      type: "http",
      protocol: window.location.protocol == "https:" ? "https" : "http",
      host: window.location.host,
    },
  ],
};

export function useSettings() {
  const projectId = useContext(Context);
  if (!projectId) {
    throw new Error("not in context");
  }
  return useLocalStorage(`${projectId}/settings`, defaultSettings);
}

export function useSetting(key: keyof typeof defaultSettings) {
  const [settings] = useSettings();
  return settings[key];
}

type Props = {
  projectId: string | undefined;
  children: ReactNode;
};

export default function SettingsProvider({ projectId, children }: Props) {
  return <Context.Provider value={projectId}>{children}</Context.Provider>;
}
