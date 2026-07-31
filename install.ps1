<#
.SYNOPSIS
  merge-submodule 一键安装脚本（Windows）
.DESCRIPTION
  1. 精确检测 Git for Windows (Git Bash)，四级降级：注册表 -> git.exe 反查 -> bash.exe + Git 性质判定 -> 兜底固定路径
  2. 下载 merge-submodule 到 %LOCALAPPDATA%\merge-submodule
  3. 把安装目录写入用户级 PATH（永久，无需管理员，幂等）
  4. 提示需在 Git Bash 中调用
.NOTES
  用法（PowerShell）：
    irm https://raw.githubusercontent.com/lwt-sadais/merge-submodule/main/install.ps1 | iex
#>

# ============================ 配置 ============================
$RepoOwner = 'lwt-sadais'
$RepoName  = 'merge-submodule'
$Version   = if ($env:MERGE_SUBMODULE_VERSION) { $env:MERGE_SUBMODULE_VERSION } else { 'main' }
$ScriptUrl = "https://raw.githubusercontent.com/$RepoOwner/$RepoName/$Version/merge-submodule"
$InstallDir = Join-Path $env:LOCALAPPDATA $RepoName

# ============================ 工具函数 ============================
function Write-Info  { param([string]$Msg) Write-Host "ℹ️  $Msg" -ForegroundColor Cyan }
function Write-Ok    { param([string]$Msg) Write-Host "✅ $Msg" -ForegroundColor Green }
function Write-Warn  { param([string]$Msg) Write-Host "⚠️  $Msg" -ForegroundColor Yellow }
function Write-Err   { param([string]$Msg) Write-Host "❌ $Msg" -ForegroundColor Red }

# ============================ Git Bash 检测 ============================

# 给定 Git 安装根目录，返回 bash.exe 路径（验证存在性），不存在返回 $null
function Test-GitRoot {
    param([string]$Root)
    if ([string]::IsNullOrWhiteSpace($Root)) { return $null }
    foreach ($rel in @('bin\bash.exe', 'usr\bin\bash.exe')) {
        $p = Join-Path $Root $rel
        if (Test-Path -LiteralPath $p -PathType Leaf) { return $p }
    }
    return $null
}

