local M = {}
local histories = {}
local marker = "  %#DiffviewFilePanelTitle#"

local function current()
  local lib = package.loaded["diffview.lib"]
  local view = lib and lib.get_current_view()
  return view, view and histories[view.tabpage]
end

function M.decorate_history_toolbar()
  if vim.bo.filetype ~= "DiffviewFileHistory" then
    return
  end
  local view, state = current()
  if not state or not view.panel then
    return
  end
  local bar = vim.wo.winbar
  local start = bar:find(marker, 1, true)
  if start then
    bar = bar:sub(1, start - 1)
  end
  local label = state.expanded and "收起" or "展开"
  local count = state.expanded and state.total or math.min(5, state.total)
  bar = bar .. marker .. ("%d/%d"):format(count, state.total) .. "%*"
  if state.total > 5 then
    bar = bar .. "  %@v:lua.MateReviewCommitsToggle@ [" .. label .. "] %X"
  end
  vim.wo.winbar = bar
end

function M.toggle()
  local view, state = current()
  if not state or view.panel.updating then
    return
  end
  local panel = view.panel
  local selected = panel.cur_item[1]
  local selected_hash = selected and selected.commit.hash
  local selected_file = panel.cur_item[2] and panel.cur_item[2].path
  state.expanded = not state.expanded
  for _, options in pairs(panel.log_options) do
    options.max_count = state.expanded and -1 or 5
  end
  panel:update_entries(function(entries, status)
    if status >= 2 or not entries then
      return
    end
    local target
    for _, entry in ipairs(entries) do
      if entry.commit.hash == selected_hash then
        for _, file in ipairs(entry.files) do
          if file.path == selected_file then
            target = file
            break
          end
        end
        target = target or entry.files[1]
        break
      end
    end
    target = target or (entries[1] and entries[1].files[1])
    if target and target ~= view:cur_file() then
      -- The native history refresh starts opening its first result while the
      -- log is streaming. Wait for that opening to finish before restoring a
      -- different selection; overlapping layout updates can lose windows.
      if view.cur_entry and not view.cur_entry.opened then
        view.emitter:once("file_open_post", function()
          vim.schedule(function()
            if vim.api.nvim_tabpage_is_valid(view.tabpage) then
              view:set_file(target, false)
            end
          end)
        end)
      else
        view:set_file(target, false)
      end
    end
    if panel:is_open() then
      vim.api.nvim_win_call(panel.winid, M.decorate_history_toolbar)
    end
  end)
  if panel:is_open() then
    vim.api.nvim_win_call(panel.winid, M.decorate_history_toolbar)
  end
end

function M.open_history()
  local range = vim.env.MATE_REVIEW_RANGE or "HEAD"
  local limited = vim.env.MATE_REVIEW_LIMIT == "5"
  vim.api.nvim_cmd(
    { cmd = "DiffviewFileHistory", args = {
      "--range=" .. range,
      "--max-count=" .. (limited and "5" or "-1"),
    } },
    {}
  )
  local view = require("diffview.lib").get_current_view()
  if not view or not limited then
    return
  end
  local result = vim
    .system({ "git", "rev-list", "--count", range, "--" }, {
      cwd = view.adapter.ctx.toplevel,
      text = true,
    })
    :wait()
  histories[view.tabpage] = { total = tonumber(result.stdout) or 5, expanded = false }
  _G.MateReviewCommitsToggle = function(_, _, button)
    if button == "l" then
      vim.schedule(M.toggle)
    end
  end
  local group = vim.api.nvim_create_augroup("MateReviewCommits", { clear = true })
  vim.api.nvim_create_autocmd({ "BufWinEnter", "WinEnter", "TabEnter" }, {
    group = group,
    callback = function()
      vim.schedule(M.decorate_history_toolbar)
    end,
  })
  vim.api.nvim_create_autocmd("TabClosed", {
    group = group,
    callback = function()
      for tab in pairs(histories) do
        if not vim.api.nvim_tabpage_is_valid(tab) then
          histories[tab] = nil
        end
      end
    end,
  })
  if view.panel:is_open() then
    vim.api.nvim_win_call(view.panel.winid, M.decorate_history_toolbar)
  end
end

return M
