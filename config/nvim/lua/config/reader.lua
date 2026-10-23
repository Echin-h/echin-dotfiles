local M = {}
local hover_win
local generation = 0
local last_mouse = ""

local function close_hover()
  if hover_win and vim.api.nvim_win_is_valid(hover_win) then
    vim.api.nvim_win_close(hover_win, true)
  end
  hover_win = nil
end

local function mouse_target(allow_gutter)
  local mouse = vim.fn.getmousepos()
  if mouse.winid == 0 or mouse.line < 1 then
    return
  end
  if not vim.api.nvim_win_is_valid(mouse.winid) or vim.api.nvim_win_get_config(mouse.winid).relative ~= "" then
    return
  end
  local buf = vim.api.nvim_win_get_buf(mouse.winid)
  if vim.bo[buf].buftype ~= "" and not require("config.navigation").is_review_buffer(buf) then
    return
  end
  -- Gutter positions do not identify a text column. Resolve their buffer line
  -- before applying symbol/whitespace filtering used by code navigation.
  local info = vim.fn.getwininfo(mouse.winid)[1]
  local gutter = info and mouse.wincol > 0 and mouse.wincol <= info.textoff
  if gutter then
    if allow_gutter then
      return { win = mouse.winid, buf = buf, line = mouse.line, col = 1, gutter = true }
    end
    return
  end
  if mouse.column < 1 then
    return
  end
  local line = vim.api.nvim_buf_get_lines(buf, mouse.line - 1, mouse.line, false)[1]
  if
    not line
    or mouse.column > #line
    or (
      line:sub(mouse.column, mouse.column):match("%s")
      and not require("config.links").find(line, mouse.column, false)
    )
  then
    return
  end
  return { win = mouse.winid, buf = buf, line = mouse.line, col = mouse.column, text = line }
end

local function at_mouse(action)
  local target = mouse_target()
  if not target then
    vim.notify("请点击函数名或符号名称后再跳转", vim.log.levels.INFO, { title = "代码导航" })
    return
  end
  close_hover()
  vim.api.nvim_set_current_win(target.win)
  vim.api.nvim_win_set_cursor(target.win, { target.line, target.col - 1 })
  action()
end

local function show_locations(options)
  vim.fn.setqflist({}, " ", options)
  vim.cmd.copen()
end

function M.definition()
  if require("config.links").at_cursor() then
    return
  end
  if require("config.review_context").definition() then
    return
  end
  require("config.navigation").definition()
end

function M.references()
  if require("config.review_context").references() then
    return
  end
  local source_win = vim.api.nvim_get_current_win()
  vim.lsp.buf.references(nil, {
    on_list = function(options)
      if vim.api.nvim_win_is_valid(source_win) then
        vim.api.nvim_set_current_win(source_win)
      end
      show_locations(options)
      vim.w.mate_results_origin = source_win
    end,
  })
end

function M.documentation()
  if require("config.review_context").documentation() then
    return
  end
  vim.lsp.buf.hover({ border = "rounded" })
end

local function scroll(key)
  if require("config.tabs").scroll(key) then
    return
  end
  local diffview = package.loaded["diffview.lib"]
  local view = diffview and diffview.get_current_view()
  local win = vim.fn.getmousepos().winid
  if view and view.cur_layout and (key == "<ScrollWheelDown>" or key == "<ScrollWheelUp>") then
    for _, pane in ipairs(view.cur_layout.windows) do
      if pane.id == win and vim.api.nvim_win_is_valid(win) then
        local lines = tonumber(vim.o.mousescroll:match("ver:(%d+)")) or 3
        if lines > 0 then
          local count = lines * vim.v.count1
          local tab = vim.api.nvim_get_current_tabpage()
          vim.schedule(function()
            if not vim.api.nvim_win_is_valid(win) or vim.api.nvim_get_current_tabpage() ~= tab then
              return
            end
            if vim.api.nvim_get_current_win() ~= win then
              local saved = vim.api.nvim_win_call(win, vim.fn.winsaveview)
              local top, bottom = vim.fn.line("w0", win), vim.fn.line("w$", win)
              local margin = vim.wo[win].scrolloff
              local first = math.min(bottom, top + margin)
              saved.lnum = math.min(math.max(saved.lnum, first), math.max(first, bottom - margin))
              vim.api.nvim_set_current_win(win)
              vim.fn.winrestview(saved)
            end
            local command = key == "<ScrollWheelDown>" and "<C-e>" or "<C-y>"
            vim.cmd.normal({ args = { tostring(count) .. vim.keycode(command) }, bang = true })
          end)
        end
        return
      end
    end
  end
  -- A hovered diff pane becomes active without jumping back to an off-screen
  -- cursor. Native scrollbind keeps matching diff blocks aligned.
  vim.cmd.normal({ args = { vim.keycode(key) }, bang = true })
