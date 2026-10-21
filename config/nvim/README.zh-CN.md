# Herdr 代码阅读工作区

在项目目录运行 `mcode .`；review 使用 `mreview`。
`mcode path/to/file.tsx` 可直接打开文件；命令也支持 Neovim 的 `+行号` 参数。

`mreview` 默认打开 PR 整体 diff：主分支与当前分支的共同祖先 → 当前分支 HEAD。
`mreview feature/name` 默认列出目标分支最近 5 个 commit，最新一次自动选中，点击「展开 / 收起」控制列表；`mreview A B` 或 `mreview A..B` 直接比较两个版本的完整快照。
`mreview A...B` 使用 PR 的共同祖先比较方式。左侧列出改动文件，左右代码区显示对应版本 SHA。
`mreview --history` 保留提交浏览，默认选中最新 commit；单击其他 commit 或文件切换。
`mreview --history origin/main..HEAD` 只列出该范围内的 commits。
默认基准优先使用 origin/HEAD，可通过 MATE_REVIEW_BASE 指定。
`mreview HASH` 或 `mreview --commit HASH` 查看单次提交（父提交 → 该提交，支持首次提交和 merge 的第一父提交）。
若 hash 不在本地，会依次查询已配置 remote（优先 origin）的分支、标签、PR 引用及历史；浅克隆会补全历史。短 hash 须唯一，建议需要时使用完整 hash。CNB 遇到系统钥匙串旧凭据遮蔽时，会仅对本次请求尝试现有 CNB CLI 登录，不修改全局 Git 配置或钥匙串；不切换分支、不改工作文件。
点击左侧文件/提交列表顶部的「退出」即可退出 `mreview`；在 `mcode` 内打开 diff 时，该按钮为「关闭 diff」，点击返回代码。
也可以用 `:DiffviewClose` 退出视图，或用 `:qa` 退出编辑器。
diff 新增行、修改行以绿色底色标出，修改字符使用更亮绿色，删除使用红色；左侧统计显示 `+新增行数 -删除行数`。review 不自动弹出 hover。
滚轮每次滚动 2 行。左右 diff 代码区滚轮同步：滚动鼠标所在的一侧时，另一侧按对应代码对齐；有新增/删除时，两边行号可能不同。

- 目录树：单击目录展开/折叠，单击文件打开。状态图标已恢复原样。
- 顶部文件标签：空白、未命名且未修改的启动页自动隐藏；输入内容后恢复显示。鼠标放在标签栏上，双指左右滑动浏览隐藏标签；当前文件、光标和代码视图保持不变。点击标签才切换文件。
- 函数跳转：`gd` / Ctrl+左键；也可以点击函数，再点顶部 Go。
- 历史 review 定义：查询所读 commit 的隔离代码快照，结果在只读历史标签打开，显示 SHA；Back / `mm` 返回原 diff，Next 可前进。支持 Go、TS/JS/React，缺少依赖或不支持的文件会提示。
- Worktree：点击顶部 Worktree，或 `Space g w`；原生列表支持上下键、j/k、Ctrl-j/k 选择，回车或单击切换；Esc / q 或点击「关闭」退出列表。编辑内容保留，普通文件自动保存；已打开的 worktree 直接返回原页。
- 阅读返回/前进：顶部 Back / Next，恢复上一处文件、光标和阅读位置（包括打开文件和函数跳转）。
- Command + `[` / Command + `【` 与当前页面的 `mm` 完全一致（历史定义页返回 review）。普通代码 `mm` / Ctrl-o 返回 Vim 跳转历史，Ctrl-i 前进；插入时 `jj` 退出插入。H 到行首，L 到行尾。
- 定义查找失败会提示未找到、语言服务不可用或查询超时；失败不会增加返回记录。
- 引用：顶部 Refs；结果列表可单击打开。按 Esc / q，或点击列表顶部「关闭结果」收起列表并回到代码。
- CSS/文档：鼠标停留 450ms；或点顶部 Info / 按 K。
- Git diff：顶部 Git；`:DiffviewClose` 退出 diff。
- 文件查找：Space Space；全文搜索：Space /；点击搜索弹窗的「关闭」或外部关闭，原有 Esc、恢复搜索、回车打开保留。目录树：Space e。
- 右键菜单：定义、引用、说明、复制位置、Git diff、阅读指南。
- 选中代码后：右键 Copy selection；复制路径行号用 Space y p。
- F1 或顶部 ?：打开操作说明。
- 点击顶部工具栏的「退出」关闭 `mcode`；有未保存修改时会询问是否保存。也可以 Esc 后 `:qa` 回车退出。`:w` 保存当前文件。

普通可编辑文件自动保存：停止输入约 800ms、退出插入、切换文件或失去焦点时写入。未命名文件、只读文件和历史快照不自动保存。自动格式化保持关闭；写入失败会提示并保留编辑内容。

诊断文字默认不显示在代码行尾或额外行中；函数跳转、引用查找和诊断数据仍可用。需要时用 `:lua vim.diagnostic.open_float()` 查看当前行的诊断说明。

Go 使用已有 gopls；TS/JS/React 使用 vtsls；Tailwind 使用官方 language server。
Tailwind v4 需要项目安装依赖，并有导入 Tailwind 的 CSS 入口；多项目可按官方设置指定入口。
工具安装在 ~/.local/share/mate-code-tools，插件版本记录在 lazy-lock.json。
`:Lazy` 管理插件；`:Mason` 管理附加语言工具；`:checkhealth` 查看环境。

字体为 JetBrainsMono Nerd Font；旧配置由仓库安装脚本备份到 `~/.local/state/echin-dotfiles/backups/`。
Herdr 右键若打开其自身菜单，可将阅读分屏的 right-click 路由设为 pane。
鼠标停留依赖终端转发 mouse-move；若未转发，点击类名后用 Info 始终可用。
本配置只复制选区/文件位置到剪贴板，不会自动给 agent 发消息。

Markdown 行内反引号代码保留文字颜色，不显示单独的彩色底。

文档中的 Markdown 文件链接、反引号路径和 `../` 相对路径可单击打开，路径相对当前文档目录解析。也可将光标放在路径上点 Go / 按 gd / Ctrl+左键；普通函数仍使用定义跳转。支持 `#L数字` / `:行号`，不存在的文件只提示，不会创建空文件。历史 review 读取对应提交的只读文件，Back / mm / Command+[ 返回。
Ghostty 默认 Command+[ 用于切换分屏；已覆盖为向 Neovim 转发返回键（兼容 Command+【 和物理左方括号）。修改终端配置后按 Command+Shift+, 重载 Ghostty，无需关闭会话。

Command + `]` / Command + `】` 前进，与 Command + `[` / Command + `【` 返回配对。普通文件使用原生 Ctrl-i 跳转历史；历史快照和 review 使用顶部 Next 对应的阅读历史。Ghostty 配置新增右括号转发后，按 Command+Shift+, 重载终端配置。
