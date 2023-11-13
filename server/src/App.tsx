import { BrowserRouter as Router, Route, Routes } from "react-router-dom";

import { ExternalLayout, ProjectLayout, RunLayout } from "./layouts";
import {
  HomePage,
  ProjectPage,
  ProjectsPage,
  GraphPage,
  TimelinePage,
  LogsPage,
  TaskPage,
  SensorPage,
} from "./pages";

function NotFound() {
  return <p>Not found</p>;
}

export default function App() {
  return (
    <Router>
      <Routes>
        <Route element={<ExternalLayout />}>
          <Route index={true} element={<HomePage />} />
          <Route path="projects" element={<ProjectsPage />} />
        </Route>
        <Route path="projects">
          <Route path=":project" element={<ProjectLayout />}>
            <Route index={true} element={<ProjectPage />} />
            <Route path="tasks/:repository/:target" element={<TaskPage />} />
            <Route
              path="sensors/:repository/:sensor"
              element={<SensorPage />}
            />
            <Route path="runs/:run" element={<RunLayout />}>
              <Route index={true} element={<GraphPage />} />
              <Route path="timeline" element={<TimelinePage />} />
              <Route path="logs" element={<LogsPage />} />
            </Route>
          </Route>
        </Route>
        <Route path="*" element={<NotFound />} />
      </Routes>
    </Router>
  );
}
