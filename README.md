# echin-dotfiles

一套可迁移的 macOS 终端配置，包含：

- **zsh + Oh My Zsh**：`robbyrussell` 主题、Git/`extract`/目录跳转插件，以及可选的自动建议和语法高亮。
- **Ghostty**：TokyoNight 配色、JetBrainsMono Nerd Font、14pt 字号、窗口内边距、静音铃声和 Cmd 快捷键映射。
- **Herdr**：终端复用器的主题配置，配置目录是 `~/.config/herdr`。
- **Neovim / LazyVim**：完整移植本机配置、插件锁文件、Go/TS/React/Tailwind 阅读和 Git 审阅功能，包含 `mcode`、`mreview` 启动命令。
- **NVM**：通过 Homebrew 安装并加载，Node.js LTS 作为默认版本；NVM 的 Node 版本目录保留在本机，不进入仓库。

仓库只保存经过审查的配置文件和安装脚本，不保存 shell 历史、Herdr 会话、日志、Token、SSH key 或任何机器专属密钥。

## 一键安装

适用于 macOS（Apple Silicon 和 Intel）：

```bash
git clone https://github.com/Echin-h/echin-dotfiles.git
cd echin-dotfiles
./install.sh
```

安装脚本会：

1. 使用 Homebrew 安装 `nvm`、`herdr`、`neovim`、`ripgrep`、`fd`、`lazygit`、`tree-sitter-cli`、`gopls`、Python、zsh 插件、Ghostty 和 JetBrainsMono Nerd Font。
2. 没有 Oh My Zsh 时，以浅克隆方式安装；再安装自动建议和语法高亮插件。
3. 创建 `~/.nvm`，把配置文件以符号链接方式接入用户目录。
4. 默认安装 Node.js LTS，并设置为 NVM 默认版本。
5. 安装锁定版本的 TS/Tailwind 语言服务，并用 `Lazy restore` 恢复 NeoVim 插件；首次安装需要访问 GitHub 和 npm。
6. 如果目标文件已经存在，先移动到 `~/.local/state/echin-dotfiles/backups/<时间戳>/`，再创建链接。

打开新终端，或者执行：

```bash
exec zsh -l
```

检查配置是否正确：

```bash
./doctor.sh
```

`doctor.sh` 会验证符号链接和 zsh 语法，并检查 NVM、Node.js、Ghostty、Herdr、NeoVim 启动及自定义模块。`--skip-deps --skip-node` 仅建立链接，不能替代完整安装验证。

## 安装选项

跳过所有依赖下载，只接入配置与启动命令：

```bash
./install.sh --skip-deps --skip-node
```

安装 NVM 但不自动安装 Node.js LTS：

```bash
./install.sh --skip-node
```

`--skip-deps` 单独使用仍可初始化 NVM/Node；`--skip-node` 单独使用时需要已有 Node/npm 才能安装语言服务。脚本也接受等价环境变量：

```bash
DOTFILES_SKIP_DEPENDENCIES=1 DOTFILES_SKIP_NODE=1 ./install.sh
```

