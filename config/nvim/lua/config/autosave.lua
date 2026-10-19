local M = {}
local timers = {}
local failures = {}

local function cancel(buf)
  local timer = timers[buf]
  timers[buf] = nil
  if timer and not timer:is_closing() then
    timer:stop()
    timer:close()
  end
end

local function writable(buf)
  return vim.api.nvim_buf_is_valid(buf)
    and vim.api.nvim_buf_is_loaded(buf)
    and vim.bo[buf].buftype == ""
    and vim.bo[buf].modified
    and vim.bo[buf].modifiable
    and not vim.bo[buf].readonly
    and not vim.b[buf].mate_review_snapshot
    and vim.api.nvim_buf_get_name(buf) ~= ""
end

function M.save(buf)
  cancel(buf)
  if not writable(buf) then
    return
  end
  local ok, err = pcall(vim.api.nvim_buf_call, buf, function()
    -- Native update detects external changes and runs normal write events;
    -- never force-write or silently overwrite another process's edits.
    vim.cmd("silent keepalt keepjumps update")
  end)
  if ok then
    failures[buf] = nil
  elseif failures[buf] ~= tostring(err) then
    failures[buf] = tostring(err)
    vim.notify(
      "自动保存失败，内容仍在编辑器中：" .. tostring(err),
      vim.log.levels.ERROR,
      { title = "自动保存" }
    )
  end
end

function M.setup()
  for buf in pairs(timers) do
    cancel(buf)
  end
  local group = vim.api.nvim_create_augroup("MateAutoSave", { clear = true })
  vim.api.nvim_create_autocmd({ "TextChanged", "TextChangedI" }, {
    group = group,
    callback = function(event)
      cancel(event.buf)
      if not writable(event.buf) then
        return
      end
      timers[event.buf] = vim.defer_fn(function()
        timers[event.buf] = nil
        M.save(event.buf)
      end, 800)
    end,
  })
  vim.api.nvim_create_autocmd({ "InsertLeave", "BufLeave" }, {
    group = group,
    callback = function(event)
      M.save(event.buf)
    end,
  })
  vim.api.nvim_create_autocmd({ "FocusLost", "VimLeavePre" }, {
    group = group,
    callback = function()
      for _, buf in ipairs(vim.api.nvim_list_bufs()) do
        M.save(buf)
      end
    end,
  })
  vim.api.nvim_create_autocmd({ "BufWritePost", "BufUnload", "BufWipeout" }, {
    group = group,
    callback = function(event)
      cancel(event.buf)
      failures[event.buf] = nil
    end,
  })
end

return M
