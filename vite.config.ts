import { defineConfig } from "vite";
import react from "@vitejs/plugin-react-swc";
import path from "path";
import { brotliCompressSync, gzipSync } from "node:zlib";
import { copyFileSync, writeFileSync } from "node:fs";
import { componentTagger } from "lovable-tagger";

function compressedAssets() {
  return {
    name: "compressed-assets",
    apply: "build" as const,
    writeBundle(_options: unknown, bundle: Record<string, { type: string; source?: string | Uint8Array; code?: string }>) {
      for (const [fileName, output] of Object.entries(bundle)) {
        if (output.type !== "asset" && output.type !== "chunk") continue;
        const content = output.type === "asset" ? output.source : output.code;
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

function githubPagesSpaFallback() {
  return {
    name: "github-pages-spa-fallback",
    apply: "build" as const,
    closeBundle() {
      // GitHub Pages does not rewrite deep links to index.html. Serving the
      // built app as 404.html lets BrowserRouter resolve /patients/:patientId
      // and other client-side routes after a direct visit or browser refresh.
      copyFileSync("dist/index.html", "dist/404.html");
    },
  };
}

// GitHub Pages serves this project from /harmony-health-hub/ rather than /
// so production asset URLs must use the project-site base path.
export default defineConfig(({ mode }) => ({
  base: mode === "production" ? "/harmony-health-hub/" : "/",
  server: {
    host: "::",
    port: 8080,
  },
  build: {
    manifest: true,
    chunkSizeWarningLimit: 350,
  },
  plugins: [react(), mode === "production" && compressedAssets(), mode === "production" && githubPagesSpaFallback(), mode === "development" && componentTagger()].filter(Boolean),
  resolve: {
    alias: {
      "@": path.resolve(__dirname, "./src"),
    },
  },
}));
