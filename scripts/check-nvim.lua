-- Run after normal init; fail with a real nonzero exit instead of trusting +qa.
local ok, err = pcall(function()
  assert(vim.fn.has("nvim-0.11.2") == 1, "Neovim 0.11.2+ is required")
  local root = vim.fn.stdpath("config")
  for _, file in ipairs(vim.fn.globpath(root, "lua/**/*.lua", false, true)) do
    assert(loadfile(file))
  end
  local config = require("lazy.core.config")
  local lock = vim.json.decode(table.concat(vim.fn.readfile(root .. "/lazy-lock.json"), "\n"))
  for name, plugin in pairs(config.plugins) do
    assert(vim.uv.fs_stat(plugin.dir), "missing plugin: " .. name .. "; run :Lazy restore")
    if lock[name] then
      local revision = vim.system({ "git", "-C", plugin.dir, "rev-parse", "HEAD" }, { text = true }):wait()
      assert(revision.code == 0 and vim.trim(revision.stdout) == lock[name].commit,
        "plugin differs from lazy-lock.json: " .. name .. "; run :Lazy restore")
    end
    for _, task in ipairs(plugin._.tasks or {}) do
      assert(not task:has_errors(), "plugin task failed: " .. name)
    end
  end
  -- These are loaded after startup in interactive sessions. Exercise the same
  -- event here so an unloaded custom module cannot hide a startup error.
  vim.api.nvim_exec_autocmds("User", { pattern = "VeryLazy", modeline = false })
  for _, file in ipairs(vim.fn.globpath(root, "lua/config/*.lua", false, true)) do
    local name = vim.fn.fnamemodify(file, ":t:r")
    require("config." .. name)
  end
  if vim.env.DOTFILES_NVIM_INSTALL == "1" then
    require("lazy").load({ plugins = { "mason.nvim" } })
    local registry = require("mason-registry")
    local tools = LazyVim.opts("mason.nvim").ensure_installed or {}
    assert(vim.wait(180000, function()
      for _, name in ipairs(tools) do
        if not registry.has_package(name) then
          return false
        end
        local package = registry.get_package(name)
        if package:is_installing() or not package:is_installed() then return false end
      end
      return true
    end, 100), "Mason tools did not finish installing; inspect :Mason, then rerun install.sh")
  end
  -- v:errmsg also retains errors deliberately suppressed with silent! by
  -- upstream plugins. Check visible diagnostics instead of that stale value.
  local messages = vim.api.nvim_exec2("messages", { output = true }).output
  assert(not messages:match("E%d+:"), "configuration diagnostics: " .. messages)
end)
if not ok then
  vim.api.nvim_err_writeln(tostring(err))
  vim.cmd("cquit 1")
else
  print("Neovim startup, plugin files and custom modules passed")
end