end

local function show_mouse_diagnostics(target)
  local _, win = vim.diagnostic.open_float({
    bufnr = target.buf,
    scope = target.gutter and "line" or "cursor",
    pos = { target.line - 1, target.col - 1 },
    border = "rounded",
    relative = "mouse",
    focusable = false,
    focus = false,
    source = true,
    severity_sort = true,
    header = { "诊断 · 第 " .. target.line .. " 行", "Title" },
    format = function(diagnostic)
      local severity = ({ "错误", "警告", "信息", "提示" })[diagnostic.severity] or "诊断"
      return severity .. ": " .. diagnostic.message
    end,
    max_width = 88,
    max_height = 22,
    close_events = { "CursorMoved", "BufLeave", "InsertEnter" },
  })
  if win then
    hover_win = win
    return true
  end
  return false
end

local function hover_mouse()
  local diffview = package.loaded["diffview.lib"]
  if diffview and diffview.get_current_view() then
    generation = generation + 1
    last_mouse = ""
    close_hover()
    return
  end
  local target = mouse_target(true)
  local key = target and (target.win .. ":" .. target.line .. ":" .. (target.gutter and "gutter" or target.col)) or ""
  if key == last_mouse then
    return
  end
  last_mouse = key
  generation = generation + 1
  local ticket = generation
  close_hover()
  if not target or vim.api.nvim_get_mode().mode ~= "n" then
    return
  end
  local tick = vim.api.nvim_buf_get_changedtick(target.buf)
  vim.defer_fn(function()
    if
      ticket ~= generation
      or not vim.api.nvim_buf_is_valid(target.buf)
      or vim.api.nvim_buf_get_changedtick(target.buf) ~= tick
    then
      return
    end
    if not vim.api.nvim_win_is_valid(target.win) then
      return
    end
    local shown = vim.api.nvim_win_call(target.win, function()
      return show_mouse_diagnostics(target)
    end)
    if shown or target.gutter then
      return
    end
    local clients = vim.lsp.get_clients({ bufnr = target.buf, method = "textDocument/hover" })
    table.sort(clients, function(a, b)
      return a.name == "tailwindcss" and b.name ~= "tailwindcss"
    end)
    local function request(index)
      local client = clients[index]
      if not client or ticket ~= generation then
        return
      end
      local params = {
        textDocument = { uri = vim.uri_from_bufnr(target.buf) },
        position = {
          line = target.line - 1,
          character = vim.str_utfindex(target.text, client.offset_encoding, target.col - 1, false),
        },
      }
      client:request("textDocument/hover", params, function(err, result)
        if
          ticket ~= generation
          or not vim.api.nvim_win_is_valid(target.win)
          or not vim.api.nvim_buf_is_valid(target.buf)
          or vim.api.nvim_buf_get_changedtick(target.buf) ~= tick
        then
          return
        end
        if err or not result or not result.contents then
          request(index + 1)
          return
        end
        local lines = vim.lsp.util.convert_input_to_markdown_lines(result.contents)
        if #lines == 0 then
          request(index + 1)
          return
        end
        vim.api.nvim_win_call(target.win, function()
          local _, win = vim.lsp.util.open_floating_preview(lines, "markdown", {
            border = "rounded",
            relative = "mouse",
            focusable = false,
            focus = false,
            max_width = 70,
            max_height = 18,
            close_events = { "CursorMoved", "BufLeave", "InsertEnter" },
          })
          hover_win = win
        end)
      end, target.buf)
    end
    request(1)
  end, 450)
end

