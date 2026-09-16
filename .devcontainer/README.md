# Harmony Health Hub development container

This repository is configured for GitHub Codespaces with Node.js 20 and npm.

## Normal workflow

Open the repository in a Codespace. The container automatically runs `npm ci` after creation.

Then use the integrated terminal normally:

```bash
node --version
npm --version
git status
npm run typecheck
npm run lint
npm run build
npm test
```

For local development:

```bash
npm run dev -- --host 0.0.0.0
```

The Vite development server uses port 8080 when the project's Vite configuration specifies that port.

This setup is intended to avoid requiring a manual `git clone` or a locally installed Node.js toolchain. The repository itself remains the source of truth.
