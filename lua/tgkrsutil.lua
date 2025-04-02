local terminal_bufnr = nil -- Store the buffer number of the terminal

local function find_parent_function()
	local current_file = vim.fn.expand("%:p")
	local bufnr = vim.api.nvim_get_current_buf()
	local cursor_pos = vim.api.nvim_win_get_cursor(0)
	local row, col = cursor_pos[1] - 1, cursor_pos[2]

	if not vim.treesitter.language.require_language("python", nil, true) then
		print("Treesitter Python parser not available")
		return nil, nil, nil
	end

	local parser = vim.treesitter.get_parser(bufnr, "python")
	local tree = parser:parse()[1]
	local root = tree:root()

	local function find_parent_node(node)
		if node:type() == "function_definition" then
			return node
		elseif node:parent() then
			return find_parent_node(node:parent())
		else
			return nil
		end
	end

	local node = root:named_descendant_for_range(row, col, row, col)
	local parent_func_node = find_parent_node(node)

	if not parent_func_node then
		print("No parent function found")
		return nil, nil, nil
	end

	-- Get the parameters node
	local parameters_node = parent_func_node:field("parameters")[1]
	if not parameters_node then
		print("No parameters found")
		return nil, nil, nil
	end

	-- Extract function name
	local function_name_node = parent_func_node:child(1)
	local function_name = vim.treesitter.get_node_text(function_name_node, bufnr)

	-- Get the range for the function signature (name + parameters)
	local start_row, start_col, _, end_col = parent_func_node:range()
	local param_end_row, param_end_col = parameters_node:end_()

	-- Extract the signature text
	local signature_lines = vim.api.nvim_buf_get_text(bufnr, start_row, start_col, param_end_row, param_end_col, {})
	local signature = table.concat(signature_lines, " ")

	-- Clean up the signature
	signature = signature:gsub("%s+", " "):gsub("^%s*", ""):gsub("%s*$", "")

	-- Wrap the signature
	local max_line_length = 80 -- You can adjust this value
	local wrapped_signature = {}
	local current_line = "def " .. function_name .. "("

	for i, param in ipairs(vim.split(signature:match("%((.-)%)"), ",")) do
		param = param:match("^%s*(.-)%s*$") -- Trim whitespace
		if #current_line + #param > max_line_length and i > 1 then
			table.insert(wrapped_signature, current_line)
			current_line = "    " .. param
		else
			current_line = current_line .. (i > 1 and ", " or "") .. param
		end
	end
	current_line = current_line .. ")"
	table.insert(wrapped_signature, current_line)

	return current_file, wrapped_signature, function_name
end

local function generate_test_command()
	local file_path, _, function_name = find_parent_function()
	if file_path and function_name then
		return string.format('pytest "%s" -k "%s"', file_path, function_name)
	else
		return nil
	end
end

-- Function to open or reuse a Neovim terminal and run the test
local function run_test(open_new)
	local cmd = generate_test_command()
	if cmd then
		if open_new or terminal_bufnr == nil or not vim.api.nvim_buf_is_valid(terminal_bufnr) then
			-- Open and configure a new terminal split
			vim.cmd("botright 12split new")
			vim.cmd("terminal")

			terminal_bufnr = vim.api.nvim_get_current_buf()
		else
			-- Reuse the existing terminal buffer
			vim.cmd(string.format("botright split | buffer %d", terminal_bufnr))
		end

		-- Send the command to the terminal
		vim.fn.chansend(vim.b.terminal_job_id, cmd .. "\n")

		-- Ensure the terminal is in insert mode
		vim.cmd("startinsert")
	else
		print("Function not found")
	end
end

-- Function to copy the test command to the clipboard
local function copy_command_to_clipboard()
	local cmd = generate_test_command()
	if cmd then
		vim.fn.setreg("+", cmd)
		print("Command copied to clipboard: " .. cmd)
	else
		print("Function not found")
	end
end

-- Function to show the current function signature in a floating window
local function show_function_signature()
	local file_path, function_signature = find_parent_function()
	if function_signature then
		-- Add "Function Signature:" header
		local content = { "Function Signature:" }
		-- Append function signature lines
		vim.list_extend(content, function_signature)
		-- Append file path
		table.insert(content, "File: " .. file_path)

		local bufnr = vim.api.nvim_create_buf(false, true) -- Create a new empty buffer
		vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, content) -- Set the buffer lines

		-- Get the window dimensions
		local width = vim.api.nvim_get_option("columns")
		local height = vim.api.nvim_get_option("lines")

		-- Set the floating window dimensions
		local win_height = #content + 2 -- Add padding
		local win_width = math.ceil(width * 0.8)
		local row = math.ceil((height - win_height) / 2 - 1)
		local col = math.ceil((width - win_width) / 2)

		-- Create the floating window
		local opts = {
			style = "minimal",
			relative = "editor",
			width = win_width,
			height = win_height,
			row = row,
			col = col,
			border = "rounded", -- Add rounded border for visual appeal
		}
		local win_id = vim.api.nvim_open_win(bufnr, true, opts)

		-- Close the floating window when leaving it or pressing any key
		vim.api.nvim_buf_set_keymap(bufnr, "n", "<Esc>", "<CMD>close<CR>", { noremap = true, silent = true })
		vim.api.nvim_buf_set_keymap(bufnr, "n", "q", "<CMD>close<CR>", { noremap = true, silent = true })

	-- vim.api.nvim_create_autocmd({"CursorMoved", "BufHidden", "InsertEnter"}, {
	--     buffer = bufnr,
	--     callback = function()
	--         if vim.api.nvim_win_is_valid(win_id) then
	--             vim.api.nvim_win_close(win_id, true)
	--         end
	--     end,
	-- })
	else
		print("Function not found")
	end
