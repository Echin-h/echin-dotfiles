# echin-dotfiles

一套可迁移的 macOS 终端配置，包含：

- **zsh + Oh My Zsh**：`robbyrussell` 主题、Git/`extract`/目录跳转插件，以及可选的自动建议和语法高亮。
- **Ghostty**：TokyoNight 配色、JetBrainsMono Nerd Font、14px 字号、窗口内边距、静音铃声和 Cmd 快捷键映射。
- **Herdr**：终端复用器的稳定主题配置。你提到的 “Header” 按本机实际安装的 **Herdr** 处理，配置目录是 `~/.config/herdr`。
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

1. 检查系统并在可用时使用 Homebrew 安装 `nvm`、`herdr`、zsh 插件、Ghostty 和 JetBrainsMono Nerd Font。
2. 没有 Oh My Zsh 时，以浅克隆方式安装；再安装自动建议和语法高亮插件。
3. 创建 `~/.nvm`，把配置文件以符号链接方式接入用户目录。
4. 默认安装 Node.js LTS，并设置为 NVM 默认版本。
5. 如果目标文件已经存在，先移动到 `~/.local/state/echin-dotfiles/backups/<时间戳>/`，再创建链接。

打开新终端，或者执行：

```bash
exec zsh -l
```

检查配置是否正确：

```bash
./doctor.sh
```

`doctor.sh` 会验证符号链接和 zsh 语法，并报告 NVM、Node.js、Ghostty、Herdr 是否可用。

## 安装选项

跳过 Homebrew、应用和插件安装，只接入配置文件：

```bash
./install.sh --skip-deps
```

安装 NVM 但不自动安装 Node.js LTS：

```bash
./install.sh --skip-node
```

两个选项可以组合。脚本也接受等价环境变量：

```bash
DOTFILES_SKIP_DEPENDENCIES=1 DOTFILES_SKIP_NODE=1 ./install.sh
```

如果系统没有 Homebrew，脚本不会强行执行官方安装器，而是保留配置链接并给出提示；安装 Homebrew 后重新执行即可。Homebrew 官方安装方式见 <https://brew.sh>。

## 文件结构

```text
config/
├── ghostty/config       # ~/.config/ghostty/config
├── herdr/config.toml    # ~/.config/herdr/config.toml
└── zsh/
    ├── .zprofile        # ~/.zprofile
    └── .zshrc           # ~/.zshrc
install.sh               # 幂等安装和备份
doctor.sh                # 本地健康检查
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

MIT。你可以自由复制和修改这套配置。
