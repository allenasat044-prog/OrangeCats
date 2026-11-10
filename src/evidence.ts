import { useCallback, useEffect, useState } from "react";

export type Check = {
  id: string;
  stage: number;
  title: string;
  proves: string;
  command: string;
  output: string;
  exitCode: number;
  status: "pass" | "fail";
};

export type Evidence = {
  generatedAt: string;
  host: string;
  macos: string;
  user: string;
  summary: { total: number; passed: number; failed: number };
  checks: Check[];
};

export type EvidenceState =
  | { status: "loading" }
  | { status: "missing" }
  | { status: "ready"; data: Evidence };

async function load(): Promise<EvidenceState> {
  try {
    const res = await fetch(`/evidence.json?t=${Date.now()}`, { cache: "no-store" });
    if (!res.ok) return { status: "missing" };
    const data = (await res.json()) as Evidence;
    if (!Array.isArray(data.checks)) return { status: "missing" };
    return { status: "ready", data };
  } catch {
    return { status: "missing" };
  }
}

export function useEvidence(pollMs = 0) {
  const [state, setState] = useState<EvidenceState>({ status: "loading" });

  const reload = useCallback(async () => {
    setState(await load());
  }, []);

  useEffect(() => {
    let alive = true;
    const run = async () => {
      const next = await load();
      if (alive) setState(next);
    };
    run();
    if (pollMs > 0) {
      const timer = setInterval(run, pollMs);
      return () => {
        alive = false;
        clearInterval(timer);
      };
    }
    return () => {
      alive = false;
    };
  }, [pollMs]);

  return { state, reload };
}

export function stageResult(data: Evidence, stage: number) {
  const checks = data.checks.filter((c) => c.stage === stage);
  const passed = checks.filter((c) => c.status === "pass").length;
  return { total: checks.length, passed };
}

export const collectCommand = "sudo bash ~/Desktop/hospital-it/src/scripts/mac/collect_evidence.sh";
