A WIP one-off plugin to assist in the migration of hyprlang syntax to lua, using Neovim's built-in Treesitter parsing.

# Use

Install `tree-sitter-hyprlang` parser + queries into Neovim via your method of choice.

In a hyprlang buffer (e.g. `:set ft=hyprlang`), use `:HyprlangToLua` to open a new buffer with the selected hyprlang
converted to Lua. If no text is selected, the current hyprlang buffer is used.

# Developing

Tools:

- lua-language-server
- Neovim
- hyprland built from git (or have the lua stubs available at /usr/share/hypr/stubs/).
