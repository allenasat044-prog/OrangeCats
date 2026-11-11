import { Link, NavLink, Outlet, useNavigate } from "react-router-dom";
import { useAuth } from "../auth";

export default function Layout() {
  const { user, signOut } = useAuth();
  const navigate = useNavigate();

  return (
    <div className="shell">
      <header className="topbar">
        <Link to="/" className="logo">
          <span className="logo-a">HOSPITAL</span>
          <span className="logo-b">IT</span>
        </Link>
        <nav>
          {user && <NavLink to="/evidence">Evidence</NavLink>}
          <NavLink to="/faq">FAQs</NavLink>
          {user ? (
            <button
              className="pill-solid"
              onClick={() => {
                signOut();
                navigate("/");
              }}
            >
              Sign out
            </button>
          ) : (
            <NavLink to="/auth" className="pill-solid">Sign in</NavLink>
          )}
        </nav>
      </header>
      <main className="page-wrap">
        <div className="page">
          <Outlet />
        </div>
      </main>
      <footer className="footer">Server administration project for hospital staff access, storage and backup.</footer>
    </div>
  );
}
