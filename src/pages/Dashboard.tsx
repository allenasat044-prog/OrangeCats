import { Link } from "react-router-dom";
import { useAuth } from "../auth";
import { folders, roles, schedule, stages } from "../data";
import { stageResult, useEvidence } from "../evidence";

export default function Dashboard() {
  const { user } = useAuth();
  const { state } = useEvidence(4000);
  const data = state.status === "ready" ? state.data : null;

  const total = stages.reduce((s, x) => s + x.minutes, 0);
  const verified = (id: number) => {
    if (!data) return false;
    const r = stageResult(data, id);
    return r.total > 0 && r.passed === r.total;
  };
  const finished = stages.filter((s) => verified(s.id)).reduce((s, x) => s + x.minutes, 0);
  const percent = Math.round((finished / total) * 100);

  return (
    <>
      <h1>Welcome, {user?.name}</h1>

      <section>
        <h2>Build progress</h2>
        <div className="bar"><div style={{ width: `${percent}%` }} /></div>
        {data ? (
          <p className="muted">
            {percent}% of the build verified by the terminal. Evidence captured {new Date(data.generatedAt).toLocaleString()}.
          </p>
        ) : (
          <p className="muted">
            No terminal evidence yet. <Link to="/evidence">Capture it from the Evidence page.</Link>
          </p>
        )}
        <ul className="stages">
          {stages.map((s) => {
            const r = data ? stageResult(data, s.id) : null;
            return (
              <li key={s.id}>
                <strong>Stage {s.id}: {s.title}</strong> <span className="muted">({s.minutes} min)</span>{" "}
                {r && r.total > 0 ? (
                  <span className={`pill ${r.passed === r.total ? "pass" : "fail"}`}>
                    {r.passed === r.total ? `Verified ${r.passed}/${r.total}` : `${r.passed}/${r.total} checks passed`}
                  </span>
                ) : (
                  <span className="pill none">No evidence</span>
                )}
                <ul>{s.tasks.map((t) => <li key={t}>{t}</li>)}</ul>
              </li>
            );
          })}
        </ul>
      </section>

      <section>
        <h2>Roles</h2>
        <div className="grid">
          {roles.map((r) => (
            <div className="card" key={r.id}>
              <h3>{r.label}</h3>
              <p>{r.duty}</p>
              <p className="muted">Group: {r.id}</p>
            </div>
          ))}
        </div>
      </section>

      <section>
        <h2>Shared folders</h2>
        <table>
          <thead><tr><th>Path</th><th>Purpose</th></tr></thead>
          <tbody>
            {folders.map((f) => (
              <tr key={f.id}><td><code>/Volumes/hospital/{f.id}</code></td><td>{f.label}</td></tr>
            ))}
          </tbody>
        </table>
      </section>

      <section>
        <h2>Scheduled jobs</h2>
        <table>
          <thead><tr><th>Job</th><th>Trigger</th><th>Runs</th></tr></thead>
          <tbody>
            {schedule.map((j) => (
              <tr key={j.job}><td>{j.job}</td><td><code>{j.trigger}</code></td><td>{j.meaning}</td></tr>
            ))}
          </tbody>
        </table>
      </section>
    </>
  );
}
