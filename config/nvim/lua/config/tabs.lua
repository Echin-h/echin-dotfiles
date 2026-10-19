local M = {}

function M.scroll(key)
  if not package.loaded["barbar"] or vim.fn.getmousepos().screenrow ~= 1 or vim.o.showtabline == 0 then return false end
  local render = require("barbar.ui.render")
  local layout = require("barbar.ui.layout").calculate(require("barbar.state"))
  local direction = (key == "<ScrollWheelRight>" or key == "<ScrollWheelDown>") and 1 or -1
  -- Move only the tab strip viewport, clamped to the actual overflow width.
  -- Scrolling never activates a buffer; activation remains a click action.
  local target = math.max(0, math.min(layout.buffers.scroll_max, render.get_scroll().target + direction * 4))
  render.set_scroll(target)
  return true
end

-- Keep empty startup pages out of the file strip without deleting buffers.
-- An unnamed document becomes listed again as soon as it has edits/content.
local function refresh_empty_pages()
  for _, buf in ipairs(vim.api.nvim_list_bufs()) do
    if vim.api.nvim_buf_is_loaded(buf) and vim.bo[buf].buftype == "" then
      local hidden = vim.b[buf].mate_empty_tab_hidden
      if vim.bo[buf].buflisted or hidden then
        local empty = vim.api.nvim_buf_get_name(buf) == "" and not vim.bo[buf].modified
          and vim.api.nvim_buf_line_count(buf) == 1
          and vim.api.nvim_buf_get_lines(buf, 0, 1, false)[1] == ""
        if empty and not hidden then
          vim.b[buf].mate_empty_tab_hidden = true
          vim.bo[buf].buflisted = false
        elseif not empty and hidden then
          vim.b[buf].mate_empty_tab_hidden = nil
          vim.bo[buf].buflisted = true
        end
      end
    end
  end
end

function M.setup()
  local pending = false
  local function refresh()
    if pending then return end
    pending = true
    vim.schedule(function()
      pending = false
      refresh_empty_pages()
    end)
  end
  vim.api.nvim_create_autocmd({ "BufAdd", "BufEnter", "BufWinEnter", "BufFilePost", "BufModifiedSet", "TextChanged", "TextChangedI", "TextChangedP" }, {
    group = vim.api.nvim_create_augroup("MateEmptyTabs", { clear = true }),
    callback = refresh,
  })
  refresh()
  local keys = {
    { "[b", "BufferPrevious", "Previous file" },
    { "]b", "BufferNext", "Next file" },
    { "[B", "BufferMovePrevious", "Move file left" },
    { "]B", "BufferMoveNext", "Move file right" },
    { "<leader>bp", "BufferPin", "Pin file" },
    { "<leader>bP", "BufferCloseAllButPinned", "Close unpinned files" },
    { "<leader>bo", "BufferCloseAllButCurrent", "Close other files" },
    { "<leader>bl", "BufferCloseBuffersLeft", "Close files to the left" },
    { "<leader>br", "BufferCloseBuffersRight", "Close files to the right" },
    { "<leader>bj", "BufferPick", "Pick file" },
  }
  for _, key in ipairs(keys) do
    vim.keymap.set("n", key[1], "<cmd>" .. key[2] .. "<cr>", { desc = key[3] })
  end
end

return M
