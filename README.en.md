<div align="right">
  <a href="./README.md">简体中文</a> | <strong>English</strong>
</div>

# OpenClaw Universal Offline Deployment Script for Windows

[![License: CC BY-NC-SA 4.0](https://img.shields.io/badge/License-CC%20BY--NC--SA%204.0-lightgrey.svg)](https://creativecommons.org/licenses/by-nc-sa/4.0/)

A one-click offline packaging and deployment tool for OpenClaw.

**Pack on online machines and deploy on offline machines.** Solves cross-platform architecture deployment issues.

Utilizes the Taobao mirror for more stable connections in some certain etwork environments. You can custumize this feature by yourself.

---


## ✨ Core Features

* **Cross-Platform Offline Deployment**: Automatically configures full deployment, ensuring all binary dependencies for Mac/Linux/Windows and x64/ARM architectures are fetched completely in one go.
* **Smart Resume & Concurrency Control**: Built-in network exception blocking and parameterized retry mechanisms, optimized for network environments with concurrency limits.

---

## ⚠️ Anti-Scam Warning

This script is open-sourced under the **CC BY-NC-SA 4.0 (Attribution-NonCommercial-ShareAlike)** license.

1. **Absolutely Free**: This project is for technical learning and communication purposes only and is **forever free**.
2. **Commercial Use & Resale Prohibited**: It is strictly forbidden for any individual or organization to use this script for paid deployment, resale, or as part of a commercial service for profit.
3. **Plagiarism & Closed-Source Prohibited**: Anyone who modifies, optimizes, or derives a new script based on this script **MUST** retain this declaration and release it for free under the same open-source license. Closed-source copyright evasion is strictly prohibited.

🚨 **Fraud Alert**: If you paid for this script or a deployment service using it, **you have been scammed**. Please request a refund immediately and report the seller!

---

## 🛠️ Prerequisites

Before starting, please ensure your machines meet the following requirements:

### [Online Machine] (For building the offline package)

* OS: Windows 10 / 11
* Installed [Node.js](https://nodejs.org/) (v24 or v22.19+ recommended)
* (Optional) Installed [Git](https://git-scm.com/install/windows/)

### [Offline Machine] (Target deployment machine)

* OS: Windows 10 / 11
* Installed [Node.js](https://nodejs.org/) (Version must match the online machine)

> **Note**: Windows may block `.ps1` scripts upon first execution due to system security policies. Please run PowerShell as Administrator and execute the following command to allow it:
> ```powershell
> Set-ExecutionPolicy RemoteSigned -Scope CurrentUser
> ```

---

## 🚀 Usage Guide

### Phase 1: Build the Offline Package on the [Online Machine]

1. Download the `openclaw-deploy.ps1` script from this repository and place it in any empty directory.
2. Open PowerShell in that directory and run the following command to start packaging:
   ```powershell
   .\openclaw-deploy.ps1 -Action pack
   ```

3. The script will automatically fetch the latest source code, configure the mirror, download all cross-platform dependencies, and pack them.
> If [Git](https://git-scm.com/install/windows/) is not installed, please download the official [Openclaw](https://github.com/openclaw/openclaw) repository code manually in advance, extract it into the same directory, and rename it to "openclaw". Pay attention to directory levels (avoid nesting).


4. Wait for the execution to finish (a green `Pack completed!` prompt will appear). An **`openclaw-offline-windows.zip`** archive will be generated in the current directory.

### Phase 2: Extract and Install on the [Offline Machine]

1. Copy both the generated `openclaw-offline-windows.zip` and the `openclaw-deploy.ps1` script into the same directory on the offline machine.
2. (Optional) If you want to keep things organized, it is recommended to move these two files to the permanent installation path for OpenClaw (e.g., `D:\Program Files\OpenClaw`).
3. Open PowerShell in that directory and execute the offline installation command:
```powershell
.\openclaw-deploy.ps1 -Action install
```


4. The script will automatically extract, reassemble dependencies offline, build the backend and UI, and register the global command in Windows.
5. Once you see the green `Install completed!`, **run the final startup command**:
```powershell
openclaw onboard --install-daemon
```



---

## ⚙️ Advanced Usage

### Registry Settings

The project uses Taobao mirror by default. You can choose not to use 3-rd-party mirror by setting this param.

**Parameter Descriptions:**
* `-Registry default` (or omitted): Uses the Taobao mirror by default (`https://registry.npmmirror.com/`).
* `-Registry official`: Connects directly to the official npm registry (`https://registry.npmjs.org/`).
* `-Registry "https://..."` (Custom URL): Uses your configured private registry (e.g., `https://npm.yourcompany.com/`).

**Usage Examples:**
```powershell
# Pack using the official registry
.\openclaw-deploy.ps1 -Action pack -Registry official

# Pack using a custom private registry with limited concurrency
.\openclaw-deploy.ps1 -Action pack -Registry "[https://npm.custom.com/](https://npm.custom.com/)" -Concurrency 2
```

 ### Network Parameter Tuning
During the `pack` phase, if your connection to the mirror is highly unstable or your ISP restricts concurrency (typically showing repeated `ECONNRESET` errors), you can use additional arguments to lower concurrency and increase retries:

```powershell
.\openclaw-deploy.ps1 -Action pack -Concurrency 2 -Retries 10 -RetryTimeout 3000
```

**Parameter Descriptions:**

* `-Concurrency`: Network concurrency limit. Default is `3`. The worse your network, the lower this should be (e.g., 1 or 2).
* `-Retries`: Number of retries upon download failure. Default is `8`.
* `-RetryTimeout`: Delay between retries (in milliseconds). Default is `2000` (2 seconds).

---

## ❓ Frequently Asked Questions (FAQ)

**Q: What should I do if it shows `[FATAL ERROR] pnpm install (Pack Phase) failed with Exit Code 1` during packing?**
A: This happens due to network anomalies when connecting to the mirror. To prevent generating a corrupted package, the script triggers a safety block. You just need to **run the pack command again**. `pnpm` will use local cache to automatically resume the download until everything is successfully fetched.

**Q: What happens if I accidentally delete the `openclaw` folder after installing on the offline machine?**
A: This script uses the `pnpm link --global` symlink installation method. The extracted `openclaw` folder is the actual core of the running program. **Absolutely do not delete or move this folder**, otherwise the global `openclaw` command will immediately break.

**Q: What if the script errors out with "cannot be loaded because running scripts is disabled on this system"?**
A: Refer to the [Prerequisites] section and use the `Set-ExecutionPolicy` command to lift the PowerShell execution restriction.
