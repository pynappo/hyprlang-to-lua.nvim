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

return M