end

-- Function to copy the whole parent function
local function copy_parent_function()
	local bufnr = vim.api.nvim_get_current_buf()
	local cursor_pos = vim.api.nvim_win_get_cursor(0)
	local row, col = cursor_pos[1] - 1, cursor_pos[2]

	if not vim.treesitter.language.require_language("python", nil, true) then
		print("Treesitter Python parser not available")
		return
	end

	local parser = vim.treesitter.get_parser(bufnr, "python")
	local tree = parser:parse()[1]
	local root = tree:root()

	local function find_parent_node(node, node_type)
		if node:type() == node_type then
			return node
		elseif node:parent() then
			return find_parent_node(node:parent(), node_type)
		else
			return nil
		end
	end

	local node = root:named_descendant_for_range(row, col, row, col)
	local parent_func_node = find_parent_node(node, "function_definition")

	if parent_func_node then
		local start_row, start_col, end_row, end_col = parent_func_node:range()
		local func_text = vim.api.nvim_buf_get_text(bufnr, start_row, start_col, end_row, end_col, {})
		local func_content = table.concat(func_text, "\n")
		vim.fn.setreg("+", func_content)
		print("Parent function copied to clipboard")
	else
		print("No parent function found")
	end
end

-- Function to copy the whole parent class
local function copy_parent_class()
	local bufnr = vim.api.nvim_get_current_buf()
	local cursor_pos = vim.api.nvim_win_get_cursor(0)
	local row, col = cursor_pos[1] - 1, cursor_pos[2]

	if not vim.treesitter.language.require_language("python", nil, true) then
		print("Treesitter Python parser not available")
		return
	end

	local parser = vim.treesitter.get_parser(bufnr, "python")
	local tree = parser:parse()[1]
	local root = tree:root()

	local function find_parent_node(node, node_type)
		if node:type() == node_type then
			return node
		elseif node:parent() then
			return find_parent_node(node:parent(), node_type)
		else
			return nil
		end
	end

	local node = root:named_descendant_for_range(row, col, row, col)
	local parent_class_node = find_parent_node(node, "class_definition")

	if parent_class_node then
		local start_row, start_col, end_row, end_col = parent_class_node:range()
		local class_text = vim.api.nvim_buf_get_text(bufnr, start_row, start_col, end_row, end_col, {})
		local class_content = table.concat(class_text, "\n")
		vim.fn.setreg("+", class_content)
		print("Parent class copied to clipboard")
	else
		print("No parent class found")
	end
end

local function search_in_selection(forward)
	-- Get the start and end of the visual selection
	local start_pos = vim.fn.getpos("'<")
	local end_pos = vim.fn.getpos("'>")

	-- Set the search range
	vim.fn.setpos("'[", start_pos)
	vim.fn.setpos("']", end_pos)

	-- Prompt for search term
	local search_term = vim.fn.input(forward and "/" or "?")
	if search_term == "" then
		return
	end

	-- Perform the search
	local flags = forward and "W" or "bW"
	local cmd =
		string.format([[exe "normal! %sg'[%s'\]%s"]], forward and "/" or "?", vim.fn.escape(search_term, "/"), flags)
	vim.cmd(cmd)
end
-- Function to visually select the whole parent function
local function visual_select_parent_function()
	local bufnr = vim.api.nvim_get_current_buf()
	local cursor_pos = vim.api.nvim_win_get_cursor(0)
	local row, col = cursor_pos[1] - 1, cursor_pos[2]

	if not vim.treesitter.language.require_language("python", nil, true) then
		print("Treesitter Python parser not available")
		return
	end

	local parser = vim.treesitter.get_parser(bufnr, "python")
	local tree = parser:parse()[1]
	local root = tree:root()

	local function find_parent_node(node, node_type)
		if node:type() == node_type then
			return node
		elseif node:parent() then
			return find_parent_node(node:parent(), node_type)
		else
			return nil
		end
	end

	local node = root:named_descendant_for_range(row, col, row, col)
	local parent_func_node = find_parent_node(node, "function_definition")

	if parent_func_node then
		local start_row, start_col, end_row, end_col = parent_func_node:range()

		-- Move cursor to start of function and enter visual mode
		vim.api.nvim_win_set_cursor(0, { start_row + 1, start_col })
		vim.cmd("normal! v")

		-- Move cursor to end of function
		vim.api.nvim_win_set_cursor(0, { end_row + 1, end_col })

		print("Parent function visually selected")
		return { start_row + 1, start_col }, { end_row + 1, end_col }
	else
		print("No parent function found")
		return nil
	end
