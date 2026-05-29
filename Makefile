# Pi Config Sync — Makefile
# 统一入口，操作 ~/.pi/agent 下的分层配置
#
# 用法:
#   make split       拆分现有的 settings.json
#   make init-local  创建当前机器的 settings.local.json
#   make merge       合并 base + local → settings.json
#   make push        推送到 dotfiles
#   make pull        从 dotfiles 拉取
#
# 环境变量覆盖:
#   PI_DIR=/custom/path make merge
#   DOTFILES_DIR=/custom/path make push

PI_DIR      ?= $(HOME)/.pi/agent
# dotfiles 默认就是当前仓库目录（脚本所在目录）
DOTFILES_DIR?= .
MERGE       := PI_DIR="$(PI_DIR)" ./pi-config-merge.sh
SYNC        := PI_DIR="$(PI_DIR)" DOTFILES_DIR="$(DOTFILES_DIR)" ./pi-config-sync.sh

.PHONY: help split init-local merge validate diff watch env \
        init push pull status setup bootstrap full-push

# ----------------------------------------------------------------------------
# Help
# ----------------------------------------------------------------------------
help:
	@echo "Pi Config Sync — 可用命令"
	@echo ""
	@echo "  make split       拆分现有 settings.json → base + local"
	@echo "  make init-local  为本机创建 settings.local.json (自动检测 OS)"
	@echo "  make merge       合并 base + local → settings.json"
	@echo "  make validate    验证 settings.json 与合并结果是否一致"
	@echo "  make diff        显示当前 settings.json 与合并结果的差异"
	@echo "  make watch       监听 base/local 变化，自动合并"
	@echo "  make env         打印环境检测信息"
	@echo ""
	@echo "  make init        初始化 dotfiles 仓库"
	@echo "  make push        推送配置到 dotfiles (含 git commit)"
	@echo "  make pull        从 dotfiles 拉取配置 (含自动合并)"
	@echo "  make status      显示各文件同步状态"
	@echo ""
	@echo "  make setup       首次设置: split + init-local + merge"
	@echo "  make bootstrap   新设备: pull + init-local + merge"
	@echo "  make full-push   merge + push (日常推送一条龙)"
	@echo ""
	@echo "环境变量:"
	@echo "  PI_DIR       = $(PI_DIR)"
	@echo "  DOTFILES_DIR = $(DOTFILES_DIR)"

# ----------------------------------------------------------------------------
# Merge / Split
# ----------------------------------------------------------------------------
split:
	$(MERGE) split

init-local:
	$(MERGE) init-local

merge:
	$(MERGE) merge

validate:
	$(MERGE) validate

diff:
	$(MERGE) diff

watch:
	$(MERGE) watch

env:
	$(MERGE) env

# ----------------------------------------------------------------------------
# Sync (dotfiles)
# ----------------------------------------------------------------------------
init:
	$(SYNC) init

push:
	$(SYNC) push

pull:
	$(SYNC) pull

status:
	$(SYNC) status

# ----------------------------------------------------------------------------
# 组合命令
# ----------------------------------------------------------------------------

## 首次设置: 拆分现有配置 + 创建本地覆盖 + 合并
setup: split init-local merge
	@echo ""
	@echo "✓ 初始化完成"
	@echo "  共享配置: $(PI_DIR)/settings.base.json"
	@echo "  本地配置: $(PI_DIR)/settings.local.json"
	@echo "  生成文件: $(PI_DIR)/settings.json"
	@echo ""
	@echo "下一步:"
	@echo "  1. 按需编辑 $(PI_DIR)/settings.local.json"
	@echo "  2. make init    → 初始化 dotfiles 仓库"
	@echo "  3. make push    → 推送到远程"

## 新设备恢复: 拉取共享配置 + 创建本地覆盖 + 合并
bootstrap: pull init-local merge
	@echo ""
	@echo "✓ 新设备配置完成"
	@echo "  共享配置已从 dotfiles 恢复"
	@echo "  本地配置已根据当前 OS 初始化"
	@echo ""
	@echo "下一步:"
	@echo "  1. 检查并调整 $(PI_DIR)/settings.local.json"
	@echo "  2. pi update --extensions    → 重装包"
	@echo "  3. pi login                  → 配置 API Key"

## 日常推送: 合并后推送到 dotfiles
full-push: merge push
	@echo ""
	@echo "✓ 已合并并推送到 dotfiles"
	@echo "  运行: git push"
