<div align="right">
  <strong>简体中文</strong> | <a href="./README.en.md">English</a>
</div>

---

# OpenClaw Windows 万能离线部署脚本

一个 OpenClaw 一键离线打包与部署工具。适用于自联网机器打包安装到非联网机器部署，解决跨平台架构部署问题。

目前支持Windows-Windows。非WSL2及Docker方案。

对网络代理的需求更小。除一个Github官方仓库外，其余npm部分采用淘宝镜像，中国大陆地区连接更加稳定。

---

## ⚠️ 声明 (Anti-Scam Warning)

本脚本采用 **CC BY-NC-SA 4.0（署名-非商业性使用-相同方式共享）** 协议开源。

1. **免费**：本项目仅供技术学习与交流使用。
2. **禁止商用与倒卖**：严禁任何个人或组织利用本脚本替他人进行有偿部署、倒卖，或将其作为商业服务的一部分以获取利润。
3. **禁止洗稿闭源**：任何人基于本脚本进行修改、优化或衍生出的新脚本，**必须**保留本声明，并以相同的开源协议免费发布，严禁闭源规避版权。
4. **转载著明出处**。

🚨 **防骗提醒**：如果你是花钱购买到这个脚本或此部署服务的，**说明你被骗了**，请立刻向卖家发起退款并举报！

---

## ✨ 核心特性

* **跨平台离线部署**：自动配置全量部署，确保 Mac/Linux/Windows 和 x64/ARM 架构依赖的二进制包一次性全量抓取。
* **智能断点续传与并发控制**：内置网络异常阻断与参数化重试机制，针对部分网络环境对并发的限制进行优化。

---

## 🛠️ 前置准备

在开始之前，请确保您的机器满足以下条件：

### 【联网机器】（用于制作离线包）

* 操作系统：Windows 10 / 11
* 已安装 [Node.js](https://nodejs.org/) (推荐 v24 或 v22.19+ 版本)
* （可选）已安装 [Git](https://git-scm.com/install/windows/)

### 【离线机器】（目标部署机）

* 操作系统：Windows 10 / 11
* 已安装 [Node.js](https://nodejs.org/) (版本需与联网机保持一致)

> **注意**：Windows 首次运行 `.ps1` 脚本时可能会被系统安全策略拦截。请以管理员身份打开 PowerShell 并执行以下命令放行：
> ```powershell
> Set-ExecutionPolicy RemoteSigned -Scope CurrentUser
> ```
> 
> 

---

## 🚀 使用教程

### 阶段一：在【联网机器】制作离线包

1. 下载本仓库的 `openclaw-deploy.ps1` 脚本，放置在任意空白目录。
2. 在该目录下打开 PowerShell，执行以下命令开始打包：
```powershell
.\openclaw-deploy.ps1 -Action pack
```
3. 脚本会自动拉取最新源码、配置镜像、下载所有跨平台依赖并打包。
    > 若未安装[Git](https://git-scm.com/install/windows/)，请提前自行下载[Openclaw](https://github.com/openclaw/openclaw)官方仓库代码，并解压复制到同目录下，重命名为“Openclaw”。注意二级目录。
4. 等待执行完毕（出现绿色的 `Pack completed!` 提示），当前目录下会生成一个 **`openclaw-offline-windows.zip`** 压缩包。

### 阶段二：在【无网机器】释放与安装

1. 将生成的 `openclaw-offline-windows.zip` 和 `openclaw-deploy.ps1` 脚本一起拷贝到离线机器的同一个目录下。
2. （可选）如果你想保持目录整洁，建议在此刻将这两个文件移动到你打算永久安装 OpenClaw 的路径下（例如 `D:\Program Files\OpenClaw`）。
3. 在该目录下打开 PowerShell，执行离线安装命令：
```powershell
.\openclaw-deploy.ps1 -Action install
```


4. 脚本将自动解压、离线重组依赖、编译前后端 UI，并向 Windows 注册全局命令。
5. 看到绿色的 `Install completed!` 后，**执行最后一步启动命令**：
```powershell
openclaw onboard --install-daemon
```

---

## ⚙️ 进阶参数设置

### 镜像源设置。

默认使用淘宝镜像加速，请根据你的网络环境或喜好自行选择。

**参数说明：**
* `-Registry default`（或不填）：默认使用淘宝镜像 `https://registry.npmmirror.com/`
* `-Registry official`：不使用镜像，直连官方源 `https://registry.npmjs.org/`
* `-Registry "https://..."`（任意网址）：使用你配置的私有源（例：`https://npm.yourcompany.com/`）。

**使用示例：**
```powershell
# 使用官方源打包
.\openclaw-deploy.ps1 -Action pack -Registry official

# 使用自定义私有源打包，并限制并发
.\openclaw-deploy.ps1 -Action pack -Registry "[https://npm.custom.com/](https://npm.custom.com/)" -Concurrency 2
```

### 网络参数调节
在 `pack` (打包) 阶段，如果你的网络连接镜像站非常不稳定或运营商限制并发（典型为反复报错ECONNRESET），可通过附加参数来降低并发，增加重试次数：

```powershell
.\openclaw-deploy.ps1 -Action pack -Concurrency 2 -Retries 10 -RetryTimeout 3000
```

**参数说明：**

* `-Concurrency`: 网络并发数。默认 `3`。网络越差，建议调得越低（如 1 或 2）。
* `-Retries`: 下载失败时的重试次数。默认 `8` 次。
* `-RetryTimeout`: 每次重试的间隔时间（毫秒）。默认 `2000` (2秒)。

---

## ❓ 常见问题 (FAQ)

**Q: 打包时提示 `[FATAL ERROR] pnpm install (Pack Phase) failed with Exit Code 1` 怎么办？**
A: 这是因为连接镜像站时发生了网络异常。脚本为了防止生成残缺的包，触发了安全阻断。你只需要**再次运行**打包命令即可，`pnpm` 会利用本地缓存自动断点续传，直到全部下载成功。

**Q: 离线机器安装后，如果我不小心把 `openclaw` 文件夹删了会怎样？**
A: 本脚本使用的是 `pnpm link --global` 软链接安装法。解压出来的 `openclaw` 文件夹就是程序运行的实体核心。**请绝对不要删除或移动该文件夹**，否则全局的 `openclaw` 命令将立即失效。

**Q: 脚本运行报错“无法加载文件，因为在此系统上禁止运行脚本”？**
A: 参考 [前置准备] 章节，使用 `Set-ExecutionPolicy` 命令解除 PowerShell 的执行限制。