#!/usr/bin/env bash
# install.sh — merge-submodule 一键安装脚本（Mac / Linux）
#
# 功能：
#   1. 下载 merge-submodule 到 ~/.local/bin
#   2. 赋予可执行权限
#   3. 自动把 ~/.local/bin 加入 PATH（幂等，不重复追加）
#
# 用法：
#   curl -fsSL https://raw.githubusercontent.com/lwt-sadais/merge-submodule/main/install.sh | sh
#
# 环境变量：
#   MERGE_SUBMODULE_VERSION  指定版本 tag，默认 main

set -euo pipefail

# ============================ 配置 ============================
INSTALL_DIR="$HOME/.local/bin"
SCRIPT_NAME="merge-submodule"
REPO_OWNER="lwt-sadais"
REPO_NAME="merge-submodule"
VERSION="${MERGE_SUBMODULE_VERSION:-main}"
BASE_URL="https://raw.githubusercontent.com/${REPO_OWNER}/${REPO_NAME}/${VERSION}"
SCRIPT_URL="${BASE_URL}/${SCRIPT_NAME}"
PATH_LINE='export PATH="$HOME/.local/bin:$PATH"'

# ============================ 工具函数 ============================

# 统一的彩色输出
info()  { printf "\033[36mℹ️\033[0m  %s\n" "$*"; }
ok()    { printf "\033[32m✅\033[0m %s\n" "$*"; }
warn()  { printf "\033[33m⚠️\033[0m %s\n" "$*"; }
error() { printf "\033[31m❌\033[0m %s\n" "$*" >&2; }

# ============================ 主流程 ============================

# 1. 创建安装目录
mkdir -p "$INSTALL_DIR"
info "安装目录：$INSTALL_DIR"

# 2. 下载核心脚本
info "下载 $SCRIPT_NAME ($VERSION) ..."
if command -v curl >/dev/null 2>&1; then
  curl -fsSL "$SCRIPT_URL" -o "$INSTALL_DIR/$SCRIPT_NAME" || { error "下载失败：$SCRIPT_URL"; exit 1; }
elif command -v wget >/dev/null 2>&1; then
  wget -qO "$INSTALL_DIR/$SCRIPT_NAME" "$SCRIPT_URL" || { error "下载失败：$SCRIPT_URL"; exit 1; }
else
  error "未找到 curl 或 wget，无法下载"
  exit 1
fi

# 3. 赋予可执行权限
chmod +x "$INSTALL_DIR/$SCRIPT_NAME"
ok "$SCRIPT_NAME 已安装到 $INSTALL_DIR/$SCRIPT_NAME"

# 4. 自动加入 PATH（幂等）
# 判断 ~/.local/bin 是否已在当前 PATH 中
path_has_install_dir() {
  case ":$PATH:" in
    *":$INSTALL_DIR:"*) return 0 ;;
    *) return 1 ;;
  esac
}

# 向 shell 配置文件追加 PATH 导出行（幂等：已有则跳过）
append_path_to_rc() {
  local rc_file="$1"
  [[ ! -f "$rc_file" ]] && touch "$rc_file"
  # grep 幂等判断：已存在该导出行则不重复追加
  if grep -qF "$PATH_LINE" "$rc_file" 2>/dev/null; then
    return 1  # 已存在
  fi
  printf '\n# merge-submodule: 加入 PATH\n%s\n' "$PATH_LINE" >> "$rc_file"
  return 0  # 新追加
}

# 根据当前 shell 选择配置文件
add_to_path() {
  local shell_name added=0
  shell_name="$(basename "$SHELL" 2>/dev/null || echo "")"

  if path_has_install_dir; then
    info "$INSTALL_DIR 已在 PATH 中，跳过配置"
    return 0
  fi

  case "$shell_name" in
    zsh)
      if append_path_to_rc "$HOME/.zshrc"; then
        ok "已向 ~/.zshrc 追加 PATH 导出"
        added=1
      else
        warn "~/.zshrc 已包含 PATH 导出，但当前会话未生效"
      fi
      ;;
    bash)
      # bash 可能用 .bashrc 或 .bash_profile，都尝试
      local touched=0
      if append_path_to_rc "$HOME/.bashrc"; then ok "已向 ~/.bashrc 追加 PATH 导出"; touched=1; fi
      if append_path_to_rc "$HOME/.bash_profile"; then ok "已向 ~/.bash_profile 追加 PATH 导出"; touched=1; fi
      [[ $touched -eq 1 ]] && added=1
      [[ $touched -eq 0 ]] && warn "~/.bashrc / ~/.bash_profile 已包含 PATH 导出，但当前会话未生效"
      ;;
    fish)
      local fish_config="$HOME/.config/fish/config.fish"
      mkdir -p "$(dirname "$fish_config")"
      if grep -qF 'fish_add_path $HOME/.local/bin' "$fish_config" 2>/dev/null; then
        warn "$fish_config 已包含 PATH 导出，但当前会话未生效"
      else
        printf '\n# merge-submodule: 加入 PATH\nfish_add_path $HOME/.local/bin\n' >> "$fish_config"
        ok "已向 $fish_config 追加 PATH 导出"
        added=1
      fi
      ;;
    *)
      warn "未识别的 shell: $shell_name，请手动将以下内容加入 shell 配置："
      printf '  %s\n' "$PATH_LINE"
      ;;
  esac

  if [[ $added -eq 1 ]]; then
    info "请执行以下命令使 PATH 立即生效（或新开一个终端）："
    case "$shell_name" in
      zsh)  printf '  source ~/.zshrc\n' ;;
      bash) printf '  source ~/.bashrc\n' ;;
      fish) printf '  exec fish\n' ;;
    esac
  fi
}

add_to_path

# 5. 验证安装
echo ""
if path_has_install_dir; then
  if "$INSTALL_DIR/$SCRIPT_NAME" >/dev/null 2>&1; then
    ok "验证失败（脚本不应无参静默退出）"
  else
    ok "安装成功！执行 merge-submodule <target-branch> 开始使用"
  fi
else
  ok "安装成功！新开终端后执行 merge-submodule <target-branch> 开始使用"
fi
echo ""
echo "示例："
echo "  cd /your/project/with-submodules"
echo "  merge-submodule master"
