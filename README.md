# merge-submodule

一键安装的子模块合并命令行工具：**把每个子模块的源分支合并到该子模块的目标分支**。

适用于含 git submodule 的项目发布流程，在任意项目目录下执行 `merge-submodule <目标分支>`，自动递归处理所有子模块（从内到外），仅合并子模块内部，主项目保持不动。

## 功能

- 🔄 **递归处理嵌套子模块**：后序遍历，从最内层子模块开始合并
- 🎯 **源分支智能识别**：优先取 `.gitmodules` 配置的 `branch`，未配置则取子模块当前 `HEAD` 所在分支
- 🔁 **自动同步远程**：源分支与目标分支都会先 `fetch` + 处理脏工作区 + ahead/behind 同步，再合并
- 🧹 **脏工作区处理**：分支落后时自动暂存已跟踪及未跟踪文件，只恢复本次创建的 stash；恢复冲突时保留 stash 并停止
- 🛡️ **安全跳过**：子模块无目标分支时打印警告并跳过，不影响其它子模块
- 🚫 **detached HEAD 保护**：子模块处于 detached HEAD 且未配置 branch 时报错退出
- 🔴 **日志醒目显示**：脚本自身日志统一使用红色加粗样式，Git 命令的原生输出不受影响

## 安装

### Mac / Linux

```bash
curl -fsSL https://raw.githubusercontent.com/lwt-sadais/merge-submodule/main/install.sh | sh
```

自动完成：
1. 下载 `merge-submodule` 到 `~/.local/bin/`
2. 赋予可执行权限
3. 把 `~/.local/bin` 写入 `~/.zshrc` / `~/.bashrc`（幂等，已存在则跳过）

### Windows

```powershell
irm https://raw.githubusercontent.com/lwt-sadais/merge-submodule/main/install.ps1 | iex
```

自动完成：
1. **精确检测 Git for Windows**（四级降级：注册表 → git.exe 反查 → bash.exe + Git 性质判定 → 兜底固定路径）
2. 下载 `merge-submodule` 到 `%LOCALAPPDATA%\merge-submodule\`
3. 把安装目录写入**用户级 PATH**（永久，无需管理员，幂等）

> ⚠️ Windows 端依赖 Git Bash，核心脚本是 bash 脚本，必须在 **Git Bash** 中执行。
> 未安装 Git for Windows 时安装脚本会报错并给出下载链接。

## 使用

```bash
cd /your/project/with-submodules
merge-submodule master        # 把每个子模块的源分支合并到该子模块的 master
merge-submodule zsgr-master   # 合并到 zsgr-master
```

### 执行流程（每个子模块内部）

```
1. 确定源分支：.gitmodules 的 branch，未配置则 git rev-parse --abbrev-ref HEAD
2. 源分支同步：fetch -> 脏工作区处理(stash/pull 或 reset/apply/commit) -> ahead/behind 对齐
3. 切目标分支 -> 同步目标分支 -> merge 源分支(--no-edit) -> push -> 回切源分支
```

### 行为说明

| 场景 | 行为 |
|------|------|
| 作用范围 | 仅子模块内部，主项目完全不动 |
| 嵌套子模块 | 后序递归，从内到外处理 |
| `.gitmodules` 配置了 branch | 用配置值作为源分支 |
| 未配置 branch | 取子模块当前 `HEAD` 所在分支 |
| 子模块无目标分支 | 打印警告并跳过该子模块，继续处理其它 |
| detached HEAD 且未配置 branch | 报错退出整个流程 |
| 本地工作区有改动且分支落后 | 自动 stash 已跟踪及未跟踪文件 → 同步 → 精确 apply 本次 stash → commit |
| 本地工作区有改动且分支不落后 | 直接自动提交 |
| 已存在用户 stash | 不恢复、不删除，只处理脚本本次创建的 stash |
| stash 恢复冲突 | 立即停止并保留 stash，输出仓库、分支、冲突文件及人工恢复指引，不自动覆盖任一侧 |
| 既领先又落后 | `reset --hard origin/<branch>` 强制对齐远程 |
| 任一 git 步骤失败 | 立即退出并提示 |

## 安装到指定版本

通过环境变量指定版本 tag：

```bash
# Mac / Linux
MERGE_SUBMODULE_VERSION=v1.0.0 curl -fsSL https://raw.githubusercontent.com/lwt-sadais/merge-submodule/main/install.sh | sh

# Windows
$env:MERGE_SUBMODULE_VERSION='v1.0.0'; irm https://raw.githubusercontent.com/lwt-sadais/merge-submodule/main/install.ps1 | iex
```

## 卸载

```bash
# Mac / Linux
rm -f ~/.local/bin/merge-submodule
# 并手动从 ~/.zshrc 或 ~/.bashrc 删除以下行：
#   export PATH="$HOME/.local/bin:$PATH"

# Windows
Remove-Item -Recurse -Force "$env:LOCALAPPDATA\merge-submodule"
# 并从用户级 PATH 移除该目录：
#   $p = [Environment]::GetEnvironmentVariable('Path','User') -split ';' | Where-Object { $_ -ne "$env:LOCALAPPDATA\merge-submodule" }
#   [Environment]::SetEnvironmentVariable('Path', ($p -join ';'), 'User')
```

## 来源

从 [dt-sale-console](https://github.com/lwt-sadais/dt-sale-console) 项目的 `publish.sh` 中抽取子模块合并逻辑独立成工具，发布流程脚本本身不受影响。
