import { defineConfig } from "vite";
import react from "@vitejs/plugin-react-swc";
import path from "path";
import { brotliCompressSync, gzipSync } from "node:zlib";
import { writeFileSync } from "node:fs";
import { componentTagger } from "lovable-tagger";

function compressedAssets() {
  return {
    name: "compressed-assets",
    apply: "build" as const,
    writeBundle(_options: unknown, bundle: Record<string, { type: string; source?: string | Uint8Array; code?: string }>) {
      for (const [fileName, output] of Object.entries(bundle)) {
        if (output.type !== "asset" && output.type !== "chunk") continue;
        const content = output.type === "asset"
          ? output.source
          : output.code;
        if (content === undefined || fileName.endsWith(".map")) continue;
        const buffer = Buffer.isBuffer(content)
          ? content
          : Buffer.from(typeof content === "string" ? content : content);
        writeFileSync(`dist/${fileName}.br`, brotliCompressSync(buffer));
        writeFileSync(`dist/${fileName}.gz`, gzipSync(buffer, { level: 9 }));
      }
    },
  };
}

// https://vitejs.dev/config/
export default defineConfig(({ mode }) => ({
  server: {
    host: "::",
    port: 8080,
  },
  build: {
    // The service worker uses the Vite manifest to precache production
    // JavaScript/CSS chunks after the first successful online installation.
    manifest: true,
    chunkSizeWarningLimit: 350,
    rollupOptions: {
      output: {
        manualChunks(id) {
          if (!id.includes("node_modules")) return;
          if (id.includes("xlsx")) return "vendor-xlsx";
          if (id.includes("recharts") || id.includes("d3-")) return "vendor-charts";
          if (id.includes("react") || id.includes("react-dom") || id.includes("react-router") || id.includes("@tanstack")) return "vendor-react";
          if (id.includes("@radix-ui") || id.includes("lucide-react") || id.includes("next-themes")) return "vendor-ui";
          return "vendor";
        },
      },
    },
  },
  plugins: [react(), mode === "production" && compressedAssets(), mode === "development" && componentTagger()].filter(Boolean),
  resolve: {
    alias: {
      "@": path.resolve(__dirname, "./src"),
    },
  },
}));
