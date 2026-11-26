import { defineTool, ToolError } from "@lovable.dev/mcp-js";
import { z } from "zod";
import { supabaseForUser } from "../supabase";

export default defineTool({
  name: "search_patients",
  title: "Search patients",
  description: "Find patients you are allowed to see by name, patient code or phone.",
  inputSchema: {
    query: z.string().min(2).max(80).describe("Part of a name, patient code or phone number."),
    limit: z.number().int().min(1).max(25).optional().describe("Maximum results (default 10)."),
  },
  annotations: { readOnlyHint: true, idempotentHint: true, openWorldHint: false },
  handler: async ({ query, limit }, ctx) => {
    const q = query.replace(/[%,()]/g, " ").trim();
    const { data, error } = await supabaseForUser(ctx)
      .from("patients")
      .select("id, patient_code, first_name, last_name, gender, date_of_birth, phone, status")
      .or(`first_name.ilike.%${q}%,last_name.ilike.%${q}%,patient_code.ilike.%${q}%,phone.ilike.%${q}%`)
      .order("last_name")
      .limit(limit ?? 10);
    if (error) throw new ToolError("Could not search patients.");
    const patients = (data ?? []).map((p) => ({
      id: p.id, patient_code: p.patient_code, name: `${p.first_name} ${p.last_name}`,
      gender: p.gender, date_of_birth: p.date_of_birth, phone: p.phone, status: p.status,
    }));
    const text = patients.length ? patients.map((p) => `${p.patient_code ?? p.id}: ${p.name}`).join("\n") : "No matching patients.";
    return { content: [{ type: "text", text }], structuredContent: { patients } };
  },
});
