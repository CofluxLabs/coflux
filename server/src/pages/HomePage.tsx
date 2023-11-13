import { Link } from "react-router-dom";

export default function HomePage() {
  return (
    <div>
      <h1>Home</h1>
      <Link to="/projects">Projects</Link>
    </div>
  );
}
