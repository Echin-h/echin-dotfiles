local M = {}
local picker
local picker_ns = vim.api.nvim_create_namespace("MateWorktreePicker")

_G.MateWorktreeClose = function()
  if picker and picker.close then
    picker.close(true)
  end
end

local function canonical(path)
  return vim.uv.fs_realpath(path) or vim.fs.normalize(path)
end

local function git(path, args, binary)
  local command = { "git", "-C", path }
  vim.list_extend(command, args)
  local result = vim.system(command, { text = not binary }):wait()
  if result.code ~= 0 then
    return nil, vim.trim(result.stderr or "Git 查询失败")
  end
  return result.stdout
end

local function context()
  local lib = package.loaded["diffview.lib"]
  local view = lib and lib.get_current_view()
  if view then
    return view.adapter.ctx.toplevel, view.cur_entry and view.cur_entry.absolute_path
  end
  local file = vim.api.nvim_buf_get_name(0)
  local directory = vim.bo.buftype == "" and file ~= "" and vim.fs.dirname(file) or vim.fn.getcwd()
  local root, err = git(directory, { "rev-parse", "--show-toplevel" })
  return root and vim.trim(root), file, err
end

function M.list(root)
  local output, err = git(root, { "worktree", "list", "--porcelain", "-z" }, true)
  if not output then
    return nil, err
  end
  local items, current = {}, nil
  for _, field in ipairs(vim.split(output, "\0", { plain = true })) do
    if field:sub(1, 9) == "worktree " then
      current = { path = field:sub(10) }
      items[#items + 1] = current
    elseif current then
      if field:sub(1, 7) == "branch " then
        current.branch = field:sub(8):gsub("^refs/heads/", "")
      elseif field:sub(1, 5) == "HEAD " then
        current.commit = field:sub(6)
      elseif field == "bare" then
        current.bare = true
      end
    end
  end
  return vim.tbl_filter(function(item)
    local stat = vim.uv.fs_stat(item.path)
    return not item.bare and stat and stat.type == "directory"
  end, items)
end

function M.open(path)
  local stat = vim.uv.fs_stat(path)
  if not stat or stat.type ~= "directory" then
    vim.notify("Worktree 目录已不可用：" .. path, vim.log.levels.WARN)
    return false
  end
  local source, file = context()
  source = source and canonical(source)
  file = file and canonical(file)
  local destination = canonical(path)
  local lib = package.loaded["diffview.lib"]
  if source and not (lib and lib.get_current_view()) then
    vim.t.mate_worktree_root = canonical(source)
  end
  for _, tab in ipairs(vim.api.nvim_list_tabpages()) do
    if vim.t[tab].mate_worktree_root == destination then
      vim.api.nvim_set_current_tabpage(tab)
      return true
    end
  end
  local relative = source and file and file:sub(1, #source + 1) == source .. "/" and file:sub(#source + 2) or nil
  vim.cmd.tabnew()
  vim.api.nvim_cmd({ cmd = "tcd", args = { path } }, {})
  vim.t.mate_worktree_root = destination
  local counterpart = relative and vim.fs.joinpath(path, relative)
  local counterpart_stat = counterpart and vim.uv.fs_stat(counterpart)
  if counterpart_stat and counterpart_stat.type == "file" then
    vim.api.nvim_cmd({ cmd = "edit", args = { counterpart } }, {})
  end
  require("neo-tree.command").execute({
    action = "show",
    source = "filesystem",
    position = "left",
    dir = path,
    reveal_file = counterpart_stat and counterpart or nil,
  })
  return true
end

function M.pick()
  if picker and vim.api.nvim_win_is_valid(picker.win) then
    vim.api.nvim_set_current_win(picker.win)
    return
  end
  local root, _, failure = context()
  if not root then
    vim.notify("当前目录不属于 Git 仓库：" .. (failure or ""), vim.log.levels.WARN)
    return
  end
  local items, err = M.list(root)
  if not items then
    vim.notify(err, vim.log.levels.WARN)
    return
  end
  if #items == 0 then
    vim.notify("没有可用的 Worktree", vim.log.levels.INFO)
    return
  end

  local origin =
    { win = vim.api.nvim_get_current_win(), buf = vim.api.nvim_get_current_buf(), view = vim.fn.winsaveview() }
  local lines = { " [ 关闭 × ]   ↑↓ / j k / Ctrl-j k 选择 · 回车或单击打开", "" }
  local selected = 1
  for i, item in ipairs(items) do
    local current = canonical(item.path) == canonical(root)
    if current then
      selected = i
    end
    local label = item.branch or ("detached " .. (item.commit or ""):sub(1, 8))
    lines[i + 2] = string.format(" %s  %s  %s", current and "[当前]" or "      ", label, item.path)
  end
  local width = math.min(math.max(40, vim.o.columns - 6), 120)
  local height = math.min(#lines, math.max(3, vim.o.lines - 8))
  local buf = vim.api.nvim_create_buf(false, true)
  vim.bo[buf].bufhidden = "wipe"
  vim.bo[buf].filetype = "mate_worktrees"
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
  vim.bo[buf].modifiable = false
  local win = vim.api.nvim_open_win(buf, true, {
    relative = "editor",
    row = math.max(1, math.floor((vim.o.lines - height) / 2) - 1),
    col = math.max(0, math.floor((vim.o.columns - width) / 2)),
    width = width,
    height = height,
    style = "minimal",
    border = "rounded",
    title = " 切换 Worktree · 原页面保留 ",
    title_pos = "center",
  })
  local state = { win = win, buf = buf, origin = origin }
  picker = state
  vim.wo[win].cursorline = true
  vim.wo[win].wrap = false
  vim.wo[win].scrolloff = 1
  vim.wo[win].winhl = "Normal:NormalFloat,CursorLine:Visual"
  vim.api.nvim_buf_add_highlight(buf, picker_ns, "Special", 0, 1, 13)
  vim.api.nvim_win_set_cursor(win, { selected + 2, 0 })
  vim.cmd.stopinsert()

  local function close(restore_origin)
    if state.closed then
      return
    end
    state.closed = true
    if picker == state then
      picker = nil
    end
    if state.group then
      pcall(vim.api.nvim_del_augroup_by_id, state.group)
    end
    if vim.api.nvim_win_is_valid(win) then
      vim.api.nvim_win_close(win, true)
    end
    if restore_origin and vim.api.nvim_win_is_valid(origin.win) then
      vim.api.nvim_set_current_win(origin.win)
      if vim.api.nvim_buf_is_valid(origin.buf) and vim.api.nvim_win_get_buf(origin.win) == origin.buf then
        vim.fn.winrestview(origin.view)
      end
    end
  end
  state.close = close
  -- Keep a mouse exit visible even when a long worktree list scrolls its header away.
  vim.wo[win].winbar = "%@v:lua.MateWorktreeClose@ 关闭 × %X  ↑↓ / j k 选择 · 回车/单击打开"
  local function choose()
    local row = vim.api.nvim_win_get_cursor(win)[1]
    local item = items[row - 2]
    if not item then
      return
    end
    -- Resolve the relative counterpart in the original editor, never in this
    -- nofile buffer or its floating-window context.
    close(true)
    M.open(item.path)
  end
  local function move(delta)
    local row = vim.api.nvim_win_get_cursor(win)[1]
    vim.api.nvim_win_set_cursor(win, { math.max(3, math.min(#lines, row + delta)), 0 })
  end
  local function click()
    local mouse = vim.fn.getmousepos()
    if mouse.winid ~= win then
      return
    end
    if mouse.line == 1 then
      if mouse.column <= 13 then
        close(true)
      end
      return
    end
    if mouse.line >= 3 and mouse.line <= #lines then
      vim.api.nvim_win_set_cursor(win, { mouse.line, 0 })
      choose()
    end
  end
  local map = function(keys, action, desc)
    vim.keymap.set("n", keys, action, { buffer = buf, silent = true, nowait = true, desc = desc })
  end
  for _, key in ipairs({ "j", "<Down>", "<C-j>" }) do
    map(key, function()
      move(1)
    end, "Next worktree")
  end
  for _, key in ipairs({ "k", "<Up>", "<C-k>" }) do
    map(key, function()
      move(-1)
    end, "Previous worktree")
  end
  map("<CR>", choose, "Open selected worktree")
  map("<LeftRelease>", click, "Click worktree or close")
  map("<2-LeftMouse>", "<Nop>", "Use single click")
  map("<Esc>", function()
    close(true)
  end, "Close worktree list")
  map("q", function()
    close(true)
  end, "Close worktree list")
  state.group = vim.api.nvim_create_augroup("MateWorktreePicker" .. buf, { clear = true })
  vim.api.nvim_create_autocmd({ "WinLeave", "BufWipeout" }, {
    group = state.group,
    buffer = buf,
    once = true,
    callback = function()
      vim.schedule(function()
        close(false)
      end)
    end,
  })
end

function M.setup()
  vim.keymap.set("n", "<leader>gw", M.pick, { desc = "Switch worktree" })
  vim.api.nvim_create_user_command("MateWorktrees", M.pick, { force = true })
end

return M
