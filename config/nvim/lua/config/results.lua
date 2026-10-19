local M = {}
local escape_mapping

local function window()
  for _, win in ipairs(vim.api.nvim_tabpage_list_wins(0)) do
    if vim.bo[vim.api.nvim_win_get_buf(win)].filetype == "qf" then return win end
  end
end

function M.close()
  local win = window()
  if not win then return false end
  local target = vim.api.nvim_get_current_win()
  if target == win then target = vim.w[win].mate_results_origin end
  if not target or not vim.api.nvim_win_is_valid(target) or vim.bo[vim.api.nvim_win_get_buf(target)].buftype ~= "" then
    target = nil
    for _, candidate in ipairs(vim.api.nvim_tabpage_list_wins(0)) do
      if candidate ~= win and vim.bo[vim.api.nvim_win_get_buf(candidate)].buftype == "" then target = candidate; break end
    end
  end
  vim.api.nvim_win_close(win, false)
  if target and vim.api.nvim_win_is_valid(target) then vim.api.nvim_set_current_win(target) end
  return true
end

function M.decorate()
  local buf = vim.api.nvim_get_current_buf()
  vim.wo.winbar = "%@v:lua.MateCloseResults@ [关闭结果] %X  Esc / q 返回代码"
  vim.keymap.set("n", "q", M.close, { buffer = buf, desc = "Close results" })
  vim.keymap.set("n", "<Esc>", M.close, { buffer = buf, desc = "Close results" })
end

function M.setup()
  if not escape_mapping then escape_mapping = vim.fn.maparg("<Esc>", "n", false, true) end
  _G.MateCloseResults = function() vim.schedule(M.close) end
  vim.keymap.set("n", "<Esc>", function()
    if M.close() then return end
    if escape_mapping.callback then
      local keys = escape_mapping.callback()
      if type(keys) == "string" then vim.api.nvim_feedkeys(vim.keycode(keys), "n", false) end
    else
      vim.api.nvim_feedkeys(vim.keycode(escape_mapping.rhs or "<Esc>"), "n", false)
    end
  end, { desc = "Dismiss results or escape" })
  vim.keymap.set("n", "q", function()
    if window() then vim.schedule(M.close); return "" end
    return "q"
  end, { expr = true, desc = "Close results or record macro" })
end

return M
