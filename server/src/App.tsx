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
  RunsPage,
  LogsPage,
  TargetPage,
} from "./pages";
import NewProjectDialog from "./components/NewProjectDialog";
import TitleContext from "./components/TitleContext";

function NotFound() {
  return <p>Not found</p>;
}

export default function App() {
  return (
    <TitleContext appName="Coflux">
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
                  path="targets/:repository/:target"
                  element={<TargetPage />}
                />
                <Route path="runs/:run" element={<RunLayout />}>
                  <Route index={true} element={<RunPage />} />
                  <Route path="graph" element={<GraphPage />} />
                  <Route path="timeline" element={<TimelinePage />} />
                  <Route path="runs" element={<RunsPage />} />
                  <Route path="logs" element={<LogsPage />} />
                </Route>
              </Route>
            </Route>
          </Route>
          <Route path="*" element={<NotFound />} />
        </Routes>
      </Router>
    </TitleContext>
  );
}
