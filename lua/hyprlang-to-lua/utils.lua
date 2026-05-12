local M = {}

---@param node TSNode
---@param label string
---@param indent integer
function M.print_tsnode(node, label, indent)
  indent = indent
  print(
    string.format(
      "%s%s (named = %s) (extra = %s)",
      string.rep(" ", indent),
      label,
      node:named(),
      node:extra()
    )
  )
  for child in node:iter_children() do
    M.print_tsnode(child, child:type(), indent + 4)
  end
end

---@param node TSNode
---@param src string?
---@return string
function M.inspect_tsnode(node, src)
  return vim.inspect({
    type = node:type(),
    range = { node:range() },
    text = src and { vim.treesitter.get_node_text(node, src) } or "<no src text provided>",
  })
end

---@param v any
---@return boolean truthy
function M.istruthy(v)
  if type(v) == "string" then
    return #v > 0 and v or nil
  end
  return not not v
end

---@param s string
---@param i integer?
---@param j integer?
---@return string?, string?, string?, string?, string?, string?, string?, string?, string?, string?, string?
function M.unpack_by_whitespace(s, i, j)
  return unpack(vim.split(s, "%s+"), i, j)
end

---@param path string
---@return string[] lines
---@nodiscard
M.readlines = function(path)
  local lines = {}
  for line in io.lines(path) do
    lines[#lines + 1] = line
  end
  return lines
end

---@param path string
---@return string text
---@nodiscard
M.readfile = function(path)
  local f = assert(io.open(path, "r"))
  local text = assert(f:read("*a"))
  f:close()
  return text
end

---@param env_var string
---@param default string
---@return string
local function env_or_default(env_var, default)
  local val = os.getenv(env_var)
  if val and val ~= "" then
    return vim.fs.normalize(val)
  end

  return vim.fs.normalize(default)
end

M.xdg = {
  data_home = env_or_default("XDG_DATA_HOME", "~/.local/share"),
  config_home = env_or_default("XDG_CONFIG_HOME", "~/.config"),
  state_home = env_or_default("XDG_STATE_HOME", "~/.local/state"),
  cache_home = env_or_default("XDG_CACHE_HOME", "~/.cache"),
  runtime_dir = os.getenv("XDG_RUNTIME_DIR") or nil, -- No standard fallback

  -- Search paths (returned as strings; you may want to split these by ':')
  data_dirs = os.getenv("XDG_DATA_DIRS") or "/usr/local/share/:/usr/share/",
  config_dirs = os.getenv("XDG_CONFIG_DIRS") or "/etc/xdg",
}

M.config_hypr_path = vim.fs.joinpath(M.xdg.config_home, "hypr")

---@generic K
---@param tbl table<K>
---@param repl table<K, K>|fun(K):K
M.tbl_replace_keys = function(tbl, repl)
  if type(repl) == "function" then
    local original_keys = vim.tbl_keys(tbl)
    for _, key in ipairs(original_keys) do
      local new_key = repl(key)
      if new_key and new_key ~= key then
        tbl[new_key] = tbl[key]
        tbl[key] = nil
      end
    end
  elseif type(repl) == "table" then
    for original, replacement in pairs(repl) do
      if tbl[original] ~= nil then
        assert(
          tbl[replacement] == nil,
          ("replacement value %s already exists for %s"):format(replacement, original)
        )
        tbl[replacement] = tbl[original]
        tbl[original] = nil
      end
    end
  end
end

---Replaces elements in the list in-place according to the map
---@generic T
---@param list T[]
---@param repl table<T, T>
M.list_gsub = function(list, repl)
  for i, item in ipairs(list) do
    local replacement = repl[item]
    if replacement then
      list[i] = replacement
    end
  end
end

---@param s string
---@return string normalized
---@nodiscard
M.tosnakecase = function(s)
  -- Handle kebab
  local res = s:gsub("%-", "_")
  -- Handle camel/pascal
  res = res:gsub("([a-z])([A-Z])", "%1_%2")
  return res:lower()
end

return M
