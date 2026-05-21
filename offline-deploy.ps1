param (
    [Parameter(Mandatory=$true)]
    [ValidateSet("pack", "install")]
    [string]$Action,

    [Parameter(Mandatory=$false)]
    [string]$Registry = "https://registry.npmmirror.com/"
)

$ErrorActionPreference = "Stop"

function Write-Info([string]$Message) {
    Write-Host "[INFO] $Message" -ForegroundColor Cyan
}

function Assert-Success([string]$TaskName) {
    if ($LASTEXITCODE -ne 0) {
        Write-Host "[FATAL ERROR] $TaskName failed with Exit Code $LASTEXITCODE!" -ForegroundColor Red
        exit $LASTEXITCODE
    }
}

if (-not $Registry.EndsWith("/")) { $Registry += "/" }

if ($Action -eq "pack") {
    Write-Info "Phase 1: Starting pack process..."

    if (Test-Path "openclaw\package.json") {
        Write-Info "Found existing openclaw directory, skipping git clone."
    } else {
        if (Test-Path "openclaw") { Remove-Item -Recurse -Force "openclaw" -ErrorAction SilentlyContinue }
        git clone https://github.com/openclaw/openclaw.git
        Assert-Success "Git Clone"
    }
    
    Set-Location "openclaw"

    Write-Info "Writing .npmrc registry settings..."
    "registry=$Registry`n" | Set-Content -Path ".npmrc" -Encoding Ascii

    Write-Info "Parsing package.json and updating pnpm-workspace.yaml..."
    
    $migrateJs = @'
const fs = require("fs");
const pkgPath = "package.json";
const yamlPath = "pnpm-workspace.yaml";

let yaml = fs.existsSync(yamlPath) ? fs.readFileSync(yamlPath, "utf8") : "";

const setKey = (key, val) => {
    const re = new RegExp(`^${key}:.*$`, "m");
    if (re.test(yaml)) {
        yaml = yaml.replace(re, `${key}: ${val}`);
    } else {
        yaml += `\n${key}: ${val}`;
    }
};

setKey("storeDir", "./.pnpm-store-local");
setKey("cacheDir", "./.pnpm-cache-local");
setKey("stateDir", "./.pnpm-state-local");
setKey("minimumReleaseAge", "0");

try {
    const pkg = JSON.parse(fs.readFileSync(pkgPath, "utf8"));
    let overrides = {};
    let has = false;

    if (pkg.overrides) { Object.assign(overrides, pkg.overrides); delete pkg.overrides; has = true; }
    if (pkg.pnpm && pkg.pnpm.overrides) { Object.assign(overrides, pkg.pnpm.overrides); delete pkg.pnpm; has = true; }

    if (has && Object.keys(overrides).length > 0) {
        if (!/^overrides:/m.test(yaml)) {
            yaml += "\noverrides:\n";
        }
        for (const [k, v] of Object.entries(overrides)) {
            const esc = k.replace(/[.*+?^${}()|[\]\\]/g, "\\$&");
            const re = new RegExp(`^\\s*"?(?:${esc})"?:.*$`, "m");
            if (re.test(yaml)) {
                yaml = yaml.replace(re, `  "${k}": "${v}"`);
            } else {
                yaml = yaml.replace(/^overrides:/m, `overrides:\n  "${k}": "${v}"`);
            }
        }
    }
    
    pkg.devDependencies = pkg.devDependencies || {};
    pkg.devDependencies["pnpm"] = "^11.0.0";

    fs.writeFileSync(pkgPath, JSON.stringify(pkg, null, 2), "utf8");
} catch (e) {
    console.error(e.message);
}

fs.writeFileSync(yamlPath, yaml.trim() + "\n", "utf8");
'@
    $migrateJs | node

    Write-Info "Installing dependencies and checking for build intercepts..."
    
    $pnpmOutput = npx --yes pnpm@11 install --no-frozen-lockfile 2>&1
    $exitCode = $LASTEXITCODE
    $pnpmOutput | ForEach-Object { Write-Host $_ }
    
    if ($exitCode -ne 0) {
        $errText = $pnpmOutput -join "`n"
        
        if ($errText -match "\[ERR_PNPM_IGNORED_BUILDS\]\s*Ignored build scripts:\s*([^\n]+)") {
            $rawList = $Matches[1]
            Write-Info "Intercepted unauthorized build scripts. Applying allowBuilds whitelist..."
            
            $env:PNPM_RAW_LIST = $rawList
            $allowJs = @'
const fs = require("fs");
let rawList = process.env.PNPM_RAW_LIST || "";
rawList = rawList.replace(/[\u001b\u009b][[()#;?]*(?:[0-9]{1,4}(?:;[0-9]{0,4})*)?[0-9A-ORZcf-nqry=><]/g, "");

let packages = rawList.split(",").map(s => {
    let p = s.trim();
    let atIndex = p.lastIndexOf("@");
    return atIndex > 0 ? p.substring(0, atIndex) : p;
}).filter(Boolean);

packages = [...new Set(packages)];

if (packages.length > 0) {
    const yamlPath = "pnpm-workspace.yaml";
    let yaml = fs.existsSync(yamlPath) ? fs.readFileSync(yamlPath, "utf8") : "";
    
    if (!/^allowBuilds:/m.test(yaml)) {
        yaml += "\nallowBuilds:\n";
    }
    
    packages.forEach(pkg => {
        const esc = pkg.replace(/[.*+?^${}()|[\]\\]/g, "\\$&");
        const re = new RegExp(`^\\s*"?(?:${esc})"?:.*$`, "m");
        if (!re.test(yaml)) {
            yaml = yaml.replace(/^allowBuilds:/m, `allowBuilds:\n  "${pkg}": true`);
        }
    });
    
    fs.writeFileSync(yamlPath, yaml.trim() + "\n", "utf8");
}
'@
            $allowJs | node
            Assert-Success "Write allowBuilds"
            
            Write-Info "Whitelist updated, retrying build..."
            npx --yes pnpm@11 install --no-frozen-lockfile
            Assert-Success "pnpm install (Retry with allowBuilds)"
        } else {
            Write-Host "[FATAL ERROR] Installation failed with Exit Code $exitCode!" -ForegroundColor Red
            exit $exitCode
        }
    }

    Write-Info "Cleaning up node_modules to optimize zip size..."
    if (Test-Path "node_modules") { Remove-Item -Recurse -Force "node_modules" -ErrorAction SilentlyContinue }

    Set-Location ..
    
    Write-Info "Creating offline ZIP archive..."
    Add-Type -AssemblyName System.IO.Compression.FileSystem
    $SourcePath = (Get-Item "openclaw").FullName
    $ZipPath = Join-Path $PWD "openclaw-offline-windows.zip"
    if (Test-Path $ZipPath) { Remove-Item -Force $ZipPath }
    
    [System.IO.Compression.ZipFile]::CreateFromDirectory($SourcePath, $ZipPath, [System.IO.Compression.CompressionLevel]::Optimal, $true)
    
    Write-Info "Pack phase completed! Output: $ZipPath"

} elseif ($Action -eq "install") {
    Write-Info "Phase 2: Starting offline installation..."

    if (Test-Path "openclaw\package.json") {
        Write-Info "Found existing openclaw directory, skipping ZIP extraction."
    } else {
        if (Test-Path "openclaw-offline-windows.zip") {
            Write-Info "Extracting openclaw-offline-windows.zip..."
            Add-Type -AssemblyName System.IO.Compression.FileSystem
            $ZipPath = (Get-Item "openclaw-offline-windows.zip").FullName
            $DestPath = (Get-Item ".").FullName
            [System.IO.Compression.ZipFile]::ExtractToDirectory($ZipPath, $DestPath)
        } else {
            Write-Host "[FATAL ERROR] Cannot find openclaw directory or offline zip!" -ForegroundColor Red
            exit 1
        }
    }

    Set-Location "openclaw"

    Write-Info "Globally installing offline pnpm from local workspace..."
    npm install -g pnpm --prefix="$env:APPDATA\npm" --cache="./.pnpm-store-local" --prefer-offline --no-audit
    Assert-Success "npm install offline pnpm"

    Write-Info "Executing offline dependency restoration..."
    $env:SHARP_IGNORE_GLOBAL_LIBVIPS = "1"
    
    $pnpmOutput = pnpm install --offline --frozen-lockfile 2>&1
    $exitCode = $LASTEXITCODE
    $pnpmOutput | ForEach-Object { Write-Host $_ }

    if ($exitCode -ne 0) {
        $errText = $pnpmOutput -join "`n"
        
        if ($errText -match "\[ERR_PNPM_IGNORED_BUILDS\]\s*Ignored build scripts:\s*([^\n]+)") {
            $rawList = $Matches[1]
            Write-Info "Intercepted unauthorized build scripts during OFFLINE install. Applying allowBuilds whitelist..."
            
            $env:PNPM_RAW_LIST = $rawList
            $allowJs = @'
const fs = require("fs");
let rawList = process.env.PNPM_RAW_LIST || "";
rawList = rawList.replace(/[\u001b\u009b][[()#;?]*(?:[0-9]{1,4}(?:;[0-9]{0,4})*)?[0-9A-ORZcf-nqry=><]/g, "");

let packages = rawList.split(",").map(s => {
    let p = s.trim();
    let atIndex = p.lastIndexOf("@");
    return atIndex > 0 ? p.substring(0, atIndex) : p;
}).filter(Boolean);

packages = [...new Set(packages)];

if (packages.length > 0) {
    const yamlPath = "pnpm-workspace.yaml";
    let yaml = fs.existsSync(yamlPath) ? fs.readFileSync(yamlPath, "utf8") : "";
    
    if (!/^allowBuilds:/m.test(yaml)) {
        yaml += "\nallowBuilds:\n";
    }
    
    packages.forEach(pkg => {
        const esc = pkg.replace(/[.*+?^${}()|[\]\\]/g, "\\$&");
        const re = new RegExp(`^\\s*"?(?:${esc})"?:.*$`, "m");
        if (!re.test(yaml)) {
            yaml = yaml.replace(/^allowBuilds:/m, `allowBuilds:\n  "${pkg}": true`);
        }
    });
    
    fs.writeFileSync(yamlPath, yaml.trim() + "\n", "utf8");
}
'@
            $allowJs | node
            Assert-Success "Write allowBuilds (Offline)"
            
            Write-Info "Whitelist updated, retrying offline build..."
            pnpm install --offline --frozen-lockfile
            Assert-Success "pnpm install (Offline Retry with allowBuilds)"
        } else {
            Write-Host "[FATAL ERROR] Offline Installation failed
            exit $exitCode
        }
    }

    Write-Info "Building project..."
    pnpm run build
    Assert-Success "pnpm build"
    pnpm run ui:build
    Assert-Success "pnpm ui:build"

    Write-Info "Linking global command..."
    $env:PNPM_CONFIG_OFFLINE = "true"
    
    $linkOutput = pnpm link --global 2>&1
    $linkExitCode = $LASTEXITCODE
    $linkOutput | ForEach-Object { Write-Host $_ }

    if ($linkExitCode -ne 0) {
        Write-Info "pnpm link failed. Falling back to npm link..."
        npm link
        Assert-Success "npm link fallback"
    }

    Write-Host "`n[SUCCESS] Installation complete! Start command:" -ForegroundColor Green
    Write-Host "openclaw onboard --install-daemon" -ForegroundColor Green
}