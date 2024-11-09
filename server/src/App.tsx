import { ComponentType, ReactNode } from "react";
import { BrowserRouter as Router, Route, Routes } from "react-router-dom";

import {
  ExternalLayout,
  InternalLayout,
  ProjectLayout,
  RunLayout,
} from "./layouts";
import {
  HomePage,
  ProjectPage,
  ProjectsPage,
  RunPage,
  GraphPage,
  TimelinePage,
  AssetsPage,
  RunsPage,
  LogsPage,
  WorkflowPage,
  SensorPage,
  RepositoryPage,
} from "./pages";
import NewProjectDialog from "./components/NewProjectDialog";
import TitleContext from "./components/TitleContext";

function NotFound() {
  return <p>Not found</p>;
}

type Provider<P = {}> = [ComponentType<P>, P];

type ProvidersProps = {
  providers: Provider<any>[];
  children: ReactNode;
};

function Providers({ providers, children }: ProvidersProps) {
  return providers.reduceRight(
    (acc, [Provider, props]) => <Provider {...props}>{acc}</Provider>,
    children,
  );
}

export default function App() {
  return (
    <Providers providers={[[TitleContext, { appName: "Coflux" }]]}>
      <Router>
        <Routes>
          <Route element={<ExternalLayout />}>
            <Route index={true} element={<HomePage />} />
          </Route>
          <Route element={<InternalLayout />}>
            <Route path="projects">
              <Route element={<ProjectsPage />}>
                <Route index={true} element={null} />
                <Route path="new" element={<NewProjectDialog />} />
              </Route>
              <Route path=":project" element={<ProjectLayout />}>
                <Route index={true} element={<ProjectPage />} />
                <Route
                  path="repositories/:repository"
                  element={<RepositoryPage />}
                />
                <Route
                  path="workflows/:repository/:target"
                  element={<WorkflowPage />}
                />
                <Route
                  path="sensors/:repository/:target"
                  element={<SensorPage />}
                />
                <Route path="runs/:run" element={<RunLayout />}>
                  <Route index={true} element={<RunPage />} />
                  <Route path="graph" element={<GraphPage />} />
                  <Route path="timeline" element={<TimelinePage />} />
                  <Route path="assets" element={<AssetsPage />} />
                  <Route path="runs" element={<RunsPage />} />
                  <Route path="logs" element={<LogsPage />} />
                </Route>
              </Route>
            </Route>
          </Route>
          <Route path="*" element={<NotFound />} />
        </Routes>
      </Router>
    </Providers>
  );
}
