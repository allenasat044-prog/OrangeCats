import { useState } from "react";
import { stages } from "../data";

export default function Runbook() {
  const [copied, setCopied] = useState<string | null>(null);
  const available = stages.filter((s) => s.commands || s.script);

  const copy = async (text: string, key: string) => {
    await navigator.clipboard.writeText(text);
    setCopied(key);
    setTimeout(() => setCopied(null), 1500);
  };

  return (
    <>
      <h1>Runbook</h1>
      <p className="muted">Run these on the Ubuntu server, one block at a time, and confirm each result before moving on.</p>
      {available.map((s) => (
        <section key={s.id}>
          <h2>Stage {s.id}: {s.title}</h2>
          {s.script && (
            <>
              <h3>Script: {s.script.name}</h3>
              <p className="muted">
                Run <code>mkdir -p ~/hospital-setup</code>, then save this as <code>{s.script.path}</code> on the server.
              </p>
              <pre>{s.script.body}</pre>
              <button className="btn ghost" onClick={() => copy(s.script!.body, `s${s.id}-script`)}>
                {copied === `s${s.id}-script` ? "Copied" : "Copy script"}
              </button>
            </>
          )}
          {s.commands && (
            <>
              <h3>Commands</h3>
              <pre>{s.commands.join("\n")}</pre>
              <button className="btn ghost" onClick={() => copy(s.commands!.join("\n"), `s${s.id}`)}>
                {copied === `s${s.id}` ? "Copied" : "Copy commands"}
              </button>
            </>
          )}
          {s.expected && (
            <>
              <h3>Expected result</h3>
              <ul>{s.expected.map((x) => <li key={x}>{x}</li>)}</ul>
            </>
          )}
        </section>
      ))}
    </>
  );
}
