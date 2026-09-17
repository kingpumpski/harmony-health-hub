$ErrorActionPreference = 'Stop'

$repoRoot = Split-Path -Parent $PSScriptRoot
Set-Location $repoRoot

Write-Host "Repository: $repoRoot"

if (-not (Get-Command git -ErrorAction SilentlyContinue)) {
  throw "Git is not installed or is not on PATH. Install Git for Windows, restart VS Code, and run this script again."
}

gitRoot = (git rev-parse --show-toplevel).Trim()
if ((Resolve-Path $gitRoot).Path -ne (Resolve-Path $repoRoot).Path) {
  throw "This folder is not the Git repository root. Expected: $repoRoot; Git root: $gitRoot"
}

if (-not (Test-Path (Join-Path $repoRoot 'package.json'))) {
  throw "package.json is missing. Open the cloned repository root in VS Code."
}

Write-Host "Git repository verified."
Write-Host "Installing exact locked dependencies with npm ci..."
npm ci

Write-Host "Checking local prerequisites..."
npm run verify:local

Write-Host "Local environment is ready."
Write-Host "Start development with: npm run dev"
