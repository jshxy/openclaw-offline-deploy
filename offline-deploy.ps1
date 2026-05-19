param (
    [Parameter(Mandatory=$true)]
    [ValidateSet("pack", "install")]
    [string]$Action,

    [Parameter(Mandatory=$false)]
    [int]$Concurrency = 3,

    [Parameter(Mandatory=$false)]
    [int]$Retries = 8,

    [Parameter(Mandatory=$false)]
    [int]$RetryTimeout = 2000,

    [Parameter(Mandatory=$false)]
    [string]$Registry = "default",

    [Parameter(Mandatory=$false)]
    [string]$TargetOS = "current,win32,linux,darwin",

    [Parameter(Mandatory=$false)]
    [string]$TargetCPU = "current,x64,arm64"
)

$ErrorActionPreference = "Stop"
$FallbackPnpmVersion = "11.1.0"
$utf8NoBom = New-Object System.Text.UTF8Encoding $false

function Write-Info([string]$Message) {
    Write-Host "[INFO] $Message" -ForegroundColor Cyan
}

function Assert-Success([string]$TaskName) {
    if ($LASTEXITCODE -ne 0) {
        Write-Host "[FATAL ERROR] $TaskName failed with Exit Code $LASTEXITCODE!" -ForegroundColor Red
        exit $LASTEXITCODE
    }
}

$ActualRegistry = "https://registry.npmmirror.com/"
if ($Registry -eq "official") {
    $ActualRegistry = "https://registry.npmjs.org/"
} elseif ($Registry -match "^https?://") {
    $ActualRegistry = $Registry
}

if (-not $ActualRegistry.EndsWith("/")) {
    $ActualRegistry += "/"
}

$TargetOS = $TargetOS -replace '\s+', ''
$TargetCPU = $TargetCPU -replace '\s+', ''

