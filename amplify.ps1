#!/usr/bin/env pwsh

<#
.SYNOPSIS
    Amplifier Docker Wrapper Script for PowerShell
.DESCRIPTION
    Runs Amplifier in a Docker container for any target project directory
.PARAMETER ProjectPath
    Path to the target project directory
.PARAMETER DataDir
    Optional path to Amplifier data directory (defaults to ./amplifier-data)
.EXAMPLE
    # First set your Claude OAuth token
    $env:CLAUDE_CODE_OAUTH_TOKEN = "your-oauth-token-here"
    ./amplify.ps1 "C:\MyProject"
.EXAMPLE
    ./amplify.ps1 "C:\MyProject" "C:\amplifier-data"
#>

param(
    [Parameter(Mandatory = $true)]
    [string]$ProjectPath,

    [Parameter(Mandatory = $false)]
    [string]$DataDir
)

# Function to write colored output
function Write-Status {
    param([string]$Message)
    Write-Host "[Amplifier] $Message" -ForegroundColor Blue
}

function Write-Success {
    param([string]$Message)
    Write-Host "[Amplifier] $Message" -ForegroundColor Green
}

function Write-Warning {
    param([string]$Message)
    Write-Host "[Amplifier] $Message" -ForegroundColor Yellow
}

function Write-Error {
    param([string]$Message)
    Write-Host "[Amplifier] $Message" -ForegroundColor Red
}

# Check if Docker is installed and running
try {
    $dockerVersion = docker --version 2>$null
    if (-not $dockerVersion) {
        throw "Docker not found"
    }
}
catch {
    Write-Error "Docker is not installed or not in PATH. Please install Docker Desktop first."
    exit 1
}

try {
    docker info 2>$null | Out-Null
}
catch {
    Write-Error "Docker is not running. Please start Docker Desktop first."
    exit 1
}

# Validate and resolve paths
if (-not (Test-Path $ProjectPath)) {
    Write-Error "Target project directory does not exist: $ProjectPath"
    exit 1
}

$TargetProject = Resolve-Path $ProjectPath
if (-not $DataDir) {
    $DataDir = Join-Path (Get-Location) "amplifier-data"
}

# Create data directory if it doesn't exist
if (-not (Test-Path $DataDir)) {
    New-Item -ItemType Directory -Path $DataDir -Force | Out-Null
}

# Resolve data directory path
$ResolvedDataDir = Resolve-Path $DataDir

Write-Status "Target Project: $TargetProject"
Write-Status "Data Directory: $ResolvedDataDir"

# Build Docker image if it doesn't exist
$ImageName = "amplifier:latest"
Write-Status "Building Amplifier Docker image..."
$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
docker build -t $ImageName $ScriptDir
if ($LASTEXITCODE -ne 0) {
    Write-Error "Failed to build Docker image"
    exit 1
}
Write-Success "Docker image built successfully"

# Prepare environment variables for Claude Code configuration
$EnvArgs = @()

# Add Claude OAuth token if available
if ($env:CLAUDE_CODE_OAUTH_TOKEN) {
    Write-Status "✅ CLAUDE_CODE_OAUTH_TOKEN found - adding to container environment"
    $MaskedToken = "****" + $env:CLAUDE_CODE_OAUTH_TOKEN.Substring([Math]::Max(0, $env:CLAUDE_CODE_OAUTH_TOKEN.Length - 4))
    Write-Status "🔑 Token: $MaskedToken (length: $($env:CLAUDE_CODE_OAUTH_TOKEN.Length))"
    $EnvArgs += @("-e", "CLAUDE_CODE_OAUTH_TOKEN=$env:CLAUDE_CODE_OAUTH_TOKEN")
}
else {
    Write-Error "❌ CLAUDE_CODE_OAUTH_TOKEN environment variable is not set!"
    Write-Error "Please set your Claude OAuth token first:"
    Write-Host "`$env:CLAUDE_CODE_OAUTH_TOKEN = 'your-oauth-token-here'" -ForegroundColor Yellow
    Write-Error "Then run this script again."
    exit 1
}

