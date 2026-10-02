import { defineConfig } from "vite";
import react from "@vitejs/plugin-react-swc";
import path from "path";
import { brotliCompressSync, gzipSync } from "node:zlib";
import { readFileSync, writeFileSync } from "node:fs";
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

function githubPagesSpaFallback(basePath: string) {
  const base = basePath.replace(/\\/$/, "");
  return {
    name: "github-pages-spa-fallback",
    apply: "build" as const,
    closeBundle() {
      // GitHub Pages returns 404.html for client-side routes. Redirect through
      // the project root and restore the original path before React Router loads.
      const indexPath = "dist/index.html";
      const restoreRoute = `<script>(function(){var params=new URLSearchParams(window.location.search);var route=params.get("__hms_spa_redirect");if(!route)return;var safeRoute=route.charAt(0)==="/"&&!route.startsWith("//")?route:"/";window.history.replaceState(null,"",${JSON.stringify(base)}+safeRoute);})();</script>`;
      const indexHtml = readFileSync(indexPath, "utf8");
      if (!indexHtml.includes("__hms_spa_redirect")) {
        writeFileSync(indexPath, indexHtml.replace("</head>", `${restoreRoute}\\n</head>`));
      }
      const fallbackHtml = `<!doctype html>
<html lang="en"><head><meta charset="UTF-8"><meta name="robots" content="noindex"><title>Opening Harmony Health Hub</title></head>
<body><p>Opening Harmony Health Hub…</p><script>(function(){var base=${JSON.stringify(base)};var path=window.location.pathname;var route=path.indexOf(base)===0?path.slice(base.length):path;if(!route.startsWith("/"))route="/"+route;var target=route+window.location.search+window.location.hash;window.location.replace(base+"/?__hms_spa_redirect="+encodeURIComponent(target));})();</script></body></html>`;
      writeFileSync("dist/404.html", fallbackHtml);
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
  plugins: [react(), mode === "production" && compressedAssets(), mode === "production" && githubPagesSpaFallback("/harmony-health-hub/"), mode === "development" && componentTagger()].filter(Boolean),
  resolve: {
    alias: {
      "@": path.resolve(__dirname, "./src"),
    },
  },
}));