end

-- Function to visually select the whole parent class
local function visual_select_parent_class()
	local bufnr = vim.api.nvim_get_current_buf()
	local cursor_pos = vim.api.nvim_win_get_cursor(0)
	local row, col = cursor_pos[1] - 1, cursor_pos[2]

	if not vim.treesitter.language.require_language("python", nil, true) then
		print("Treesitter Python parser not available")
		return
	end

	local parser = vim.treesitter.get_parser(bufnr, "python")
	local tree = parser:parse()[1]
	local root = tree:root()

	local function find_parent_node(node, node_type)
		if node:type() == node_type then
			return node
		elseif node:parent() then
			return find_parent_node(node:parent(), node_type)
		else
			return nil
		end
	end

	local node = root:named_descendant_for_range(row, col, row, col)
	local parent_class_node = find_parent_node(node, "class_definition")
	if parent_class_node then
		local start_row, start_col, end_row, end_col = parent_class_node:range()

		-- Move cursor to start of class and enter visual mode
		vim.api.nvim_win_set_cursor(0, { start_row + 1, start_col })
		vim.cmd("normal! v")

		-- Move cursor to end of class
		vim.api.nvim_win_set_cursor(0, { end_row + 1, end_col })

		print("Parent class visually selected")
		return { start_row + 1, start_col }, { end_row + 1, end_col }
	else
		print("No parent class found")
		return nil
	end
end

local function search_in_parent_function(forward)
	local start_pos, end_pos = visual_select_parent_function()
	if start_pos and end_pos then
		vim.fn.setpos("'<", { 0, start_pos[1], start_pos[2], 0 })
		vim.fn.setpos("'>", { 0, end_pos[1], end_pos[2], 0 })
		search_in_selection(forward)
	end
end

local function search_in_parent_class(forward)
	local start_pos, end_pos = visual_select_parent_class()
	if start_pos and end_pos then
		vim.fn.setpos("'<", { 0, start_pos[1], start_pos[2], 0 })
		vim.fn.setpos("'>", { 0, end_pos[1], end_pos[2], 0 })
		search_in_selection(forward)
	end
end

-- Create key mappings to run the test function and other commands
vim.api.nvim_set_keymap(
	"n",
	"<leader>rt",
	':lua require("tgkrsutil").run_test(false)<CR>',
	{ noremap = true, silent = true }
)
vim.api.nvim_set_keymap(
	"n",
	"<leader>rT",
	':lua require("tgkrsutil").run_test(true)<CR>',
	{ noremap = true, silent = true }
)
vim.api.nvim_set_keymap(
	"n",
	"<leader>rc",
	':lua require("tgkrsutil").copy_command_to_clipboard()<CR>',
	{ noremap = true, silent = true }
)
vim.api.nvim_set_keymap(
	"n",
	"<leader>rf",
	':lua require("tgkrsutil").show_function_signature()<CR>',
	{ noremap = true, silent = true }
)
vim.api.nvim_set_keymap(
	"n",
	"<leader>rif",
	':lua require("tgkrsutil").copy_parent_function()<CR>',
	{ noremap = true, silent = true }
)
vim.api.nvim_set_keymap(
	"n",
	"<leader>ric",
	':lua require("tgkrsutil").copy_parent_class()<CR>',
	{ noremap = true, silent = true }
)
vim.api.nvim_set_keymap(
	"n",
	"<leader>rvif",
	':lua require("tgkrsutil").visual_select_parent_function()<CR>',
	{ noremap = true, silent = true }
)
vim.api.nvim_set_keymap(
	"n",
	"<leader>rvic",
	':lua require("tgkrsutil").visual_select_parent_class()<CR>',
	{ noremap = true, silent = true }
)
vim.api.nvim_set_keymap(
	"n",
	"<leader>rsif",
	':lua require("tgkrsutil").search_in_parent_function(true)<CR>',
	{ noremap = true, silent = true }
)
vim.api.nvim_set_keymap(
	"n",
	"<leader>rsic",
	':lua require("tgkrsutil").search_in_parent_class(true)<CR>',
	{ noremap = true, silent = true }
)
vim.api.nvim_set_keymap(
	"n",
	"<leader>rSif",
	':lua require("tgkrsutil").search_in_parent_function(false)<CR>',
	{ noremap = true, silent = true }
)
vim.api.nvim_set_keymap(
	"n",
	"<leader>rSic",
	':lua require("tgkrsutil").search_in_parent_class(false)<CR>',
	{ noremap = true, silent = true }
)

-- Export the functions
return {
	run_test = run_test,
	copy_command_to_clipboard = copy_command_to_clipboard,
	show_function_signature = show_function_signature,
	copy_parent_function = copy_parent_function,
	copy_parent_class = copy_parent_class,
	visual_select_parent_function = visual_select_parent_function,
	visual_select_parent_class = visual_select_parent_class,
	search_in_parent_function = search_in_parent_function,
	search_in_parent_class = search_in_parent_class,
}
