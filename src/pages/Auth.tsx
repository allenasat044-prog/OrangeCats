import { useState, type FormEvent } from "react";
import { Navigate, useNavigate } from "react-router-dom";
import { useAuth } from "../auth";

export default function Auth() {
  const { user, signIn, signUp } = useAuth();
  const navigate = useNavigate();
  const [mode, setMode] = useState<"signin" | "signup">("signin");
  const [name, setName] = useState("");
  const [email, setEmail] = useState("");
  const [password, setPassword] = useState("");
  const [error, setError] = useState<string | null>(null);
  const [busy, setBusy] = useState(false);

  if (user) return <Navigate to="/dashboard" replace />;

  const submit = async (e: FormEvent) => {
    e.preventDefault();
    setBusy(true);
    const result = mode === "signin" ? await signIn(email, password) : await signUp(name, email, password);
    setBusy(false);
    if (result) setError(result);
    else navigate("/dashboard");
  };

  return (
    <section className="auth">
      <h1>{mode === "signin" ? "Sign in" : "Create your account"}</h1>
      <form onSubmit={submit}>
        {mode === "signup" && (
          <label>
            Full name
            <input value={name} onChange={(e) => setName(e.target.value)} autoComplete="name" />
          </label>
        )}
        <label>
          Email
          <input type="email" value={email} onChange={(e) => setEmail(e.target.value)} autoComplete="email" />
        </label>
        <label>
          Password
          <input
            type="password"
            value={password}
            onChange={(e) => setPassword(e.target.value)}
            autoComplete={mode === "signin" ? "current-password" : "new-password"}
          />
        </label>
        {error && <p className="error">{error}</p>}
        <button className="btn" disabled={busy}>{mode === "signin" ? "Sign in" : "Sign up"}</button>
      </form>
      <p className="muted">
        {mode === "signin" ? "New here?" : "Already registered?"}{" "}
        <button
          className="link"
          onClick={() => {
            setError(null);
            setMode(mode === "signin" ? "signup" : "signin");
          }}
        >
          {mode === "signin" ? "Create an account" : "Sign in instead"}
        </button>
      </p>
    </section>
  );
}