完整安装前需安装 [Homebrew](https://brew.sh)、Git 和 macOS Command Line Tools（`xcode-select --install`），并确保 `brew` 在 PATH 中。缺少 Homebrew 时完整安装返回非零退出码；仅想接入配置可用 `--skip-deps --skip-node`。

## 文件结构

```text
config/
├── ghostty/config       # ~/.config/ghostty/config
├── herdr/config.toml    # ~/.config/herdr/config.toml
├── nvim/                # ~/.config/nvim（完整 LazyVim 配置）
└── zsh/
    ├── .zprofile        # ~/.zprofile
    └── .zshrc           # ~/.zshrc
bin/                     # mcode、mreview
lib/mate-code/           # Git commit 解析工具
tools/mate-code-tools/   # 语言服务的 npm 清单与锁文件
install.sh               # 幂等安装和备份
doctor.sh                # 本地健康检查
```


## Neovim

Neovim 是独立编辑器，Zsh 仅负责提供 `nvim`、`mcode`、`mreview` 命令的搜索路径。配置完整位于 `config/nvim/`，安装后整体链接到 `~/.config/nvim`。原有目录会先备份，包括其中已有的 Git 元数据；仓库不复制本机插件缓存、会话、undo 文件或日志。

```bash
nvim                       # 普通启动
mcode .                    # 阅读当前项目（目录树与工具栏）
mcode path/to/file.tsx      # 打开文件
mreview                    # 默认主分支共同祖先到 HEAD 的 diff
mreview main HEAD          # 比较两个版本
mreview --commit HASH       # 查看一次提交
```

本套配置基于 LazyVim，主要包含：TokyoNight 主题、鼠标目录树、顶部导航和阅读历史、函数定义/引用、Git diff、Worktree 切换，以及 Go、TypeScript/React、Tailwind 语言服务。完整快捷键和审阅行为见 [NeoVim 中文使用说明](config/nvim/README.zh-CN.md)。

**自动保存行为：** 普通可写文件在停止输入约 800ms、退出插入、切换文件或失去焦点时保存；自动格式化关闭。使用前请了解这一行为。未命名文件、只读文件和历史快照不会自动保存。

插件提交固定在 `config/nvim/lazy-lock.json`；安装脚本执行 `Lazy restore`，不会主动升级到最新版本。手动更新可在编辑器中运行 `:Lazy`，更新锁文件后一起提交。要求 Neovim 0.11.2+、Git 2.19+、C 编译器（macOS Command Line Tools）、以及可访问 GitHub/npm 的网络。macOS 剪贴板使用系统工具。

Go 使用 `gopls`；TS/React 与 Tailwind 使用锁定 npm 依赖，安装位置是 `~/.local/share/mate-code-tools`。项目自身依赖仍需按项目说明安装；Tailwind v4 项目应有导入 Tailwind 的 CSS 入口。Mason 可用于额外语言工具，首次打开某类文件可能继续下载解析器或附加工具。

Git 审阅要求当前目录属于 Git 仓库；远端 commit 查找可能执行 fetch（最多约 120 秒），需要当前用户自己的访问权限。不会切换分支或改动工作文件。CNB CLI 已登录时可作为凭据来源，但安装不携带或创建任何账号凭据。

排查编辑器问题可运行 `:checkhealth`、`:Lazy`、`:Mason`。仅安装编辑器但没有插件时，先恢复锁定插件：

```bash
nvim --headless '+Lazy! restore' +qa
```

## NVM 说明

配置兼容两种安装来源：

- 标准 NVM 目录：`$NVM_DIR/nvm.sh`，默认是 `~/.nvm/nvm.sh`。
- Homebrew NVM：`$(brew --prefix nvm)/nvm.sh`。

这样即使 Homebrew 未来升级 Cellar 路径，配置仍通过稳定的 `brew --prefix nvm` 查找。Node 版本和全局包都留在本机；不同用户可以自行选择：

```bash
nvm install --lts
nvm alias default 'lts/*'
nvm ls
```

## 自定义配置

所有文件都是普通文本，可以直接编辑：

```bash
$EDITOR config/zsh/.zshrc
$EDITOR config/ghostty/config
$EDITOR config/herdr/config.toml
$EDITOR config/nvim/lua/config/options.lua
```

修改后，运行 `exec zsh -l` 重新加载 zsh；Ghostty 和 Herdr 重新打开窗口后读取配置。保持配置中的路径使用 `$HOME` 或命令探测，避免把某一台机器的用户名、磁盘路径和应用版本写进仓库。

## 故障排查

### `nvm: command not found`

先确认 Homebrew NVM 存在，再重新执行安装：

```bash
brew install nvm
mkdir -p ~/.nvm
./install.sh
exec zsh -l
nvm --version
```

### Oh My Zsh 插件报错

删除不完整的插件目录后重跑安装：

```bash
rm -rf "$HOME/.oh-my-zsh/custom/plugins/zsh-autosuggestions" \
       "$HOME/.oh-my-zsh/custom/plugins/zsh-syntax-highlighting"
./install.sh
```

### 想恢复安装前的配置

从最近一次备份恢复，例如：

```bash
ls -la ~/.local/state/echin-dotfiles/backups
mv ~/.zshrc ~/.zshrc.dotfiles-link
cp ~/.local/state/echin-dotfiles/backups/<时间戳>/.zshrc ~/.zshrc
```

Ghostty 和 Herdr 使用相同的备份目录规则。恢复后重新打开对应应用即可。

### 配置链接被手动删除

再次执行 `./install.sh` 即可恢复；脚本是幂等的，已经正确链接的文件不会重复备份。

## 验证范围

在 macOS Apple Silicon、Neovim 0.12.6 上以隔离 HOME 和全新的 XDG 插件/缓存目录验证插件下载和无界面启动；检查了自定义 Lua 模块、配置备份、目录链接及重复安装。Intel 和 Linux 未做实机验收；Linux 不属于本安装脚本的完整应用安装范围。

离线检查安装逻辑：

```bash
python3 scripts/test-install.py
```

安装依赖后检查实际环境：

```bash
./doctor.sh
```

`doctor.sh` 遇到缺失的 NeoVim、语言服务、自定义模块或配置链接会返回 1；其他组件的提示会显示为警告。无界面检查覆盖启动和模块加载，鼠标交互、具体项目的 LSP 结果仍需在对应项目中使用确认。

## 安全边界

请不要把以下内容加入仓库：

- `~/.zsh_history`、Herdr `session.json`、`session-snapshots/` 和日志；
- `.env`、API key、Token、SSH 私钥、云服务凭据；
- 带有真实用户名、绝对路径或公司内部地址的本机专属配置。

提交前可以运行：

```bash
git status --short
git grep -nE 'AKIA|ghp_|github_pat_|BEGIN (OPENSSH|RSA|EC) PRIVATE KEY|api[_-]?key|token' -- . ':!README.md'
```

上面的检查没有匹配并不等于完成安全审查；新配置仍应人工确认。

## 许可证

本仓库自有脚本使用 MIT。`config/nvim/` 基于 LazyVim starter，保留其 [Apache-2.0 许可证](config/nvim/LICENSE)；下载的第三方插件与依赖遵循各自许可证。
