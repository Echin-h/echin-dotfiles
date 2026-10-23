-- One commit selector per Diffview tab. Revision replacement is isolated here
-- because Diffview has no public change-range command; never patch its sources.
local M = {}
local api = vim.api
local states = {}
local page_size = 20
local function valid(win)
  return win and api.nvim_win_is_valid(win)
end
local function notice(message)
  vim.notify(message, vim.log.levels.INFO, { title = "审阅范围" })
end
local function view_now()
  local lib = package.loaded["diffview.lib"]
  return lib and lib.get_current_view()
end
local function refresh()
  local ui = package.loaded["config.review_workspace"]
  if ui then
    ui.refresh()
  end
end
local function state_for(view)
  local state = states[view.tabpage]
  if not state then
    local history_range = view.rev_arg or "HEAD"
    if not history_range:match("%^!$") and view.left.commit and view.right.commit then
      history_range = view.left.commit .. ".." .. view.right.commit
    end
    state = {
      view = view,
      range = view.rev_arg,
      history_range = history_range,
      limit = page_size,
      positions = {},
    }
    states[view.tabpage] = state
  end
  return state
end
function M.state()
  local view = view_now()
  return view and states[view.tabpage]
end
local function capture(view)
  local position = { path = view.cur_entry and view.cur_entry.path, panes = {} }
  for _, side in ipairs({ "a", "b" }) do
    local pane = view.cur_layout and view.cur_layout[side]
    if pane and valid(pane.id) then
      position.panes[side] = api.nvim_win_call(pane.id, function()
        return {
          cursor = api.nvim_win_get_cursor(0),
          view = vim.fn.winsaveview(),
          foldenable = vim.wo.foldenable,
          foldlevel = vim.wo.foldlevel,
        }
      end)
    end
  end
  return position
end
local function restore_position(view, position)
  if not position or not view.cur_entry or view.cur_entry.path ~= position.path then
    return
  end
  for side, saved in pairs(position.panes) do
    local pane = view.cur_layout[side]
    if pane and valid(pane.id) then
      api.nvim_win_call(pane.id, function()
        vim.wo.foldenable = saved.foldenable
        vim.wo.foldlevel = saved.foldlevel
        api.nvim_win_set_cursor(0, { math.min(api.nvim_buf_line_count(0), saved.cursor[1]), saved.cursor[2] })
        vim.fn.winrestview(saved.view)
      end)
    end
  end
end
function M.close(restore)
  local state = M.state()
  if not state or not valid(state.win) then
    return false
  end
  local win = state.win
  state.win = nil
  api.nvim_win_close(win, true)
  if restore ~= false then
    local pane = state.view.cur_layout.b
    if valid(pane.id) then
      api.nvim_set_current_win(pane.id)
    end
  end
  return true
