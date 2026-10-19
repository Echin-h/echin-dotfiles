return {
  { "LazyVim/LazyVim", opts = { news = { lazyvim = false, neovim = false } } },
  {
    "nvim-neo-tree/neo-tree.nvim",
    opts = {
      close_if_last_window = false,
      filesystem = {
        follow_current_file = { enabled = true },
        filtered_items = { hide_dotfiles = false, hide_gitignored = true },
      },
      window = {
        width = 28,
        mappings = {
          ["<LeftRelease>"] = "open",
          ["<2-LeftMouse>"] = "none",
        },
      },
    },
  },
  {
    "sindrets/diffview.nvim",
    cmd = { "DiffviewOpen", "DiffviewClose", "DiffviewFileHistory" },
    keys = {
      { "<leader>gv", "<cmd>DiffviewOpen<cr>", desc = "Review changes" },
      { "<leader>gH", "<cmd>DiffviewFileHistory %<cr>", desc = "File history" },
    },
    opts = function(_, opts)
      opts.enhanced_diff_hl = true
      opts.hooks = opts.hooks or {}
      opts.hooks.diff_buf_read = function(buf)
        -- Independent scroll animations fight Neovim's synchronized diff view.
        vim.b[buf].snacks_scroll = false
      end
      opts.view = opts.view or {}
      opts.view.default = { layout = "diff2_horizontal", winbar_info = true }
      opts.view.file_history = { layout = "diff2_horizontal", winbar_info = true }
      opts.file_history_panel = opts.file_history_panel or {}
      opts.file_history_panel.win_config = { position = "left", width = 38 }
      local actions = require("diffview.actions")
      opts.keymaps = opts.keymaps or {}
      opts.keymaps.file_panel = { { "n", "<LeftRelease>", actions.select_entry, { desc = "Click to open diff" } } }
      opts.keymaps.file_history_panel = {
        { "n", "<LeftRelease>", function()
          local view = require("diffview.lib").get_current_view()
          if not view or not view.panel:is_focused() then return end
          local item = view.panel:get_item_at_cursor()
          if not item then return end
          -- A commit row opens that commit's first file, rather than only
          -- toggling its fold and leaving the previous commit's diff visible.
          view:set_file(item.files and item.files[1] or item, false)
        end, { desc = "Click commit or file to review changes" } },
      }
    end,
  },
  {
    "neovim/nvim-lspconfig",
    opts = {
      servers = {
        ["*"] = {
          keys = { { "gd", function() require("config.reader").definition() end, desc = "Go to definition", has = "definition" } },
        },
        gopls = { mason = false },
        vtsls = { mason = false, cmd = { vim.fn.expand("~/.local/share/mate-code-tools/node_modules/.bin/vtsls"), "--stdio" } },
        tailwindcss = {
          mason = false,
          cmd = { vim.fn.expand("~/.local/share/mate-code-tools/node_modules/.bin/tailwindcss-language-server"), "--stdio" },
          settings = { tailwindCSS = { classFunctions = { "cn", "clsx", "cva", "tw" } } },
        },
      },
    },
  },
  {
    "saghen/blink.cmp",
    opts = {
      completion = { menu = { auto_show = true }, documentation = { auto_show = true } },
    },
  },
}
