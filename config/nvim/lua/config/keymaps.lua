-- Loaded by LazyVim after startup.
require("config.reader").setup()

vim.keymap.set("n", "mm", "<C-o>", { desc = "Jump back (Ctrl-o)" })
-- Remap through mm so historical review's buffer-local return also applies.
for _, key in ipairs({ "<D-[>", "<D-【>" }) do
  vim.keymap.set("n", key, "mm", { remap = true, desc = "Jump back (mm)" })
end
-- Pair with mm: native jump-list forward for code, review history for snapshots.
for _, key in ipairs({ "<D-]>", "<D-】>" }) do
  vim.keymap.set("n", key, function()
    local navigation = require("config.navigation")
    if vim.b.mate_review_snapshot or navigation.is_review_buffer(vim.api.nvim_get_current_buf()) then
      return '<Cmd>lua require("config.navigation").forward()<CR>'
    end
    return "<C-i>"
  end, { expr = true, desc = "Jump forward" })
end
vim.keymap.set("i", "jj", "<Esc>", { desc = "Exit insert mode" })
vim.keymap.set({ "n", "x" }, "H", "0", { desc = "Start of line" })
vim.keymap.set({ "n", "x" }, "L", "$", { desc = "End of line" })

vim.keymap.set("x", "<D-c>", '"+y', { desc = "Copy selection to system clipboard" })
vim.keymap.set({ "n", "i", "x", "s" }, "<D-v>", function()
  vim.api.nvim_paste(vim.fn.getreg("+"), true, -1)
end, { desc = "Paste from system clipboard" })
