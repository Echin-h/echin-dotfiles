return {
  { "akinsho/bufferline.nvim", enabled = false },
  {
    "romgrk/barbar.nvim",
    event = "VeryLazy",
    dependencies = { "nvim-mini/mini.icons" },
    init = function() vim.g.barbar_auto_setup = false end,
    opts = {
      animation = false,
      auto_hide = 1,
      clickable = true,
      maximum_length = 26,
      minimum_padding = 1,
      maximum_padding = 2,
      insert_at_end = true,
      sidebar_filetypes = { ["neo-tree"] = { event = "BufWipeout" } },
      icons = {
        filetype = { enabled = true },
        diagnostics = { [vim.diagnostic.severity.ERROR] = { enabled = true }, [vim.diagnostic.severity.WARN] = { enabled = true } },
        modified = { button = "●" },
        separator = { left = "▎", right = "" },
      },
    },
    config = function(_, opts)
      require("barbar").setup(opts)
      require("config.tabs").setup()
    end,
  },
}
