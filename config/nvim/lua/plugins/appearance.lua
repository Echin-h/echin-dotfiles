return {
  {
    "folke/tokyonight.nvim",
    opts = function(_, opts)
      opts.styles = opts.styles or {}
      opts.styles.comments = vim.tbl_extend("force", opts.styles.comments or {}, { italic = false })
      opts.styles.keywords = vim.tbl_extend("force", opts.styles.keywords or {}, { italic = false })
      local previous = opts.on_highlights
      opts.on_highlights = function(highlights, colors)
        if previous then previous(highlights, colors) end
        -- Keep inline-code text coloring without a separate background block.
        highlights["@markup.raw.markdown_inline"].bg = "NONE"
      end
    end,
  },
}