# Function to convert paths for Docker mounting based on environment
function ConvertTo-DockerPath {
    param([string]$LocalPath)

    # Simple environment detection using built-in PowerShell variables
    if ($env:WSL_DISTRO_NAME) {
        # Running in WSL - convert Windows paths to WSL mount format
        # C:\Users\... becomes /mnt/c/Users/...
        $DockerPath = $LocalPath -replace '\\', '/' -replace '^([A-Za-z]):', { '/mnt/' + $_.Groups[1].Value.ToLower() }
        Write-Status "WSL environment: $LocalPath -> $DockerPath"
        return $DockerPath
    }
    elseif ($IsWindows -or $env:OS -eq "Windows_NT") {
        # Native Windows - Docker Desktop handles Windows paths directly
        Write-Status "Windows environment: Using native path $LocalPath"
        return $LocalPath
    }
    else {
        # Unix/Linux - use paths as-is
        Write-Status "Unix environment: Using path $LocalPath"
        return $LocalPath
    }
}

# Convert paths to Docker-compatible format
$DockerProjectPath = ConvertTo-DockerPath -LocalPath $TargetProject.Path
$DockerDataPath = ConvertTo-DockerPath -LocalPath $ResolvedDataDir.Path

# Simple validation: test if Docker can mount the project directory
Write-Status "Testing Docker mount accessibility..."
try {
    $TestOutput = docker run --rm -v "${DockerProjectPath}:/test" alpine:latest test -d /test 2>&1
    if ($LASTEXITCODE -ne 0) {
        Write-Warning "Docker may not be able to access project directory: $DockerProjectPath"
        Write-Warning "If container fails to start:"
        Write-Warning "  - For Docker Desktop: Enable file sharing for this drive in Settings"
        Write-Warning "  - For WSL: Ensure path is accessible from within WSL"
        Write-Warning "  - Check path exists and has proper permissions"
    }
    else {
        Write-Success "Docker mount test successful"
    }
}
catch {
    Write-Warning "Could not test Docker mount accessibility: $_"
    Write-Warning "Container will attempt to start anyway"
}

# Run the Docker container with Claude Code pre-configured
Write-Status "🚀 Starting Amplifier Docker container..."
Write-Status "📁 Project: $DockerProjectPath → /workspace"
Write-Status "💾 Data: $DockerDataPath → /app/amplifier-data"
Write-Status "🔑 Authentication: Claude Pro OAuth Token (no billing)"

Write-Warning "⚠️  IMPORTANT: When Claude starts, send this first message:"
Write-Host "===========================================" -ForegroundColor Yellow
Write-Host "I'm working in /workspace which contains my project files." -ForegroundColor White
Write-Host "Please cd to /workspace and work there." -ForegroundColor White
Write-Host "Do NOT update any issues or PRs in the Amplifier repo." -ForegroundColor White
Write-Host "===========================================" -ForegroundColor Yellow
Write-Host ""
Write-Status "Press Ctrl+C to exit when done"

$ContainerName = "amplifier-$(Split-Path -Leaf $TargetProject)-$PID"

# Docker run arguments with complete environment configuration
# FIX: Use array concatenation (+) to properly flatten $EnvArgs instead of embedding as nested array
$DockerArgs = @("run", "-it", "--rm") +
$EnvArgs +
@(
    # Essential environment variables for Amplifier operation
    "-e", "TARGET_DIR=/workspace"                    # Target project directory in container
    "-e", "AMPLIFIER_DATA_DIR=/app/amplifier-data"   # Amplifier data persistence
    # Volume mounts: Host → Container
    "-v", "$($DockerProjectPath):/workspace"         # User project files
    "-v", "$($DockerDataPath):/app/amplifier-data"   # Amplifier data directory
    # Container identification
    "--name", $ContainerName
    $ImageName
)

Write-Status "Executing: docker run with $(($DockerArgs | Where-Object { $_ -eq '-e' }).Count) environment variables"

try {
    & docker @DockerArgs
    Write-Success "✅ Amplifier session completed successfully"
}
catch {
    Write-Error "❌ Failed to run Amplifier container: $_"
    Write-Error "Check that Docker is running and the image exists"
    exit 1
}