function M.help()
  local lines = {
    "# Mate Code · 鼠标阅读指南",
    "",
    "- 目录树：单击展开目录 / 打开文件。滚轮阅读。",
    "- 函数定义：Ctrl + 左键；或点击函数后点击顶部定义。",
    "- 文档路径：单击 Markdown 文件链接/反引号路径；Ctrl+单击路径也可打开。相对当前文件目录。",
    "- 查找引用：点击函数后点击引用；单击结果打开，Esc / q 或「关闭结果」收起列表。",
    "- 返回 / 前进：顶部后退 / 前进，恢复上一处阅读的文件和位置。",
    "- 错误详情：悬停左侧红叉/警告或代码报错位置 450ms，显示错误、来源和错误码。",
    "- CSS / 函数说明：鼠标停留 450ms；或点击顶部文档 / 按 K。",
    "- Git review：顶部 Git 打开 diff；:DiffviewClose 返回代码。",
    "- 文件搜索：Space Space；全文搜索：Space /；点击「关闭」或弹窗外关闭。",
    "- Worktree：点击顶部 Worktree 或 Space g w，选择后保留原页及未保存内容。",
    "- 审阅：mreview 查看整体改动，顶部「提交历史」选择提交。",
    "- 滚轮每次 2 行；diff 新增/修改为绿色，删除为红色。",
    "- 切换目录树：Space e；Git 管理：Space g g。",
    "- 复制给 agent：选中代码后点右键 → Copy selection。",
    "- 复制位置：右键 → Copy file:line（或 Space y p）。",
    "- 退出：点击顶部「退出」，或 Esc 后输入 :qa 回车。修改后用 :w 保存。",
    "",
    "普通文件编辑后自动保存；自动格式化关闭，历史快照只读。",
    "若终端拦截 Ctrl+点击，使用顶部定义。",
  }
  local lib = package.loaded["diffview.lib"]
  if (lib and lib.get_current_view()) or vim.b.mate_review_snapshot or vim.env.MATE_REVIEW_MODE then
    lines = {
      "# mreview · 审阅指南",
      "",
      "- 审阅范围：顶部「整体改动 / 提交历史」；选择提交不会新增审阅标签。",
      "- 提交历史：每次加载 20 条，单击 / 回车选择；底部继续加载，Esc / q 关闭列表。",
      "- 版本：代码栏显示旧版 / 新版和 SHA；点击对应代码后，目录和上下文查询沿用该版本。",
      "- 文件导航：左栏「改动文件 / 完整目录」；单击文件预览。",
      "- 代码上下文：定义 gd、引用 gr、大纲 Space r o、文档 K。",
      "- 预览：单击或上下选择更新；回车 /「打开阅读」进入完整代码，Esc / q 关闭预览。",
      "- 目录：Space r e；目录内回车打开阅读，引用列表 t 定位相邻文件。",
      "- 阅读历史：后退 / mm / Command+[ 逐层返回，前进 / Command+] 前进。",
      "- 返回审阅：阅读页按钮 / gR 直接返回原 Diff、光标和滚动位置。",
      "- 快捷入口：Space r h 提交历史，Space r a 整体改动，Space r f 改动文件。",
      "- 更多：复制位置、切换 Worktree、文件搜索、全文搜索；Space r m 打开。",
      "- 退出审阅：顶部按钮；从 mcode 进入时关闭审阅并返回代码。",
      "",
      "历史代码和预览只读；不切换分支，不改工作区。缺少语言服务时会提示。",
    }
  end
  vim.lsp.util.open_floating_preview(
    lines,
    "markdown",
    { border = "rounded", focus_id = "mate-code-help", max_width = 78 }
  )
end

function M.copy_location()
  local name = vim.fn.fnamemodify(vim.api.nvim_buf_get_name(0), ":.")
  local location = name .. ":" .. vim.api.nvim_win_get_cursor(0)[1]
  vim.fn.setreg("+", location)
  vim.notify("Copied " .. location)
end

function M.shutdown()
  local links = package.loaded["config.links"]
  if links and links.shutdown then
    links.shutdown()
  end
  generation = generation + 1
  last_mouse = ""
  close_hover()
end

