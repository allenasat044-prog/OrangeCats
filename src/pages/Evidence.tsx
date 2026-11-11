import { useState } from "react";
import { stages } from "../data";
import { collectCommand, stageResult, useEvidence } from "../evidence";

export default function Evidence() {
  const { state, reload } = useEvidence(4000);
  const [copied, setCopied] = useState(false);

  const copy = async () => {
    await navigator.clipboard.writeText(collectCommand);
    setCopied(true);
    setTimeout(() => setCopied(false), 1500);
  };

  return (
    <>
      <h1>Evidence</h1>
      <p className="muted">
        Real output captured from the server by <code>collect_evidence.sh</code>. A web page cannot run commands, so run the script in
        Terminal and this page updates by itself.
      </p>

      <section>
        <h2>Architecture</h2>
        <img src="/architecture.svg" alt="Architecture of the hospital IT server" style={{ width: "100%", height: "auto" }} />
      </section>

      <section>
        <h2>Capture the evidence</h2>
        <pre>{collectCommand}</pre>
        <div className="row">
          <button className="btn ghost" onClick={copy}>{copied ? "Copied" : "Copy command"}</button>
          <button className="btn ghost" onClick={reload}>Refresh now</button>
        </div>
      </section>

      {state.status === "loading" && <p className="muted">Loading evidence.</p>}

      {state.status === "missing" && (
        <section>
          <h2>No evidence captured yet</h2>
          <p>Run the command above in Terminal. It takes a few seconds, and the results appear here.</p>
        </section>
      )}

      {state.status === "ready" && (
        <>
          <section>
            <div className="row">
              <span className={`pill ${state.data.summary.failed === 0 ? "pass" : "fail"}`}>
                {state.data.summary.passed} of {state.data.summary.total} checks passed
              </span>
              <span className="muted">
                Captured {new Date(state.data.generatedAt).toLocaleString()} on {state.data.host}, macOS {state.data.macos}, user {state.data.user}
              </span>
            </div>
          </section>

          {stages.map((s) => {
            const checks = state.data.checks.filter((c) => c.stage === s.id);
            if (checks.length === 0) return null;
            const result = stageResult(state.data, s.id);
            return (
              <section key={s.id}>
                <h2>
                  Stage {s.id}: {s.title}{" "}
                  <span className={`pill ${result.passed === result.total ? "pass" : "fail"}`}>
                    {result.passed}/{result.total}
                  </span>
                </h2>
                {checks.map((c) => (
                  <details key={c.id} open>
                    <summary>
                      <span className={`pill ${c.status}`}>{c.status === "pass" ? "PASS" : "FAIL"}</span> {c.title}
                    </summary>
                    <p className="muted">{c.proves}</p>
                    <pre>{`$ ${c.command}\n\n${c.output || "(no output)"}`}</pre>
                    <p className="muted">Exit code {c.exitCode}</p>
                  </details>
                ))}
              </section>
            );
          })}
        </>
      )}
    </>
  );
}
