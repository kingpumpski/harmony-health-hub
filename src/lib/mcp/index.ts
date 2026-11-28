import { auth, defineMcp } from "@lovable.dev/mcp-js";
import searchPatients from "./tools/search-patients";
import listAppointments from "./tools/list-appointments";

const supabaseUrl = (globalThis as { Deno?: { env: { get(name: string): string | undefined } } }).Deno?.env.get("SUPABASE_URL");
if (!supabaseUrl) throw new Error("SUPABASE_URL is not configured");
const authIssuer = supabaseUrl.replace(/\/+$/, "") + "/auth/v1";

export default defineMcp({
  name: "harmony-health-hub",
  title: "Harmony Health Hub",
  version: "0.1.0",
  instructions: "Read-only tools for Harmony Health Hub. Results respect the signed-in user's role and record access.",
  auth: auth.oauth.issuer({
    issuer: authIssuer,
    acceptedAudiences: "authenticated",
  }),
  tools: [searchPatients, listAppointments],
});
