import { defineConfig } from "vite";
import react from "@vitejs/plugin-react-swc";
import path from "path";
import { componentTagger } from "lovable-tagger";

// https://vitejs.dev/config/
export default defineConfig(({ mode }) => ({
  server: {
    host: "::",
    port: 8080,
  },
  plugins: [react(), mode === "development" && componentTagger()].filter(Boolean),
  resolve: {
    alias: {
      "@": path.resolve(__dirname, "./src"),
    },
  },
  build: {
    rollupOptions: {
      output: {
        manualChunks(id) {
          if (!id.includes("node_modules")) return;

          if (id.includes("xlsx")) return "vendor-spreadsheets";
          if (id.includes("recharts") || id.includes("d3-")) return "vendor-charts";
          if (
            id.includes("react") ||
            id.includes("react-dom") ||
            id.includes("react-router") ||
            id.includes("@tanstack")
          ) {
            return "vendor-react";
          }
          if (id.includes("@radix-ui") || id.includes("lucide-react") || id.includes("next-themes")) {
            return "vendor-ui";
          }
          if (id.includes("@supabase")) return "vendor-supabase";
        },
      },
    },
  },
}));
