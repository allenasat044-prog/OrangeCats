import { Navigate, Route, Routes } from "react-router-dom";
import Layout from "./components/Layout";
import Protected from "./components/Protected";
import Landing from "./pages/Landing";
import Auth from "./pages/Auth";
import Dashboard from "./pages/Dashboard";
import Analysis from "./pages/Analysis";
import Runbook from "./pages/Runbook";
import FAQ from "./pages/FAQ";

export default function App() {
  return (
    <Routes>
      <Route path="/" element={<Landing />} />
      <Route element={<Layout />}>
        <Route path="/auth" element={<Auth />} />
        <Route path="/faq" element={<FAQ />} />
        <Route element={<Protected />}>
          <Route path="/dashboard" element={<Dashboard />} />
          <Route path="/analysis" element={<Analysis />} />
          <Route path="/runbook" element={<Runbook />} />
        </Route>
        <Route path="*" element={<Navigate to="/" replace />} />
      </Route>
    </Routes>
  );
}
