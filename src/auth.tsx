import { createContext, useContext, useState, type ReactNode } from "react";

type User = { name: string; email: string };
type Stored = User & { hash: string };
type Ctx = {
  user: User | null;
  signUp: (name: string, email: string, password: string) => Promise<string | null>;
  signIn: (email: string, password: string) => Promise<string | null>;
  signOut: () => void;
};

const AuthContext = createContext<Ctx | null>(null);

async function hash(value: string) {
  const buf = await crypto.subtle.digest("SHA-256", new TextEncoder().encode(value));
  return Array.from(new Uint8Array(buf))
    .map((b) => b.toString(16).padStart(2, "0"))
    .join("");
}

function readUsers(): Stored[] {
  try {
    return JSON.parse(localStorage.getItem("hit_users") || "[]");
  } catch {
    return [];
  }
}

export function AuthProvider({ children }: { children: ReactNode }) {
  const [user, setUser] = useState<User | null>(() => {
    const email = localStorage.getItem("hit_session");
    const found = readUsers().find((u) => u.email === email);
    return found ? { name: found.name, email: found.email } : null;
  });

  const signUp: Ctx["signUp"] = async (name, email, password) => {
    const e = email.trim().toLowerCase();
    if (!name.trim() || !e || password.length < 6) {
      return "Enter your name, an email, and a password of at least 6 characters.";
    }
    const users = readUsers();
    if (users.some((u) => u.email === e)) return "An account with this email already exists.";
    users.push({ name: name.trim(), email: e, hash: await hash(password) });
    localStorage.setItem("hit_users", JSON.stringify(users));
    localStorage.setItem("hit_session", e);
    setUser({ name: name.trim(), email: e });
    return null;
  };

  const signIn: Ctx["signIn"] = async (email, password) => {
    const e = email.trim().toLowerCase();
    const found = readUsers().find((u) => u.email === e);
    if (!found || found.hash !== (await hash(password))) return "Incorrect email or password.";
    localStorage.setItem("hit_session", e);
    setUser({ name: found.name, email: found.email });
    return null;
  };

  const signOut = () => {
    localStorage.removeItem("hit_session");
    setUser(null);
  };

  return <AuthContext.Provider value={{ user, signUp, signIn, signOut }}>{children}</AuthContext.Provider>;
}

export function useAuth() {
  const ctx = useContext(AuthContext);
  if (!ctx) throw new Error("useAuth must be used inside AuthProvider");
  return ctx;
}
