# Pi Config Sync

在多设备之间同步 [pi](https://pi.dev/) 配置，采用**分层配置**方案——机器无关的基础配置 + 机器专属的本地覆盖。

> **本仓库本身就是 dotfiles 仓库。** 你把本仓库克隆到任意位置，配置就存在这里，直接 `git push` 即可同步到多设备。

## 为什么要分层配置？

你的 `~/.pi/agent/settings.json` 混合了两种配置：

- **共享配置** — 模型偏好、已安装包、主题（`defaultModel`、`packages`...）
- **机器专属配置** — Shell 路径、操作系统相关前缀（`shellPath`、`shellCommandPrefix`...）

如果直接把整个 `settings.json` 推送到 Git，在另一台设备上拉取时会出问题——比如 Mac 上读到一个 Windows 的 `shellPath`。

这个方案把 `settings.json` 当作**生成产物**（类似 `dist/`），将源配置拆成两层：

| 文件 | 用途 | 是否 Git 同步 |
|------|------|-------------|
| `settings.base.json` | 共享配置（模型、包、主题） | **是** |
| `settings.local.json` | 机器专属路径和覆盖项 | **否** |
| `settings.json` | 合并后的最终文件（pi 实际读取） | **否**（自动生成） |

## 前置条件

- [jq](https://jqlang.github.io/jq/download/) — `pi-config-merge.sh` 需要
- Git — `pi-config-sync.sh` 需要
- pi 已安装并至少运行过一次

## 文件结构

```
~/.pi/agent/                           本仓库目录（当前目录）
├── settings.base.json      # ← 共享 ─┐
├── settings.local.json     # ← 私有  │
├── settings.json           # ← 生成  │
├── auth.json               # ← 私有  │
├── skills/                 # ← 共享 ─┤
├── extensions/             # ← 共享  │  git push/pull
├── themes/                 # ← 共享  │  同步这些内容
├── prompts/                # ← 共享 ─┘
├── sessions/               # ← 自动生成（不同步）
├── npm/                    # ← 自动生成（不同步）
└── bin/                    # ← 自动生成（不同步）
```

本仓库只保存共享配置（`settings.base.json`、`skills/` 等），`settings.local.json` 和 `auth.json` 留在本机。

## 快速开始

### 1. 迁移现有配置（一次性的）

克隆本仓库到任意位置：

```bash
git clone https://github.com/你的用户名/pi-config-sync.git ~/dev/pi-config-sync
cd ~/dev/pi-config-sync

# 一键完成拆分 + 生成本地配置 + 合并
make setup
```

`setup` 会自动完成：
1. `split` — 拆分现有 `settings.json` 为 `base` + `local`
2. `init-local` — 根据当前操作系统生成 `settings.local.json`
3. `merge` — 合并生成最终的 `settings.json`

### 2. 初始化 Git 仓库

```bash
make init                    # 初始化本目录为 git 仓库（如果还不是）

git remote add origin https://github.com/你的用户名/pi-config-sync.git
git add . && git commit -m "Initial pi config"
git push -u origin main
```

> `.gitignore` 会自动生成，排除 `auth.json`、`settings.json`、`settings.local.json`、`sessions/`、`npm/`、`bin/`。

### 3. 日常 workflow（主力机）

```bash
# 编辑共享配置（比如换默认模型）
vim ~/.pi/agent/settings.base.json

# 编辑本地配置（比如调整 shell 路径）
vim ~/.pi/agent/settings.local.json

# 重新生成 settings.json
make merge

# 推送到本仓库
make full-push    # merge + push（一条龙）
git push
```

或者在开发配置时用 watch 自动合并：

```bash
make watch
# 在另一个终端编辑 base 或 local，settings.json 会自动更新
```

### 4. 在新设备上恢复

```bash
# 克隆本仓库
git clone https://github.com/你的用户名/pi-config-sync.git ~/dev/pi-config-sync
cd ~/dev/pi-config-sync

# 一键恢复：拉取共享配置 + 生成本地覆盖 + 合并
make bootstrap
```

`bootstrap` 会自动完成：
1. `pull` — 从本仓库恢复共享配置到 `~/.pi/agent/`
2. `init-local` — 根据当前操作系统生成 `settings.local.json`
3. `merge` — 合并生成 `settings.json`

然后手动完成：

```bash
# 按需微调本地配置
vim ~/.pi/agent/settings.local.json
make merge

# 重装 settings 中声明的所有 pi 包
pi update --extensions

# 配置 API Key
pi login
```

## 命令参考

### Make 命令（推荐）

| 命令 | 作用 |
|------|------|
| `make setup` | **首次设置**：`split` + `init-local` + `merge` |
| `make bootstrap` | **新设备**：`pull` + `init-local` + `merge` |
| `make full-push` | **日常推送**：`merge` + `push` |
| `make merge` | 合并 `base + local` → `settings.json` |
| `make split` | 拆分现有 `settings.json` → `base + local` |
| `make init-local` | 为当前 OS 创建 `settings.local.json` |
| `make validate` | 验证 `settings.json` 是否一致 |
| `make diff` | 显示当前与合并结果的差异 |
| `make watch` | 监听变化自动合并 |
| `make init` | 初始化 git 仓库 |
| `make push` | 复制共享配置到本仓库 + git commit |
| `make pull` | 从本仓库恢复共享配置到 `~/.pi/agent/` |
| `make status` | 显示同步状态 |
| `make env` | 打印环境信息 |

### 底层脚本（高级用法）

如需直接调用脚本（支持更多参数）：

```bash
# 合并/拆分
./pi-config-merge.sh merge
./pi-config-merge.sh split

# 同步（默认 dotfiles 目录为脚本所在目录，即当前仓库）
./pi-config-sync.sh push

# 自定义路径
PI_DIR=/custom/.pi/agent ./pi-config-sync.sh push
```

**环境变量：**

| 变量 | 默认值 | 说明 |
|------|--------|------|
| `PI_DIR` | `~/.pi/agent` | pi agent 目录 |
| `DOTFILES_DIR` | 脚本所在目录（当前仓库） | dotfiles 仓库目录 |
| `LOCAL_KEYS` | `shellPath,shellCommandPrefix,editor,npmCommand` | 始终视为机器本地的键 |

## 多设备工作流

| 操作 | 命令 | 在哪台机器 |
|------|------|-----------|
| 安装 pi 包 | `pi install npm:xxx` | 机器 A |
| 编辑共享配置 | `vim settings.base.json` | 机器 A |
| 重新生成 | `make merge` | 机器 A |
| 推送到仓库 | `make full-push && git push` | 机器 A |
| 在机器 B 恢复 | `make bootstrap` | 机器 B |
| 重装包 | `pi update --extensions` | 机器 B |

> `settings.local.json` 不会离开本机。机器 B 通过 `init-local` 创建自己的本地配置。

## 本地键是怎么被检测的？

运行 `split` 时，脚本会分析 `settings.json`，如果满足以下任一条件，该键会被归类为"本地"：

1. 键名在 `LOCAL_KEYS` 环境变量中（默认：`shellPath`、`shellCommandPrefix`、`editor`、`npmCommand`）
2. 值是绝对 Windows 路径（`D:\...`）
3. 值是绝对 Unix 路径（`/usr/bin/...`，排除 `/tmp/`、`/dev/`、`/proc/`）

其余所有键都会进入 `settings.base.json`。

## 注意事项

- **不要直接编辑 `settings.json`**。始终编辑 `settings.base.json` 或 `settings.local.json`，然后运行 `merge`。
- **CI 中可运行 `validate`**，用于捕获对 `settings.json` 的意外直接修改。
- **频繁调整配置时用 `watch`**，避免忘记合并。
- **本仓库建议设为私有**——虽然敏感信息已被排除，但包列表和模型偏好仍属于个人隐私。
