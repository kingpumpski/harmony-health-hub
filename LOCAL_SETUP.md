# Local development setup

## Windows + VS Code

Always open the cloned repository root:

`C:\path\to\harmony-health-hub`

Do not open only a parent folder, `src`, or another nested directory. VS Code Source Control detects the repository from the folder containing `.git` (or the worktree metadata created by Git).

### First setup after cloning

From the repository root, run:

```powershell
npm ci
npm run verify:local
npm run dev
```

`npm ci` is intentional: it installs the exact dependency tree recorded by `package-lock.json` and creates `node_modules/.bin/vite`. Running `npm run dev` before dependencies are installed causes `sh: vite: command not found`.

If PowerShell is being troublesome, double-click or run:

```text
scripts\\bootstrap-local.cmd
```

The bootstrap verifies that the current directory belongs to the Git repository and then installs the locked dependencies.

### Git verification

```powershell
git rev-parse --show-toplevel
git status
```

The first command must print the `harmony-health-hub` repository root. `git status` should then report the current branch and working-tree state.

### If VS Code says "The folder currently opened doesn't have a Git repository"

1. Close the incorrectly opened folder/workspace.
2. In VS Code choose **File → Open Folder**.
3. Select the actual cloned `harmony-health-hub` directory.
4. Open a new integrated terminal.
5. Run `git rev-parse --show-toplevel`.
6. Run `git status`.

If Git itself is not found, install Git for Windows and restart VS Code. The repository cannot make a missing local Git executable appear; Git is installed on the computer, while `.git` is metadata created by the clone.

### Keeping local and GitHub versions synchronized

Before starting work:

```powershell
git pull --ff-only
npm ci
```

After work:

```powershell
git status
git add .
git commit -m "describe the change"
git push origin main
```

If working on a feature branch, replace `main` with that branch. Do not use force-push unless the project workflow explicitly requires it.

### Important

Do not delete `.git`, copy only the visible project files into a new folder, or open a parent directory and assume VS Code will treat the child clone as the active repository. A proper Git clone already contains the Git metadata required for Source Control.
