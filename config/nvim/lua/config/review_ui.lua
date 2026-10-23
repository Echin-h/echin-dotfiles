local M = {}

function M.highlights()
  -- Full-line green backgrounds distinguish additions/changes from context;
  -- a brighter green identifies the changed characters within a line.
  local groups = {
    DiffviewDiffAdd = { bg = "#264f39" },
    DiffviewDiffChange = { bg = "#254331" },
    DiffviewDiffText = { fg = "#e8ffdf", bg = "#43784b", bold = true },
    DiffviewDiffAddAsDelete = { bg = "#582d3c" },
    DiffviewDiffDeleteDim = { fg = "#785266", bg = "#282333" },
    DiffviewFilePanelInsertions = { fg = "#9fe6a0", bold = true },
    DiffviewFilePanelDeletions = { fg = "#ff9ea9", bold = true },
  }
  for group, value in pairs(groups) do
    vim.api.nvim_set_hl(0, group, value)
  end
end

-- Diffview exposes panel components but has no statistics formatter. Decorate
-- the rendered component, without changing its file/context or cursor mapping.
-- Remove this adapter when Diffview provides a public statistics formatter.
function M.format_stats(component)
  local pairs_by_line = {}
  for _, hl in ipairs(component.hl or {}) do
    if hl.group == "DiffviewFilePanelInsertions" or hl.group == "DiffviewFilePanelDeletions" then
      local pair = pairs_by_line[hl.line_idx] or {}
      pairs_by_line[hl.line_idx] = pair
      pair[hl.group == "DiffviewFilePanelInsertions" and "add" or "del"] = hl
    end
  end
  for index, pair in pairs(pairs_by_line) do
    local add, del = pair.add, pair.del
    local line = component.lines[index + 1]
    if add and del and line and add.last <= del.first then
      local additions = line:sub(add.first + 1, add.last)
      local deletions = line:sub(del.first + 1, del.last)
      -- Conflicts, binary files and already formatted rows keep upstream text.
      if additions:match("^%s*%d+$") and deletions:match("^%d+$") then
        local plus = additions:match("^%s*") .. "+" .. additions:match("%d+")
        local minus = "-" .. deletions
        local start, finish = add.first, del.last
        local replacement = plus .. " " .. minus
        local delta = #replacement - (finish - start)
        component.lines[index + 1] = line:sub(1, start) .. replacement .. line:sub(finish + 1)
        for _, hl in ipairs(component.hl) do
          if hl.line_idx == index then
            if hl == add then
              hl.first, hl.last = start, start + #plus
            elseif hl == del then
              hl.first, hl.last = start + #plus + 1, start + #replacement
            elseif hl.first >= finish then
              hl.first, hl.last = hl.first + delta, hl.last + delta
            end
          end
        end
      end
    end
  end
  for _, child in ipairs(component.components or {}) do
    M.format_stats(child)
  end
end

function M.decorate_view(view)
  if not view or not view.panel or view.panel.mate_stats_decorated then return end
  local panel = view.panel
  local render = panel.render
  panel.render = function(self, ...)
    render(self, ...)
    if self.components and self.components.comp then
      M.format_stats(self.components.comp)
    end
  end
  panel.mate_stats_decorated = true
  -- The initial render may precede view_opened; refresh only a loaded panel.
  if panel:buf_loaded() then
    panel:render()
    panel:redraw()
  end
end

function M.setup()
  local group = vim.api.nvim_create_augroup("MateReviewUI", { clear = true })
  vim.api.nvim_create_autocmd("ColorScheme", {
    group = group,
    callback = function() vim.schedule(M.highlights) end,
  })
  vim.api.nvim_create_autocmd("User", {
    group = group,
    pattern = { "DiffviewViewOpened", "DiffviewViewEnter" },
    callback = function()
      M.highlights()
      M.decorate_view(require("diffview.lib").get_current_view())
    end,
  })
  vim.api.nvim_create_autocmd("User", {
    group = group,
    pattern = "DiffviewDiffBufWinEnter",
    callback = function()
      -- Keep the file panel selection, but avoid the cursorline decoration in
      -- code panes. It reads as an underline over changed lines in Diffview.
      vim.opt_local.cursorline = false
    end,
  })
  M.highlights()
end

return M
