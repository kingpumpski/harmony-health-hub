import { auth, defineMcp } from "@lovable.dev/mcp-js";
import searchPatients from "./tools/search-patients";
import listAppointments from "./tools/list-appointments";

const projectRef = import.meta.env["VITE_SUPABASE_PROJECT_ID"] ?? "project-ref-unset";

export default defineMcp({
  name: "harmony-health-hub",
  title: "Harmony Health Hub",
  version: "0.1.0",
  instructions: "Read-only tools for Harmony Health Hub. Results respect the signed-in user's role and record access.",
  auth: auth.oauth.issuer({
    issuer: `https://${projectRef}.supabase.co/auth/v1`,
    acceptedAudiences: "authenticated",
  }),
  tools: [searchPatients, listAppointments],
});
