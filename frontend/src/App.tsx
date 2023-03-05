import React, { Suspense } from 'react';
import { BrowserRouter as Router, Route, Routes } from 'react-router-dom';

const ExternalLayout = React.lazy(() => import('./layouts/ExternalLayout'));
const ProjectLayout = React.lazy(() => import('./layouts/ProjectLayout'));
const RunLayout = React.lazy(() => import('./layouts/RunLayout'));

const HomePage = React.lazy(() => import('./pages/HomePage'));
const ProjectPage = React.lazy(() => import('./pages/ProjectPage'));
const ProjectsPage = React.lazy(() => import('./pages/ProjectsPage'));
const GraphPage = React.lazy(() => import('./pages/GraphPage'));
const TimelinePage = React.lazy(() => import('./pages/TimelinePage'));
const LogsPage = React.lazy(() => import('./pages/LogsPage'));
const TaskPage = React.lazy(() => import('./pages/TaskPage'));
const SensorPage = React.lazy(() => import('./pages/SensorPage'));

function NotFound() {
  return <p>Not found</p>;
}

export default function App() {
  return (
    <Suspense fallback={<p>Loading...</p>}>
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
              <Route path="sensors/:repository/:sensor" element={<SensorPage />} />
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
    </Suspense>
  );
}