if ($Action -eq "pack") {
    Write-Info "Phase 1: Starting pack process..."
    
    Write-Info "Fetching latest pnpm version from registry ($ActualRegistry)..."
    try {
        $ApiUrl = "${ActualRegistry}pnpm/latest"
        $PnpmVersion = (Invoke-RestMethod -Uri $ApiUrl -UseBasicParsing -ErrorAction Stop).version
        Write-Info "Latest pnpm version resolved to: $PnpmVersion"
    } catch {
        $PnpmVersion = $FallbackPnpmVersion
        Write-Host "[WARNING] Failed to fetch latest version, using fallback: $PnpmVersion" -ForegroundColor Yellow
    }

    if (Get-Command git -ErrorAction SilentlyContinue) {
        if (Test-Path "openclaw") { Remove-Item -Recurse -Force "openclaw" }
        git clone https://github.com/openclaw/openclaw.git
        Assert-Success "Git Clone"
    } else {
        if (-not (Test-Path "openclaw")) {
            Write-Host "[ERROR] Git not found and 'openclaw' directory missing!" -ForegroundColor Red
            exit 1
        }
    }
    
    if (Test-Path "openclaw-offline-windows.zip") { Remove-Item -Force "openclaw-offline-windows.zip" }
    Set-Location "openclaw"

    Write-Info "Packing offline pnpm using native npm..."
    npm pack pnpm@$PnpmVersion
    Assert-Success "npm pack pnpm"
    
    if (Test-Path "pnpm-$PnpmVersion.tgz") {
        Move-Item -Path "pnpm-$PnpmVersion.tgz" -Destination "pnpm-offline.tgz" -Force
    } else {
        Write-Host "[ERROR] npm pack output file not found!" -ForegroundColor Red
        exit 1
    }

    Write-Info "Injecting v11-compatible configuration natively (OS: $TargetOS, CPU: $TargetCPU)..."
    $SupportedArch = "os=$TargetOS;cpu=$TargetCPU"
    $nodeScript = "const fs=require('fs');let p=JSON.parse(fs.readFileSync('package.json','utf8'));delete p.packageManager;if(p.pnpm){delete p.pnpm.supportedArchitectures;delete p.pnpm.onlyBuiltDependencies;}fs.writeFileSync('package.json',JSON.stringify(p,null,2));fs.writeFileSync('.npmrc',['store-dir=./.pnpm-store-local','registry=$ActualRegistry','network-concurrency=$Concurrency','fetch-retries=$Retries','fetch-retry-mintimeout=$RetryTimeout','only-built-dependencies=@google/genai,@matrix-org/matrix-sdk-crypto-nodejs,@tloncorp/tlon-skill,baileys,esbuild,koffi,protobufjs,sharp,tree-sitter-bash,@discordjs/opus,@tloncorp/api','supported-architectures=$SupportedArch'].join(String.fromCharCode(10)));"
    node -e $nodeScript

    Write-Info "Downloading dependencies via configured registry..."
    $env:SHARP_IGNORE_GLOBAL_LIBVIPS = "1"
    npx pnpm@$PnpmVersion install
    Assert-Success "npx pnpm install (Pack Phase)"

    Write-Info "Creating zip archive using optimized .NET compression..."
    Remove-Item -Recurse -Force "node_modules" -ErrorAction SilentlyContinue
    Set-Location ..
    
    Add-Type -AssemblyName System.IO.Compression.FileSystem
    $SourcePath = (Get-Item "openclaw").FullName
    $ZipPath = Join-Path $PWD "openclaw-offline-windows.zip"
    [System.IO.Compression.ZipFile]::CreateFromDirectory($SourcePath, $ZipPath)
    
    Write-Info "Pack completed! Zip file is ready."

} elseif ($Action -eq "install") {
    Write-Info "Phase 2: Starting offline installation..."

    $SkipExtraction = $false
    if (Test-Path "openclaw\package.json") {
        Write-Info "Detected manually extracted 'openclaw' directory. Skipping zip extraction to save time."
        Set-Location "openclaw"
        $SkipExtraction = $true
    } elseif (Test-Path "package.json") {
        Write-Info "Already inside a valid openclaw directory. Proceeding..."
        $SkipExtraction = $true
    }

    if (-not $SkipExtraction) {
        if (Test-Path "openclaw-offline-windows.zip") {
            Write-Info "Extracting zip file"
            if (Test-Path "openclaw") { Remove-Item -Recurse -Force "openclaw" }
            
            Add-Type -AssemblyName System.IO.Compression.FileSystem
            $ZipPath = (Get-Item "openclaw-offline-windows.zip").FullName
            $DestPath = (Get-Item ".").FullName
            [System.IO.Compression.ZipFile]::ExtractToDirectory($ZipPath, $DestPath)
            
            Set-Location "openclaw"
        } else {
            Write-Host "[ERROR] Cannot find 'openclaw-offline-windows.zip' or a valid 'openclaw' directory!" -ForegroundColor Red
            exit 1
        }
    }

    if (Test-Path "pnpm-offline.tgz") {
        Write-Info "Installing offline pnpm globally using native npm..."
        npm install -g ./pnpm-offline.tgz
        Assert-Success "npm install local pnpm"
    } else {
        Write-Host "[ERROR] 'pnpm-offline.tgz' not found!" -ForegroundColor Red
        exit 1
    }

    Write-Info "Installing dependencies offline..."
    $env:SHARP_IGNORE_GLOBAL_LIBVIPS = "1"
    pnpm install --offline
    Assert-Success "pnpm install --offline (Install Phase)"

    Write-Info "Building project..."
    pnpm build
    Assert-Success "pnpm build"
    pnpm ui:build
    Assert-Success "pnpm ui:build"

    Write-Info "Linking global command..."
    pnpm link --global
    Assert-Success "pnpm link"

    Write-Info "Install completed! Start command:"
    Write-Host "openclaw onboard --install-daemon" -ForegroundColor Green
}