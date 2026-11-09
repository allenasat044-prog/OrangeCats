import { useState } from "react";
import { folders, modeFor, roles, stages, type Role } from "../data";

const label = { rw: "Read and write", r: "Read only", none: "No access" } as const;

export default function Analysis() {
  const [role, setRole] = useState<Role>("nurses");
  const [folderId, setFolderId] = useState(folders[0].id);
  const [action, setAction] = useState<"read" | "write">("write");

  const folder = folders.find((f) => f.id === folderId)!;
  const level = folder.access[role];
  const allowed = action === "read" ? level !== "none" : level === "rw";
  const maxMinutes = Math.max(...stages.map((s) => s.minutes));
  const total = stages.reduce((s, x) => s + x.minutes, 0);

  return (
    <>
      <h1>Analysis</h1>

      <section>
        <h2>Access matrix</h2>
        <table>
          <thead>
            <tr>
              <th>Folder</th>
              {roles.map((r) => <th key={r.id}>{r.label}</th>)}
            </tr>
          </thead>
          <tbody>
            {folders.map((f) => (
              <tr key={f.id}>
                <td><code>/hospital/{f.id}</code></td>
                {roles.map((r) => (
                  <td key={r.id} className={`cell ${f.access[r.id]}`}>{label[f.access[r.id]]}</td>
                ))}
              </tr>
            ))}
          </tbody>
        </table>
      </section>

      <section>
        <h2>Permission checker</h2>
        <div className="row">
          <select value={role} onChange={(e) => setRole(e.target.value as Role)}>
            {roles.map((r) => <option key={r.id} value={r.id}>{r.label}</option>)}
          </select>
          <select value={action} onChange={(e) => setAction(e.target.value as "read" | "write")}>
            <option value="read">tries to read</option>
            <option value="write">tries to write</option>
          </select>
          <select value={folderId} onChange={(e) => setFolderId(e.target.value)}>
            {folders.map((f) => <option key={f.id} value={f.id}>{f.label}</option>)}
          </select>
        </div>
        <p className={allowed ? "ok" : "error"}>
          {allowed ? "Allowed" : "Permission denied"}: {roles.find((r) => r.id === role)!.label} {action === "read" ? "reading" : "writing to"} {folder.label}
        </p>
      </section>

      <section>
        <h2>ACL commands generated from the matrix</h2>
        <pre>
          {folders
            .flatMap((f) => roles.map((r) => `sudo setfacl -m g:${r.id}:${modeFor[f.access[r.id]]} /hospital/${f.id}`))
            .join("\n")}
        </pre>
      </section>

      <section>
        <h2>Time budget</h2>
        {stages.map((s) => (
          <div className="timerow" key={s.id}>
            <span>Stage {s.id}: {s.title}</span>
            <div className="bar"><div style={{ width: `${(s.minutes / maxMinutes) * 100}%` }} /></div>
            <span>{s.minutes} min</span>
          </div>
        ))}
        <p className="muted">Planned total: {total} minutes of 480, leaving {480 - total} minutes spare.</p>
      </section>
    </>
  );
}
