-- tgkrsutil.lua (language-agnostic Treesitter utility plugin)
local M = {}
local config = {
  enable_test_runner = true,
  test_runner = function(file_path, function_name)
    return string.format('pytest "%s" -k "%s"', file_path, function_name)
  end,
}

function M.setup(opts)
  config = vim.tbl_deep_extend("force", config, opts or {})

  -- Optional: define default keymaps here
  vim.keymap.set("n", "<leader>rt", function() M.run_test(false) end, { desc = "Run test on function" })
  vim.keymap.set("n", "<leader>rT", function() M.run_test(true) end, { desc = "Run test in new terminal" })
  vim.keymap.set("n", "<leader>rif", M.copy_parent_function, { desc = "Copy parent function" })
  vim.keymap.set("n", "<leader>ric", M.copy_parent_class, { desc = "Copy parent class" })
end

local terminal_bufnr = nil

local function is_function_node(node)
  local type = node:type()
  return type:match("function") or type == "method_declaration"
end

local function is_class_node(node)
  local type = node:type()
  return type == "class_definition" or type == "class_declaration" or type == "struct_specifier"
end

local function find_parent_node(node, checker)
  if checker(node) then
    return node
  elseif node:parent() then
    return find_parent_node(node:parent(), checker)
  else
    return nil
  end
end

local function get_buf_parser(bufnr)
  local lang = vim.bo[bufnr].filetype
  if not vim.treesitter.language.require_language(lang, nil, true) then
    print("Treesitter parser not available for filetype: " .. lang)
    return nil, lang
  end
  return vim.treesitter.get_parser(bufnr, lang), lang
end

function M.find_parent_function()
  local bufnr = vim.api.nvim_get_current_buf()
  local cursor_pos = vim.api.nvim_win_get_cursor(0)
  local row, col = cursor_pos[1] - 1, cursor_pos[2]

  local parser, lang = get_buf_parser(bufnr)
  if not parser then return nil, nil, nil end

  local tree = parser:parse()[1]
  local root = tree:root()
  local node = root:named_descendant_for_range(row, col, row, col)
  local parent_func_node = find_parent_node(node, is_function_node)

  if not parent_func_node then
    print("No parent function found")
    return nil, nil, nil
  end

  local function_name = "<anonymous>"
  for i = 0, parent_func_node:named_child_count() - 1 do
    local child = parent_func_node:named_child(i)
    if child:type():match("identifier") then
      function_name = vim.treesitter.get_node_text(child, bufnr)
      break
    end
  end

  local start_row, start_col, _, _ = parent_func_node:range()
  local end_row, end_col = parent_func_node:end_()
  local lines = vim.api.nvim_buf_get_text(bufnr, start_row, start_col, end_row, end_col, {})

  local signature = lines[1] or ""
  signature = signature:gsub("%s+", " "):gsub("^%s*", ""):gsub("%s*$", "")

  return vim.fn.expand("%:p"), { signature }, function_name
end

function M.generate_test_command()
  if not config.enable_test_runner then
    return nil
  end
  local file_path, _, function_name = M.find_parent_function()
  if file_path and function_name then
    return config.test_runner(file_path, function_name)
  end
  return nil
end

function M.run_test(open_new)
  local cmd = M.generate_test_command()
  if not cmd then return end

  if open_new or not terminal_bufnr or not vim.api.nvim_buf_is_valid(terminal_bufnr) then
    vim.cmd("botright 12split new | terminal")
    terminal_bufnr = vim.api.nvim_get_current_buf()
  else
    vim.cmd(string.format("botright split | buffer %d", terminal_bufnr))
  end

  vim.fn.chansend(vim.b.terminal_job_id, cmd .. "\n")
  vim.cmd("startinsert")
end

local function copy_to_clipboard(content, msg)
  if content then
    vim.fn.setreg("+", content)
    print(msg)
  else
    print("Nothing to copy")
  end
end

function M.copy_parent_function()
  local bufnr = vim.api.nvim_get_current_buf()
  local cursor = vim.api.nvim_win_get_cursor(0)
  local parser = get_buf_parser(bufnr)
  if not parser then return end

  local tree = parser:parse()[1]
  local root = tree:root()
  local node = root:named_descendant_for_range(cursor[1] - 1, cursor[2], cursor[1] - 1, cursor[2])
  local func_node = find_parent_node(node, is_function_node)
  if func_node then
    local sr, sc, er, ec = func_node:range()
    local text = vim.api.nvim_buf_get_text(bufnr, sr, sc, er, ec, {})
    copy_to_clipboard(table.concat(text, "\n"), "Parent function copied to clipboard")
  else
    print("No parent function found")
  end
end

function M.copy_parent_class()
  local bufnr = vim.api.nvim_get_current_buf()
  local cursor = vim.api.nvim_win_get_cursor(0)
  local parser = get_buf_parser(bufnr)
  if not parser then return end

  local tree = parser:parse()[1]
  local root = tree:root()
  local node = root:named_descendant_for_range(cursor[1] - 1, cursor[2], cursor[1] - 1, cursor[2])
  local class_node = find_parent_node(node, is_class_node)
  if class_node then
    local sr, sc, er, ec = class_node:range()
    local text = vim.api.nvim_buf_get_text(bufnr, sr, sc, er, ec, {})
    copy_to_clipboard(table.concat(text, "\n"), "Parent class copied to clipboard")
  else
    print("No parent class found")
  end
end

return M
