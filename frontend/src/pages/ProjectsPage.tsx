import { Link } from 'react-router-dom';

export default function ProjectsPage() {
  return (
    <div>
      <h1>Projects</h1>
      <ul>
        <li><Link to="/projects/project_1">Project 1</Link></li>
        <li><Link to="/projects/project_2">Project 2</Link></li>
      </ul>
    </div>
  );
}
