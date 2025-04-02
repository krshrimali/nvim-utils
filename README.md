# nvim-utils

All my utilities of neovim in a single plugin

## ✨ Features (so far)

- Run `pytest` on the current function
- Copy parent function/class
- View function signatures
- Visual/select/search inside parent scopes

## 📦 Installation (lazy.nvim)

```lua
{
  "krshrimali/nvim-utils",
  config = function()
    require("tgkrsutil") -- or require("tgkrsutil").setup()
  end
}
