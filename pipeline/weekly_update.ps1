# Weekly card update for Gridiron Dynasty.
#
# Downloads the latest nflverse data, builds new cards (Week Standouts for each newly finished
# week, Base cards for newly qualifying players) and, when anything is new, commits ONLY
# docs/cards.json and pushes it. GitHub Pages then serves it, and live game servers load it
# within 30 minutes. No republish needed.
#
# Runs on this PC, so the private real-to-fictional mapping (private/) never leaves it.
# Scheduled by pipeline\install_weekly_task.ps1. Log: private\logs\weekly_update.log
#
# Manual run:  powershell -ExecutionPolicy Bypass -File pipeline\weekly_update.ps1

# "Continue": git and python write normal progress to stderr; failures are caught by exit codes
$ErrorActionPreference = "Continue"
$root = Split-Path -Parent $PSScriptRoot
Set-Location $root

$logDir = Join-Path $root "private\logs"
New-Item -ItemType Directory -Force $logDir | Out-Null
$log = Join-Path $logDir "weekly_update.log"

function Log($msg) {
	$line = "{0}  {1}" -f (Get-Date -Format "yyyy-MM-dd HH:mm:ss"), $msg
	Add-Content -Path $log -Value $line -Encoding utf8
	Write-Output $line
}

try {
	Log "---- weekly update starting"

	# Only publish from a clean main branch that's up to date with GitHub
	$branch = (git rev-parse --abbrev-ref HEAD).Trim()
	if ($branch -ne "main") {
		Log "skipped: on branch '$branch', not main"
		exit 0
	}
	$cardsDirty = git status --porcelain -- docs/cards.json
	if ($cardsDirty) {
		Log "skipped: docs/cards.json has uncommitted changes"
		exit 0
	}
	git pull --ff-only --quiet 2>&1 | ForEach-Object { Log "git: $_" }
	if ($LASTEXITCODE -ne 0) {
		Log "skipped: git pull failed"
		exit 1
	}

	$python = Join-Path $root ".venv\Scripts\python.exe"
	$output = & $python -I -X utf8 (Join-Path $root "pipeline\build.py") 2>&1
	$code = $LASTEXITCODE
	$output | ForEach-Object { Log "build: $_" }
	if ($code -ne 0) {
		Log "FAILED: build exited with code $code (nothing published)"
		exit 1
	}

	$result = $output | Where-Object { "$_" -like "RESULT *" } | Select-Object -Last 1
	if (-not $result -or "$result" -like "RESULT unchanged*") {
		Log "nothing new this time"
		exit 0
	}

	if ("$result" -match "week=(\d+) version=(\d+) added=(\d+)") {
		$msg = "Week $($Matches[1]) card update: $($Matches[3]) new cards (data v$($Matches[2]))"
	} else {
		$msg = "Weekly card update"
	}
	git commit --quiet -m $msg -m "Automated by pipeline/weekly_update.ps1" -- docs/cards.json 2>&1 | ForEach-Object { Log "git: $_" }
	if ($LASTEXITCODE -ne 0) {
		Log "FAILED: git commit"
		exit 1
	}
	git push --quiet origin main 2>&1 | ForEach-Object { Log "git: $_" }
	if ($LASTEXITCODE -ne 0) {
		Log "FAILED: git push (the commit is saved locally; it will go out with the next push)"
		exit 1
	}
	Log "published: $msg"
	exit 0
} catch {
	Log "FAILED: $_"
	exit 1
}
