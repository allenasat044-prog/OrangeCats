import { useState } from "react";
import { stages } from "../data";

export default function Runbook() {
  const [copied, setCopied] = useState<string | null>(null);

  const copy = async (text: string, key: string) => {
    await navigator.clipboard.writeText(text);
    setCopied(key);
    setTimeout(() => setCopied(null), 1500);
  };

  return (
    <>
      <h1>Runbook</h1>
      <p className="muted">
        macOS commands for each stage, in the order they were run. Run one block at a time and check the expected result before moving on.
        Linux and Windows equivalents are in the README.
      </p>
      {stages.map((s) => (
        <section key={s.id}>
          <h2>Stage {s.id}: {s.title}</h2>
          {s.scripts && (
            <>
              <h3>Scripts</h3>
              {s.scripts.map((sc) => (
                <details key={sc.name}>
                  <summary>{sc.name} <span className="muted">({sc.path})</span></summary>
                  <pre>{sc.body}</pre>
                  <button className="btn ghost" onClick={() => copy(sc.body, `s${s.id}-${sc.name}`)}>
                    {copied === `s${s.id}-${sc.name}` ? "Copied" : "Copy script"}
                  </button>
                </details>
              ))}
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
