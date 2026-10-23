-- Browse Git's tree, not the checkout or dependencies linked into a snapshot.
local M = {}
local trees = {}
local cache = {}
local api = vim.api
local ns = api.nvim_create_namespace("MateReviewTree")

local function valid(win)
  return win and api.nvim_win_is_valid(win)
end
local function current()
  return trees[api.nvim_get_current_tabpage()]
end
local function notice(text)
  vim.notify(text, vim.log.levels.INFO, { title = "Review 目录" })
end

local function render(state)
  if not valid(state.win) then
    return
  end
  local lines, rows = {}, {}
  local function children(node, depth)
    local list = vim.tbl_values(node.children or {})
    table.sort(list, function(a, b)
      if (a.children ~= nil) ~= (b.children ~= nil) then
        return a.children ~= nil
      end
      return a.name:lower() < b.name:lower()
    end)
    for _, child in ipairs(list) do
      local status = state.changed[child.path] or " "
      local marker = child.children and (state.expanded[child.path] and "▾ " or "▸ ") or "  "
      lines[#lines + 1] = string.rep("  ", depth)
        .. marker
        .. status
        .. " "
        .. child.name
        .. (child.children and "/" or "")
      rows[#lines] = child
      if child.children and state.expanded[child.path] then
        children(child, depth + 1)
      end
    end
  end
  children(state.root, 0)
  if #lines == 0 then
    lines = { " 此版本没有文件" }
  end
  state.rows = rows
  vim.bo[state.buf].modifiable = true
  api.nvim_buf_set_lines(state.buf, 0, -1, false, lines)
  vim.bo[state.buf].modifiable = false
  api.nvim_buf_clear_namespace(state.buf, ns, 0, -1)
  for i, node in ipairs(rows) do
    local group = node.children and "Directory" or (state.changed[node.path] and "DiffviewFilePanelInsertions")
    if group then
      api.nvim_buf_add_highlight(state.buf, ns, group, i - 1, 0, -1)
    end
  end
  for i, node in ipairs(rows) do
    if node.path == state.context.path then
      api.nvim_win_set_cursor(state.win, { i, 0 })
      break
    end
  end
end

function M.close(restore)
  local state = current()
  if not state then
    return false
  end
  trees[state.tab] = nil
  state.token = nil
  if valid(state.win) then
    api.nvim_win_close(state.win, true)
  end
  if state.view and api.nvim_tabpage_is_valid(state.tab) then
    state.view.panel:open()
  end
  if restore ~= false and valid(state.source.win) then
    api.nvim_set_current_win(state.source.win)
  end
  return true
end

function M.select(open_reading)
  local state = current()
  if not state or not valid(state.win) then
    return
  end
  local row = api.nvim_win_get_cursor(state.win)[1]
  local node = state.rows[row]
  if not node then
    return
  end
  if node.children then
    state.expanded[node.path] = not state.expanded[node.path]
    state.context.path = node.path
    render(state)
    return
  end
  local token = {}
  state.token = token
  local context = vim.tbl_extend("force", state.context, { path = node.path })
  require("config.review_navigation").open_file(context, function(err, prepared)
    if current() ~= state or state.token ~= token then
      return
    end
    if err then
      notice(err)
      return
    end
    if state.floating then
      M.close(false)
    end
    require("config.review_context").show(state.source, context, "文件预览", {
      {
        snapshot = prepared.snapshot,
        encoding = "utf-8",
        location = {
          uri = vim.uri_from_bufnr(prepared.buf),
          range = { start = { line = 0, character = 0 }, ["end"] = { line = 0, character = 0 } },
        },
      },
    })
    if open_reading then
      require("config.review_context").open()
    end
  end)
end

local function build(paths)
  local root = { children = {} }
  for _, path in ipairs(paths) do
    local parts, node, prefix = vim.split(path, "/", { plain = true }), root, ""
    for i, name in ipairs(parts) do
      prefix = prefix == "" and name or prefix .. "/" .. name
      node.children[name] = node.children[name] or { name = name, path = prefix, children = i < #parts and {} or nil }
      node = node.children[name]
    end
  end
  return root
end

function M.open(context, source)
  require("config.review_commits").close(false)
  local tab = api.nvim_get_current_tabpage()
  local previous = current()
  if previous then
    M.close(false)
  end
  if not valid(source.win) then
    return
  end
  local lib = package.loaded["diffview.lib"]
  local view = lib and lib.tabpage_to_view(tab)
  local state =
    { tab = tab, context = vim.deepcopy(context), source = source, view = view, expanded = {}, changed = {} }
  trees[tab] = state
  local path = context.path
  while path and path ~= "." and path ~= "" do
    state.expanded[path] = true
    path = vim.fs.dirname(path)
  end
  if view and view.panel.ordered_file_list then
    for _, file in ipairs(view.panel:ordered_file_list() or {}) do
      state.changed[file.path] = file.status
      if file.oldpath then
        state.changed[file.oldpath] = file.status
      end
    end
  end
  local function show(root)
    if trees[tab] ~= state or api.nvim_get_current_tabpage() ~= tab or not valid(source.win) then
      return
    end
    state.root = root
    if view then
      view.panel:close()
    end
    api.nvim_set_current_win(source.win)
    state.buf = api.nvim_create_buf(false, true)
    if vim.o.columns < 110 then
      state.floating = true
      state.win = api.nvim_open_win(state.buf, true, {
        relative = "editor",
        row = 1,
        col = 1,
        width = math.min(42, vim.o.columns - 4),
        height = math.max(4, vim.o.lines - 6),
        border = "rounded",
        style = "minimal",
        title = " 完整目录 " .. context.revision:sub(1, 8) .. " ",
        title_pos = "center",
      })
    else
      vim.cmd("topleft 34vsplit")
      state.win = api.nvim_get_current_win()
      vim.wo[state.win].diff = false
      vim.wo[state.win].scrollbind = false
      vim.wo[state.win].cursorbind = false
      api.nvim_win_set_buf(state.win, state.buf)
    end
    vim.bo[state.buf].buftype = "nofile"
    vim.bo[state.buf].bufhidden = "wipe"
    vim.bo[state.buf].swapfile = false
    vim.bo[state.buf].buflisted = false
    vim.bo[state.buf].filetype = "mate_review_tree"
    for key, value in pairs({
      diff = false,
      scrollbind = false,
      cursorbind = false,
      number = false,
      relativenumber = false,
      wrap = false,
      signcolumn = "no",
      foldcolumn = "0",
      cursorline = true,
      winfixwidth = true,
    }) do
      vim.wo[state.win][key] = value
    end
    vim.wo[state.win].winbar = require("config.review_workspace").file_bar(true)
    local map = function(key, action)
      vim.keymap.set("n", key, action, { buffer = state.buf, silent = true, nowait = true })
    end
    map("<CR>", function()
      M.select(true)
    end)
    map("<2-LeftMouse>", function()
      M.select(true)
    end)
    map("<LeftRelease>", M.select)
    map("q", M.close)
    map("<Esc>", M.close)
    map("l", function()
      local node = state.rows[api.nvim_win_get_cursor(state.win)[1]]
      if node and node.children and state.expanded[node.path] then
        return
      end
      M.select()
    end)
    map("h", function()
      local node = state.rows[api.nvim_win_get_cursor(state.win)[1]]
      if not node then
        return
      end
      if node.children and state.expanded[node.path] then
        state.expanded[node.path] = false
        state.context.path = node.path
      else
        state.context.path = vim.fs.dirname(node.path)
        state.expanded[state.context.path] = false
      end
      render(state)
    end)
    render(state)
    if view and view.cur_layout and view.cur_layout.a and view.cur_layout.b then
      local a, b = view.cur_layout.a.id, view.cur_layout.b.id
      if valid(a) and valid(b) then
        local width = api.nvim_win_get_width(a) + api.nvim_win_get_width(b)
        api.nvim_win_set_width(a, math.floor(width / 2))
      end
    end
    require("config.review_context").resize()
  end
  local key = context.root .. ":" .. context.revision
  if cache[key] then
    show(cache[key])
    return
  end
  vim.system(
    { "git", "-C", context.root, "ls-tree", "-r", "--name-only", "-z", context.revision, "--" },
    {},
    function(result)
      vim.schedule(function()
        if trees[tab] ~= state then
          return
        end
        if result.code ~= 0 then
          trees[tab] = nil
          notice("无法读取该提交的目录：" .. result.stderr)
          return
        end
        local root = build(vim.split(result.stdout, "\0", { plain = true, trimempty = true }))
        -- Keep only the two most recently browsed versions, like the snapshot cache.
        if vim.tbl_count(cache) >= 2 then
          cache = {}
        end
        cache[key] = root
        show(root)
      end)
    end
  )
end

function M.setup()
  _G.MateReviewTreeClose = function(_, _, button)
    if button == "l" then
      vim.schedule(M.close)
    end
  end
  local group = api.nvim_create_augroup("MateReviewTree", { clear = true })
  api.nvim_create_autocmd("WinClosed", {
    group = group,
    callback = function(event)
      local state = current()
      if state and state.win == tonumber(event.match) then
        vim.schedule(M.close)
      end
    end,
  })
  api.nvim_create_autocmd("TabClosed", {
    group = group,
    callback = function()
      for tab in pairs(trees) do
        if not api.nvim_tabpage_is_valid(tab) then
          trees[tab] = nil
        end
      end
    end,
  })
  api.nvim_create_autocmd("VimResized", {
    group = group,
    callback = function()
      vim.schedule(function()
        local state = current()
        if state and valid(state.win) and (vim.o.columns < 110) ~= (state.floating == true) then
          M.open(state.context, state.source)
        elseif state and state.floating and valid(state.win) then
          api.nvim_win_set_config(
            state.win,
            { width = math.min(42, vim.o.columns - 4), height = math.max(4, vim.o.lines - 6) }
          )
        end
      end)
    end,
  })
end

return M
