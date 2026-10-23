-- Shared chrome for review scope, file navigation and code context.
local M = {}
local api = vim.api
local previous_tabline, previous_showtabline
local function valid(win)
  return win and api.nvim_win_is_valid(win)
end
local function escape(value)
  return tostring(value or ""):gsub("%%", "%%%%"):gsub("[\r\n]", " ")
end
local function view_now()
  local lib = package.loaded["diffview.lib"]
  return lib and lib.get_current_view()
end
local function button(id, label)
  return "%" .. id .. "@v:lua.MateReviewWorkspaceAction@ " .. label .. " %X"
end
function M.source()
  local view = view_now()
  if not view or not view.cur_layout then
    return
  end
  local win = vim.t.mate_review_code_win
  local found = false
  for _, pane in ipairs(view.cur_layout.windows) do
    if pane.id == win then
      found = true
    end
  end
  if not found then
    win = view.cur_layout.b.id
  end
  if valid(win) then
    return api.nvim_win_call(win, require("config.navigation").position)
  end
end
local function root()
  if not view_now() and vim.b.mate_review_snapshot then
    require("config.navigation").return_review()
  end
  local source = M.source()
  if source then
    api.nvim_set_current_win(source.win)
  end
end
function M.files()
  root()
  require("config.review_tree").close(false)
  local view = view_now()
  if view then
    view.panel:open()
    api.nvim_set_current_win(view.panel.winid)
  end
  M.refresh()
end
function M.tree()
  local source = M.source()
  if source then
    api.nvim_set_current_win(source.win)
  end
  require("config.review_context").tree()
end
function M.more()
  local options = { "复制位置", "切换 Worktree", "文件搜索", "全文搜索" }
  vim.ui.select(options, { prompt = "更多操作" }, function(choice)
    if not choice then
      return
    end
    local source = M.source()
    if source then
      api.nvim_set_current_win(source.win)
    end
    if choice == options[1] then
      require("config.reader").copy_location()
    elseif choice == options[2] then
      require("config.worktrees").pick()
    elseif choice == options[3] then
      Snacks.picker.files()
    else
      Snacks.picker.grep()
    end
  end)
end
function M.exit()
  if vim.env.MATE_REVIEW_MODE then
    vim.cmd("confirm qall")
    return
  end
  root()
  require("config.review_context").close(false)
  require("config.review_tree").close(false)
  require("config.review_commits").close(false)
  if view_now() then
    vim.cmd.DiffviewClose()
  end
end
function M.line()
  local view = view_now()
  local snapshot = vim.b.mate_review_snapshot
  if not view and not snapshot then
    return ""
  end
  local range = snapshot and snapshot.revision:sub(1, 8) or (view and view.rev_arg) or ""
  local text = button(1, "整体改动") .. button(2, "提交历史") .. button(5, "退出审阅")
  if vim.o.columns >= 130 and range ~= "" then
    text = text .. " | " .. escape(range)
  end
  return text .. "%<%="
end
function M.file_bar(tree)
  return button(6, tree and "改动文件" or "[改动文件]")
    .. button(7, tree and "[完整目录]" or "完整目录")
end
function M.code_bar(label)
  local version, path = label:match("^(.-) · (.*)$")
  if not version then
    return escape(label)
  end
  return escape(version) .. " · %<" .. escape(path)
end
function M.refresh()
  local view = view_now()
  local active = view or vim.b.mate_review_snapshot
  if active then
    if previous_tabline == nil then
      previous_tabline = vim.o.tabline
      previous_showtabline = vim.o.showtabline
    end
    vim.o.tabline = "%!v:lua.MateReviewWorkspaceLine()"
    vim.o.showtabline = 2
  elseif previous_tabline ~= nil then
    vim.o.tabline = previous_tabline
    vim.o.showtabline = previous_showtabline
    previous_tabline = nil
  end
  if view and view.panel and view.panel:is_open() and vim.bo[view.panel.bufid].filetype == "DiffviewFiles" then
    vim.wo[view.panel.winid].winbar = M.file_bar(false)
  end
  if view and view.cur_layout then
    local a, b = view.cur_layout.a, view.cur_layout.b
    if view.panel:is_open() and vim.o.columns < 110 then
      api.nvim_win_set_width(view.panel.winid, 28)
    end
    if
      a
      and b
      and valid(a.id)
      and valid(b.id)
      and api.nvim_win_get_position(a.id)[1] == api.nvim_win_get_position(b.id)[1]
    then
      local width = api.nvim_win_get_width(a.id) + api.nvim_win_get_width(b.id)
      if math.abs(api.nvim_win_get_width(a.id) - api.nvim_win_get_width(b.id)) > 1 then
        api.nvim_win_set_width(a.id, math.floor(width / 2))
      end
    end
    for _, side in ipairs({ "a", "b" }) do
      local pane = view.cur_layout[side]
      if pane and valid(pane.id) then
        local context = require("config.review_navigation").context(api.nvim_win_get_buf(pane.id))
        if context then
          local label = (side == "a" and "旧版 " or "新版 ")
            .. (context.revision and context.revision:sub(1, 8) or "工作区")
            .. " · "
            .. context.path
          vim.wo[pane.id].winbar = M.code_bar(label)
        end
      end
    end
  end
  vim.cmd.redrawtabline()
end
function M.setup()
  local actions = {
    function()
      root()
      require("config.review_commits").overall()
    end,
    function()
      root()
      require("config.review_commits").open()
    end,
    M.more,
    function()
      require("config.reader").help()
    end,
    M.exit,
    M.files,
    M.tree,
    function()
      local view = view_now()
      if view and valid(view.cur_layout.a.id) then
        api.nvim_set_current_win(view.cur_layout.a.id)
      end
    end,
    function()
      local view = view_now()
      if view and valid(view.cur_layout.b.id) then
        api.nvim_set_current_win(view.cur_layout.b.id)
      end
    end,
  }
  _G.MateReviewWorkspaceAction = function(id, _, button)
    if button ~= "l" then
      return
    end
    vim.schedule(function()
      if actions[id] then
        actions[id]()
        M.refresh()
      end
    end)
  end
  _G.MateReviewWorkspaceLine = M.line
  local group = api.nvim_create_augroup("MateReviewWorkspace", { clear = true })
  api.nvim_create_autocmd({ "TabEnter", "WinEnter", "BufWinEnter", "VimResized" }, {
    group = group,
    callback = function()
      vim.schedule(M.refresh)
    end,
  })
  api.nvim_create_autocmd("User", {
    group = group,
    pattern = { "DiffviewViewOpened", "DiffviewDiffBufWinEnter", "MateReviewSnapshot" },
    callback = function()
      vim.schedule(M.refresh)
    end,
  })
  require("config.review_commits").setup()
end
return M
