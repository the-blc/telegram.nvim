-- Input component for Telegram.nvim
local api = vim.api

local M = {}

-- Input state
local state = {
	buffer = nil,
	window = nil,
	composing = false,
	reply_to = nil,
	draft = "",
	attachment = nil,
}

-- Handle message submission
local function submit_message()
	if not state.buffer or not api.nvim_buf_is_valid(state.buffer) then
		return
	end

	local current_chat = UI.chat_list.get_current_chat()
	if not current_chat then
		vim.notify("No chat selected", vim.log.levels.WARN)
		return
	end

	-- Get message text
	local lines = api.nvim_buf_get_lines(state.buffer, 1, -1, false)
	local text = table.concat(lines, "\n")

	if text == "" and not state.attachment then
		return
	end

	-- Handle different types of messages
	if state.attachment then
		if state.attachment.type == "file" then
			Core.tdlib.send_file(current_chat.id, state.attachment.path)
		elseif state.attachment.type == "voice" then
			-- TODO: Implement voice message sending
			vim.notify("Voice messages not yet implemented", vim.log.levels.INFO)
		end
		state.attachment = nil
	else
		Core.tdlib.send_message(current_chat.id, text)
	end

	-- Clear input
	api.nvim_buf_set_option(state.buffer, "modifiable", true)
	api.nvim_buf_set_lines(state.buffer, 1, -1, false, { "" })
	api.nvim_buf_set_option(state.buffer, "modifiable", false)

	-- Reset state
	state.composing = false
	state.reply_to = nil
	state.draft = ""
end

-- Handle file attachment
local function attach_file()
	-- Open file picker
	vim.ui.input({
		prompt = "Enter file path: ",
		completion = "file",
	}, function(path)
		if path then
			state.attachment = {
				type = "file",
				path = path,
			}
			vim.notify("File attached: " .. path, vim.log.levels.INFO)
		end
	end)
end

-- Start voice recording
local function start_voice_recording()
	-- TODO: Implement voice recording
	vim.notify("Voice recording not yet implemented", vim.log.levels.INFO)
end

-- Show emoji picker
local function show_emoji_picker()
	-- TODO: Implement emoji picker
	vim.notify("Emoji picker not yet implemented", vim.log.levels.INFO)
end

-- Initialize input component
function M.init()
	local handles = UI.layout.get_handles()
	if not handles then
		return
	end

	state.buffer = handles.buffers.input
	state.window = handles.windows.input

	if not state.buffer or not api.nvim_buf_is_valid(state.buffer) then
		return
	end

	-- Set buffer options
	api.nvim_buf_set_option(state.buffer, "buftype", "prompt")
	api.nvim_buf_set_option(state.buffer, "swapfile", false)

	-- Set up prompt
	vim.fn.prompt_setprompt(state.buffer, "Message: ")

	-- Set up keymaps
	local opts = { buffer = state.buffer, silent = true }

	-- Submit message
	api.nvim_buf_set_keymap(state.buffer, "i", "<C-s>", "", {
		callback = submit_message,
		buffer = state.buffer,
		silent = true,
	})

	api.nvim_buf_set_keymap(state.buffer, "n", "<C-s>", "", {
		callback = submit_message,
		buffer = state.buffer,
		silent = true,
	})

	-- Attach file
	api.nvim_buf_set_keymap(state.buffer, "i", "<C-a>", "", {
		callback = attach_file,
		buffer = state.buffer,
		silent = true,
	})

	api.nvim_buf_set_keymap(state.buffer, "n", "<C-a>", "", {
		callback = attach_file,
		buffer = state.buffer,
		silent = true,
	})

	-- Voice message
	api.nvim_buf_set_keymap(state.buffer, "i", "<C-v>", "", {
		callback = start_voice_recording,
		buffer = state.buffer,
		silent = true,
	})

	api.nvim_buf_set_keymap(state.buffer, "n", "<C-v>", "", {
		callback = start_voice_recording,
		buffer = state.buffer,
		silent = true,
	})

	-- Emoji picker
	api.nvim_buf_set_keymap(state.buffer, "i", "<C-e>", "", {
		callback = show_emoji_picker,
		buffer = state.buffer,
		silent = true,
	})

	api.nvim_buf_set_keymap(state.buffer, "n", "<C-e>", "", {
		callback = show_emoji_picker,
		buffer = state.buffer,
		silent = true,
	})

	-- Set up autocommands
	local group = api.nvim_create_augroup("TelegramInput", { clear = true })

	-- Handle text changes
	api.nvim_create_autocmd("TextChanged", {
		group = group,
		buffer = state.buffer,
		callback = function()
			local current_chat = UI.chat_list.get_current_chat()
			if current_chat then
				local lines = api.nvim_buf_get_lines(state.buffer, 1, -1, false)
				local text = table.concat(lines, "\n")

				if text ~= "" and not state.composing then
					state.composing = true
					Core.tdlib.send({
						["@type"] = "sendChatAction",
						chat_id = current_chat.id,
						action = {
							["@type"] = "chatActionTyping",
						},
					})
				elseif text == "" and state.composing then
					state.composing = false
				end

				state.draft = text
			end
		end,
	})

	-- Handle chat changes
	Core.events.on(Core.events.events.UI_CHAT_SELECTED, function(chat)
		-- Clear current input
		api.nvim_buf_set_option(state.buffer, "modifiable", true)
		api.nvim_buf_set_lines(state.buffer, 1, -1, false, { "" })
		api.nvim_buf_set_option(state.buffer, "modifiable", false)

		-- Reset state
		state.composing = false
		state.reply_to = nil
		state.draft = ""
		state.attachment = nil
	end)

	-- Enter insert mode by default
	vim.cmd("startinsert")
end

-- Set reply to message
function M.set_reply(message_id)
	state.reply_to = message_id
end

-- Clear reply
function M.clear_reply()
	state.reply_to = nil
end

-- Get current draft
function M.get_draft()
	return state.draft
end

-- Clean up
function M.cleanup()
	state.buffer = nil
	state.window = nil
	state.composing = false
	state.reply_to = nil
	state.draft = ""
	state.attachment = nil
end

return M
