import { Navigate, Outlet } from "react-router-dom";
import { useAuth } from "../auth";

export default function Protected() {
  const { user } = useAuth();
  return user ? <Outlet /> : <Navigate to="/auth" replace />;
}
