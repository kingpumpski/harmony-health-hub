import { auth, defineMcp } from "@lovable.dev/mcp-js";
import searchPatients from "./tools/search-patients";
import listAppointments from "./tools/list-appointments";

const projectRef = (globalThis as { Deno?: { env: { get(name: string): string | undefined } } }).Deno?.env.get("SUPABASE_PROJECT_REF");
if (!projectRef) throw new Error("SUPABASE_PROJECT_REF is not configured");

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