function M.setup()
  require("config.navigation").setup()
  require("config.results").setup()
  require("config.worktrees").setup()
  require("config.links").setup()
  require("config.review_context").setup()
  require("config.review_tree").setup()
  require("config.review_workspace").setup()
  local map = vim.keymap.set
  map("n", "<C-LeftMouse>", function()
    at_mouse(M.definition)
  end, { desc = "Click: go to definition" })
  map("n", "<C-RightMouse>", function()
    at_mouse(M.references)
  end, { desc = "Click: find references" })
  map("n", "<MouseMove>", hover_mouse, { desc = "Mouse hover diagnostics or documentation" })
  map({ "n", "x" }, "<ScrollWheelDown>", function()
    scroll("<ScrollWheelDown>")
  end, { desc = "Scroll and synchronize diff panes" })
  map({ "n", "x" }, "<ScrollWheelUp>", function()
    scroll("<ScrollWheelUp>")
  end, { desc = "Scroll and synchronize diff panes" })
  map({ "n", "x" }, "<ScrollWheelLeft>", function()
    scroll("<ScrollWheelLeft>")
  end, { desc = "Scroll tabs or code left" })
  map({ "n", "x" }, "<ScrollWheelRight>", function()
    scroll("<ScrollWheelRight>")
  end, { desc = "Scroll tabs or code right" })
  map("n", "<leader>yp", M.copy_location, { desc = "Copy file:line for agent" })
  map("n", "<F1>", M.help, { desc = "Mouse reading guide" })
  map("n", "gd", M.definition, { desc = "Go to definition" })
  map("n", "gr", M.references, { desc = "Find references" })
  map("n", "<leader>re", function()
    require("config.review_context").tree()
  end, { desc = "Review version directory" })
  map("n", "<leader>rh", function()
    require("config.review_commits").open()
  end, { desc = "提交历史" })
  map("n", "<leader>ra", function()
    require("config.review_commits").overall()
  end, { desc = "整体改动" })
  map("n", "<leader>rf", function()
    require("config.review_workspace").files()
  end, { desc = "改动文件" })
  map("n", "<leader>rm", function()
    require("config.review_workspace").more()
  end, { desc = "更多操作" })
  map("n", "<leader>ro", function()
    require("config.review_context").outline()
  end, { desc = "Review file outline" })
  map("n", "K", M.documentation, { desc = "文档 / CSS" })

  local actions = {
    function()
      require("config.navigation").back()
    end,
    function()
      require("config.navigation").forward()
    end,
    M.definition,
    M.references,
    M.documentation,
    function()
      vim.cmd.DiffviewOpen()
    end,
    M.help,
    function()
      vim.cmd("confirm qall")
    end,
    function()
      require("config.worktrees").pick()
    end,
    function()
      require("config.navigation").return_review()
    end,
    function()
      require("config.review_context").tree()
    end,
    function()
      require("config.review_context").outline()
    end,
  }
  _G.MateCodeToolbar = function(id)
    close_hover()
    local win = vim.fn.getmousepos().winid
    vim.schedule(function()
      if
        win ~= 0
        and vim.api.nvim_win_is_valid(win)
        and (
          vim.bo[vim.api.nvim_win_get_buf(win)].buftype == ""
          or require("config.navigation").is_review_buffer(vim.api.nvim_win_get_buf(win))
        )
      then
        vim.api.nvim_set_current_win(win)
      end
      actions[id]()
    end)
  end
  vim.opt.winbar =
    "%1@v:lua.MateCodeToolbar@ 后退 %X%2@v:lua.MateCodeToolbar@ 前进 %X%3@v:lua.MateCodeToolbar@ 定义 %X%4@v:lua.MateCodeToolbar@ 引用 %X%5@v:lua.MateCodeToolbar@ 文档 %X%6@v:lua.MateCodeToolbar@ Git %X%7@v:lua.MateCodeToolbar@ ? %X%9@v:lua.MateCodeToolbar@ Worktree %X%8@v:lua.MateCodeToolbar@ 退出 %X"

  local toolbar = vim.o.winbar
  vim.o.winbar = ""
  local function update_toolbar()
    if vim.bo.filetype == "DiffviewFiles" or vim.bo.filetype == "DiffviewFileHistory" then
      require("config.review_workspace").refresh()
      return
    end
    if vim.bo.filetype == "qf" then
      require("config.results").decorate()
      return
    end
    if vim.w.mate_review_preview or vim.bo.filetype:match("^mate_review_") then
      return
    end
    local diffview = package.loaded["diffview.lib"]
    if diffview and diffview.get_current_view() then
      local pane_win = false
      local layout = diffview.get_current_view().cur_layout
      for _, pane in ipairs(layout and layout.windows or {}) do
        if pane.id == vim.api.nvim_get_current_win() then
          pane_win = true
        end
      end
      if pane_win and require("config.review_navigation").context(vim.api.nvim_get_current_buf()) then
        vim.t.mate_review_code_win = vim.api.nvim_get_current_win()
      end
      require("config.review_workspace").refresh()
      return
    end
    local snapshot = vim.b.mate_review_snapshot
    if snapshot then
      vim.wo.winbar = "%10@v:lua.MateCodeToolbar@ 返回审阅 %X%1@v:lua.MateCodeToolbar@ 后退 %X%2@v:lua.MateCodeToolbar@ 前进 %X%3@v:lua.MateCodeToolbar@ 定义 %X%4@v:lua.MateCodeToolbar@ 引用 %X%12@v:lua.MateCodeToolbar@ 大纲 %X%5@v:lua.MateCodeToolbar@ 文档 %X  历史 "
        .. snapshot.revision:sub(1, 8)
    else
      vim.wo.winbar = vim.bo.buftype == "" and toolbar or ""
    end
  end
  local group = vim.api.nvim_create_augroup("MateCodeReader", { clear = true })
  local function definition_key(buf)
    if
      require("config.navigation").is_review_buffer(buf)
      or #vim.lsp.get_clients({ bufnr = buf, method = "textDocument/definition" }) > 0
    then
      map("n", "gd", M.definition, { buffer = buf, desc = "Go to definition" })
      map("n", "gr", M.references, { buffer = buf, desc = "Find references" })
    end
  end
  vim.api.nvim_create_autocmd("LspAttach", {
    group = group,
    callback = function(event)
      definition_key(event.buf)
    end,
  })
  for _, buf in ipairs(vim.api.nvim_list_bufs()) do
    definition_key(buf)
  end
  vim.api.nvim_create_autocmd({ "BufEnter", "FileType" }, {
    group = group,
    callback = function(event)
      definition_key(event.buf)
      if vim.b[event.buf].mate_review_snapshot then
        map("n", "mm", function()
          require("config.navigation").back()
        end, { buffer = event.buf, desc = "Return to review" })
        map("n", "<C-o>", function()
          require("config.navigation").back()
        end, { buffer = event.buf, desc = "Return to review" })
      end
    end,
  })
  vim.api.nvim_create_autocmd("User", {
    group = group,
    pattern = "MateReviewSnapshot",
    callback = function(event)
      local buf = event.data and event.data.buf or vim.api.nvim_get_current_buf()
      definition_key(buf)
      map("n", "mm", function()
        require("config.navigation").back()
      end, { buffer = buf, desc = "Return to review" })
      map("n", "<C-o>", function()
        require("config.navigation").back()
      end, { buffer = buf, desc = "Return to review" })
      if vim.api.nvim_get_current_buf() == buf then
        update_toolbar()
      end
    end,
  })
  vim.api.nvim_create_autocmd({ "WinEnter", "BufWinEnter" }, { group = group, callback = update_toolbar })
  vim.api.nvim_create_autocmd("User", {
    group = group,
    pattern = "DiffviewDiffBufWinEnter",
    callback = function()
      vim.schedule(function()
        local lib = package.loaded["diffview.lib"]
        local view = lib and lib.get_current_view()
        if view and view.cur_layout then
          for _, pane in ipairs(view.cur_layout.windows) do
            if pane.id and vim.api.nvim_win_is_valid(pane.id) then
              vim.api.nvim_win_call(pane.id, update_toolbar)
            end
          end
        end
      end)
    end,
  })
  for _, win in ipairs(vim.api.nvim_list_wins()) do
    vim.api.nvim_win_call(win, update_toolbar)
  end
  vim.api.nvim_create_autocmd("FileType", {
    group = group,
    pattern = { "qf", "snacks_picker_list" },
    callback = function(event)
      if vim.bo[event.buf].filetype == "qf" then
        local select_result = function()
          if not require("config.navigation").select_definition() then
            vim.cmd.normal({ args = { "\r" }, bang = true })
          end
        end
        map("n", "<LeftRelease>", select_result, { buffer = event.buf, desc = "Click to open result" })
        map("n", "<CR>", select_result, { buffer = event.buf, desc = "Open result" })
        require("config.results").decorate()
      else
        map("n", "<LeftRelease>", "<CR>", { buffer = event.buf, remap = true, desc = "Click to open result" })
      end
      if vim.bo[event.buf].filetype ~= "qf" then
        vim.opt_local.winbar = ""
      end
    end,
  })
  vim.api.nvim_create_autocmd("FileType", {
    group = group,
    pattern = { "neo-tree", "lazy", "mason", "snacks_dashboard", "help" },
    callback = function()
      vim.opt_local.winbar = ""
    end,
  })
  vim.api.nvim_create_autocmd({ "InsertEnter", "BufLeave", "WinLeave" }, {
    group = group,
    callback = function()
      generation = generation + 1
      last_mouse = ""
      close_hover()
    end,
  })
  vim.cmd([[amenu PopUp.定义 <Cmd>lua require('config.reader').definition()<CR>]])
  vim.cmd([[amenu PopUp.引用 <Cmd>lua require('config.reader').references()<CR>]])
  vim.cmd([[amenu PopUp.文档 <Cmd>lua require('config.reader').documentation()<CR>]])
  vim.cmd([[amenu PopUp.复制位置 <Cmd>lua require('config.reader').copy_location()<CR>]])
  vim.cmd([[vmenu PopUp.复制选区 "+y]])
  vim.cmd([[amenu PopUp.审阅改动 <Cmd>DiffviewOpen<CR>]])
  vim.cmd([[amenu PopUp.操作指南 <Cmd>lua require('config.reader').help()<CR>]])
end

return M
