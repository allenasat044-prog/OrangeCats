import { useState } from "react";
import { useAuth } from "../auth";
import { folders, roles, schedule, stages } from "../data";

export default function Dashboard() {
  const { user } = useAuth();
  const [done, setDone] = useState<number[]>(() => {
    try {
      return JSON.parse(localStorage.getItem("hit_progress") || "[]");
    } catch {
      return [];
    }
  });

  const toggle = (id: number) => {
    const next = done.includes(id) ? done.filter((d) => d !== id) : [...done, id];
    setDone(next);
    localStorage.setItem("hit_progress", JSON.stringify(next));
  };

  const total = stages.reduce((s, x) => s + x.minutes, 0);
  const finished = stages.filter((s) => done.includes(s.id)).reduce((s, x) => s + x.minutes, 0);
  const percent = Math.round((finished / total) * 100);

  return (
    <>
      <h1>Welcome, {user?.name}</h1>

      <section>
        <h2>Build progress</h2>
        <div className="bar"><div style={{ width: `${percent}%` }} /></div>
        <p className="muted">{percent}% complete, {finished} of {total} planned minutes done</p>
        <ul className="stages">
          {stages.map((s) => (
            <li key={s.id}>
              <label>
                <input type="checkbox" checked={done.includes(s.id)} onChange={() => toggle(s.id)} />
                <strong>Stage {s.id}: {s.title}</strong> <span className="muted">({s.minutes} min)</span>
              </label>
              <ul>{s.tasks.map((t) => <li key={t}>{t}</li>)}</ul>
            </li>
          ))}
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
              <tr key={f.id}><td><code>/hospital/{f.id}</code></td><td>{f.label}</td></tr>
            ))}
          </tbody>
        </table>
      </section>

      <section>
        <h2>Scheduled jobs</h2>
        <table>
          <thead><tr><th>Job</th><th>Cron</th><th>Runs</th></tr></thead>
          <tbody>
            {schedule.map((j) => (
              <tr key={j.job}><td>{j.job}</td><td><code>{j.cron}</code></td><td>{j.meaning}</td></tr>
            ))}
          </tbody>
        </table>
      </section>
    </>
  );
}
