@echo off
setlocal
cd /d "%~dp0.."

git rev-parse --show-toplevel >nul 2>&1
if errorlevel 1 (
  echo Git is not available or this folder is not a Git working tree.
  echo Open the cloned repository root in VS Code and ensure Git for Windows is installed.
  exit /b 1
)

if not exist package.json (
  echo package.json is missing. Open the cloned repository root.
  exit /b 1
)

echo Git repository verified.
echo Installing exact locked dependencies with npm ci...
npm ci
if errorlevel 1 exit /b %errorlevel%

npm run verify:local
if errorlevel 1 exit /b %errorlevel%

echo Local environment is ready.
echo Start development with: npm run dev
endlocal