# 精确检测 Git for Windows，返回 bash.exe 绝对路径，找不到返回 $null
# 检测顺序：注册表 Uninstall 键 -> git.exe 反查 -> bash.exe + Git 性质判定 -> 兜底固定路径
function Find-GitForWindowsBash {
    # ---------- 1. 注册表 Uninstall 键 ----------
    # Inno Setup 自动写入：InstallLocation、DisplayName、DisplayVersion、Publisher、'Inno Setup: App Path'
    # 三个 hive 必须都查：HKLM 64位视图 / HKLM WOW6432Node(32位视图) / HKCU(非管理员安装)
    $regRoots = @(
        'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*',
        'HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*',
        'HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*'
    )
    foreach ($root in $regRoots) {
        try {
            $keys = Get-ChildItem -LiteralPath $root -ErrorAction SilentlyContinue
            foreach ($k in $keys) {
                $props = Get-ItemProperty -LiteralPath $k.PSPath -ErrorAction SilentlyContinue
                if ($null -eq $props) { continue }
                $name = [string]$props.DisplayName
                $pub  = [string]$props.Publisher
                # DisplayName -match '^Git\b' 容忍 Inno Setup 的 "(64-bit)" 后缀
                # Publisher -match 'Git' 双重过滤，排除 GitHub Desktop 等
                if ($name -match '^Git\b' -and $pub -match 'Git') {
                    # 优先 InstallLocation，缺失回退 Inno Setup 私有值 'Inno Setup: App Path'
                    $loc = [string]$props.InstallLocation
                    if ([string]::IsNullOrWhiteSpace($loc)) {
                        $loc = [string]$props.'Inno Setup: App Path'
                    }
                    if (-not [string]::IsNullOrWhiteSpace($loc)) {
                        $loc = $loc.TrimEnd('\')
                        $bash = Test-GitRoot $loc
                        if ($bash) { return $bash }
                    }
                }
            }
        } catch { }
    }

    # ---------- 2. git.exe 反查 ----------
    # Get-Command git 返回 <GitRoot>\cmd\git.exe，推导根目录再找 bash.exe
    try {
        $g = Get-Command git.exe -ErrorAction SilentlyContinue
        if ($g -and -not [string]::IsNullOrWhiteSpace($g.Source)) {
            $gitExe = $g.Source
            $dir = Split-Path -Parent $gitExe
            $name = Split-Path -Leaf $dir
            # cmd\git.exe -> 父目录即根；mingw64\bin\git.exe -> 向上两级；bin\git.exe -> 父目录
            $root = if ($name -ieq 'cmd') { Split-Path -Parent $dir }
                    elseif ($name -ieq 'bin') {
                        $parent = Split-Path -Parent $dir
                        if ((Split-Path -Leaf $parent) -match '^mingw(32|64)$') { Split-Path -Parent $parent }
                        else { $parent }
                    }
                    else { Split-Path -Parent $dir }
            if ($root) {
                $bash = Test-GitRoot $root
                if ($bash) { return $bash }
            }
        }
    } catch { }

    # ---------- 3. bash.exe + Git 性质判定 ----------
    # 区分 WSL(System32\bash.exe)、Cygwin、MSYS2：路径含 \Git\ 段 或 同目录有 git.exe
    try {
        $bashes = @(Get-Command bash.exe -All -ErrorAction SilentlyContinue)
        if (-not $bashes) { $bashes = @(Get-Command bash -All -ErrorAction SilentlyContinue) }
        foreach ($b in $bashes) {
            $src = $b.Source
            if ([string]::IsNullOrWhiteSpace($src)) { continue }
            # (a) 路径含 \Git\ 段，截取到 Git 目录为根
            if ($src -match '\\Git\\') {
                $idx = $src.ToUpperInvariant().IndexOf('\GIT\')
                if ($idx -ge 0) {
                    $root = $src.Substring(0, $idx + 4)  # 含 "\Git"
                    $bash = Test-GitRoot $root
                    if ($bash) { return $bash }
                }
            }
            # (b) 同目录有 git.exe（<GitRoot>\bin\bash.exe 旁有 git.exe）
            $dir = Split-Path -Parent $src
            if (Test-Path -LiteralPath (Join-Path $dir 'git.exe') -PathType Leaf) {
                $root = Split-Path -Parent $dir
                $bash = Test-GitRoot $root
                if ($bash) { return $bash }
            }
        }
    } catch { }

    # ---------- 4. 兜底固定路径 ----------
    $candidates = @(
        "$env:ProgramFiles\Git\bin\bash.exe",
        "${env:ProgramFiles(x86)}\Git\bin\bash.exe",
        "$env:LOCALAPPDATA\Programs\Git\bin\bash.exe"
    )
    foreach ($c in $candidates) {
        if ($c -and (Test-Path -LiteralPath $c -PathType Leaf)) { return $c }
    }

    return $null
}

# ============================ 主流程 ============================

# 1. 检测 Git Bash
Write-Info '检测 Git for Windows (Git Bash) ...'
$bashPath = Find-GitForWindowsBash
if ([string]::IsNullOrWhiteSpace($bashPath)) {
    Write-Err '未检测到 Git for Windows (Git Bash)'
    Write-Host ''
    Write-Host '请先安装 Git for Windows：https://git-scm.com/downloads' -ForegroundColor Yellow
    Write-Host '安装完成后重新运行此安装脚本。' -ForegroundColor Yellow
    exit 1
}
$gitRoot = Split-Path -Parent (Split-Path -Parent $bashPath)
Write-Ok "检测到 Git Bash：$bashPath"
Write-Info "Git 根目录：$gitRoot"

# 2. 创建安装目录
if (-not (Test-Path -LiteralPath $InstallDir -PathType Container)) {
    New-Item -ItemType Directory -Path $InstallDir -Force | Out-Null
}
Write-Info "安装目录：$InstallDir"

# 3. 下载核心脚本
Write-Info "下载 merge-submodule ($Version) ..."
$dest = Join-Path $InstallDir 'merge-submodule'
try {
    # TLS 1.2 兼容老版本 PowerShell
    [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
    Invoke-WebRequest -Uri $ScriptUrl -OutFile $dest -UseBasicParsing -ErrorAction Stop
} catch {
    Write-Err "下载失败：$ScriptUrl"
    Write-Err $_.Exception.Message
    exit 1
}
Write-Ok "merge-submodule 已安装到 $dest"

# 4. 写入用户级 PATH（永久，幂等）
Write-Info '配置用户级 PATH ...'
$dirInPath = $false

# 读取当前进程 PATH 看是否已生效
$currentPath = [Environment]::GetEnvironmentVariable('Path', 'User')
if ($currentPath) {
    $parts = $currentPath -split ';' | ForEach-Object { $_.Trim() }
    foreach ($p in $parts) {
        if ($p -ieq $InstallDir) { $dirInPath = $true; break }
    }
}

if ($dirInPath) {
    Write-Info "$InstallDir 已在用户级 PATH 中，跳过配置"
} else {
    # 幂等：拼接后写回用户级 PATH（不影响系统级 PATH，无需管理员）
    $newPath = if ([string]::IsNullOrWhiteSpace($currentPath)) { $InstallDir } else { "$InstallDir;$currentPath" }
    [Environment]::SetEnvironmentVariable('Path', $newPath, 'User')
    # 同时更新当前会话 PATH，避免要求用户重开终端才能用 $InstallDir
    if (-not ($env:Path -split ';' -contains $InstallDir)) {
        $env:Path = "$InstallDir;$env:Path"
    }
    Write-Ok "已将 $InstallDir 写入用户级 PATH"
}

# 5. 输出使用说明
Write-Host ''
Write-Ok '安装成功！'
Write-Host ''
Write-Host '使用方式：' -ForegroundColor Cyan
Write-Host '  1. 打开 Git Bash（开始菜单搜索 "Git Bash"）'
Write-Host '  2. cd 到含子模块的项目目录'
Write-Host '  3. 执行 merge-submodule <目标分支>'
Write-Host ''
Write-Host '示例：' -ForegroundColor Cyan
Write-Host '  cd /c/your/project/with-submodules'
Write-Host '  merge-submodule master'
Write-Host ''
Write-Warn '注意：必须在 Git Bash 中执行（核心脚本是 bash 脚本）'
Write-Warn '若新开 Git Bash 后命令未找到，请重开终端使 PATH 生效'