end
local function render(state)
  if not valid(state.win) then
    return
  end
  local lines = {}
  for _, entry in ipairs(state.entries or {}) do
    lines[#lines + 1] = (entry.hash == state.commit and "● " or "  ") .. entry.hash:sub(1, 8) .. " " .. entry.subject
  end
  if state.more then
    lines[#lines + 1] = "  加载更多提交…"
  end
  if #lines == 0 then
    lines = { state.loading and "  正在加载提交…" or "  此范围没有提交" }
  end
  vim.bo[state.buf].modifiable = true
  api.nvim_buf_set_lines(state.buf, 0, -1, false, lines)
  vim.bo[state.buf].modifiable = false
  vim.wo[state.win].winbar = "%@v:lua.MateReviewHistoryClose@ 关闭列表 %X  提交历史 " .. #(state.entries or {})
end
local function load(state)
  if state.loading then
    return
  end
  state.loading = true
  local row = valid(state.win) and api.nvim_win_get_cursor(state.win)[1] or 1
  vim.system({
    "git",
    "-C",
    state.view.adapter.ctx.toplevel,
    "log",
    "--format=%H%x09%s",
    "--max-count=" .. (state.limit + 1),
    "--end-of-options",
    state.history_range,
    "--",
  }, { text = true }, function(result)
    vim.schedule(function()
      if states[state.view.tabpage] ~= state then
        return
      end
      state.loading = false
      if result.code ~= 0 then
        notice("无法读取提交：" .. result.stderr)
        return
      end
      local entries = {}
      for line in result.stdout:gmatch("[^\n]+") do
        local hash, subject = line:match("^(%x+)\t(.*)$")
        if hash then
          entries[#entries + 1] = { hash = hash, subject = subject }
        end
      end
      state.more = #entries > state.limit
      if state.more then
        table.remove(entries)
      end
      state.entries = entries
      render(state)
      if valid(state.win) then
        api.nvim_win_set_cursor(state.win, { math.min(row, math.max(1, #entries)), 0 })
      end
    end)
  end)
  render(state)
end
-- Preserve the FileDict identity used by the native panel. Empty it before
-- refreshing: Diffview otherwise reuses same-path entries from the OLD revision.
local function replace_range(state, range, commit)
  local view = state.view
  if state.busy or not view.ready or (view.cur_entry and not view.cur_entry.opened) then
    notice("正在切换文件，请稍后再选提交")
    return
  end
  local options = view.adapter:diffview_options(require("diffview.arg_parser").parse({ range }))
  if not options then
    return
  end
  require("config.review_context").close(false)
  require("config.review_tree").close(false)
  state.positions[state.commit or "overall"] = capture(view)
  local target = state.positions[commit or "overall"]
  local path = target and target.path or (view.cur_entry and view.cur_entry.path)
  state.busy = true
  view.cur_layout:detach_files()
  for _, file in view.files:iter() do
    file:destroy()
  end
  view.files:set_conflicting({})
  view.files:set_working({})
  view.files:set_staged({})
  view.files:update_file_trees()
  view.panel:set_cur_file(nil)
  view.cur_entry = nil
  view.left, view.right, view.rev_arg = options.left, options.right, range
  view.options = options.options or {}
  view.options.selected_file = path
  view.initialized = false
  view.panel.rev_pretty_name = range
  state.commit = commit
  view:update_files(function(err)
    vim.schedule(function()
      if not api.nvim_tabpage_is_valid(view.tabpage) then
        return
      end
      if err then
        state.busy = false
        notice("切换范围失败：" .. table.concat(err, "; "))
        return
      end
      local function finish()
        if api.nvim_get_current_tabpage() == view.tabpage then
          restore_position(view, target)
        end
        state.busy = false
        render(state)
        refresh()
      end
      if target and view.cur_entry and not view.cur_entry.opened then
        view.emitter:once("file_open_post", function()
          vim.schedule(finish)
        end)
      else
        finish()
      end
    end)
  end)
  render(state)
  refresh()
end
function M.select()
  local state = M.state()
  if not state or not valid(state.win) then
    return
  end
  local row = api.nvim_win_get_cursor(state.win)[1]
  local entry = (state.entries or {})[row]
  if entry then
    if entry.hash ~= state.commit then
      replace_range(state, entry.hash .. "^!", entry.hash)
    end
  elseif state.more then
    state.limit = state.limit + page_size
    load(state)
  end
end
function M.overall()
  local state = M.state()
  if not state then
    return
  end
  M.close(false)
  if state.commit then
    replace_range(state, state.range, nil)
  end
end
function M.open(range)
  local view = view_now()
  if not view or not view.files then
    notice("请先打开审阅")
    return
  end
  local state = state_for(view)
  if range then
    state.history_range = range
  end
  if valid(state.win) then
    api.nvim_set_current_win(state.win)
    return
  end
  local position = capture(view)
  require("config.review_context").close(false)
  require("config.review_tree").close(false)
  view.panel:open()
  api.nvim_set_current_win(view.panel.winid)
  vim.cmd("aboveleft " .. math.max(4, math.min(10, math.floor(vim.o.lines / 3))) .. "split")
  state.win = api.nvim_get_current_win()
  state.buf = api.nvim_create_buf(false, true)
  api.nvim_win_set_buf(state.win, state.buf)
  vim.bo[state.buf].filetype = "mate_review_commits"
  vim.bo[state.buf].bufhidden = "wipe"
  for key, value in pairs({
    diff = false,
    scrollbind = false,
    cursorbind = false,
    number = false,
    relativenumber = false,
    wrap = false,
    signcolumn = "no",
    cursorline = true,
    winfixheight = true,
  }) do
    vim.wo[state.win][key] = value
  end
  for key, fn in pairs({ ["<CR>"] = M.select, ["<LeftRelease>"] = M.select, q = M.close, ["<Esc>"] = M.close }) do
    api.nvim_buf_set_keymap(state.buf, "n", key, "", { callback = fn, silent = true, nowait = true })
  end
  api.nvim_create_autocmd("BufWipeout", {
    buffer = state.buf,
    once = true,
    callback = function()
      state.win = nil
    end,
  })
  if not state.entries then
    load(state)
  else
    render(state)
  end
  restore_position(view, position)
  refresh()
end
function M.open_history()
  local range = vim.env.MATE_REVIEW_RANGE or "HEAD"
  local result = vim
    .system({ "git", "rev-list", "--max-count=1", "--end-of-options", range, "--" }, { text = true })
    :wait()
  local hash = vim.trim(result.stdout or "")
  if result.code ~= 0 or hash == "" then
    notice("此范围没有可审阅的提交")
    return
  end
  vim.api.nvim_cmd({ cmd = "DiffviewOpen", args = { hash .. "^!" } }, {})
  local view = view_now()
  if not view then
    return
  end
  local state = state_for(view)
  state.range = range:find("..", 1, true) and range or hash .. "^!"
  state.commit, state.history_range = hash, range
  vim.schedule(function()
    M.open(range)
  end)
end
function M.setup()
  _G.MateReviewHistoryClose = function(_, _, button)
    if button == "l" then
      vim.schedule(M.close)
    end
  end
  api.nvim_create_autocmd("TabClosed", {
    group = api.nvim_create_augroup("MateReviewCommits", { clear = true }),
    callback = function()
      for tab in pairs(states) do
        if not api.nvim_tabpage_is_valid(tab) then
          states[tab] = nil
        end
      end
    end,
  })
end
return M
