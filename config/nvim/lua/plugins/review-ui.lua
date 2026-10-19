return {
  {
    "sindrets/diffview.nvim",
    opts = function()
      require("config.review_ui").setup()
    end,
  },
}
