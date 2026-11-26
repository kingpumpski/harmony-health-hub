import { defineTool, ToolError } from "@lovable.dev/mcp-js";
import { z } from "zod";
import { supabaseForUser } from "../supabase";

export default defineTool({
  name: "list_upcoming_appointments",
  title: "List upcoming appointments",
  description: "List upcoming appointments you are allowed to see, soonest first.",
  inputSchema: {
    days: z.number().int().min(1).max(60).optional().describe("How many days ahead to look (default 7)."),
  },
  annotations: { readOnlyHint: true, idempotentHint: true, openWorldHint: false },
  handler: async ({ days }, ctx) => {
    const now = new Date();
    const until = new Date(now.getTime() + (days ?? 7) * 86400000);
    const { data, error } = await supabaseForUser(ctx)
      .from("appointments")
      .select("id, patient_id, department, reason, scheduled_at, status, duration_minutes")
      .gte("scheduled_at", now.toISOString())
      .lte("scheduled_at", until.toISOString())
      .order("scheduled_at")
      .limit(50);
    if (error) throw new ToolError("Could not load appointments.");
    const appointments = (data ?? []).map((a) => ({
      id: a.id, patient_id: a.patient_id, department: a.department, reason: a.reason,
      scheduled_at: a.scheduled_at, status: a.status, duration_minutes: a.duration_minutes,
    }));
    const text = appointments.length
      ? appointments.map((a) => `${a.scheduled_at} — ${a.department ?? "General"} (${a.status})`).join("\n")
      : "No upcoming appointments.";
    return { content: [{ type: "text", text }], structuredContent: { appointments } };
  },
});
