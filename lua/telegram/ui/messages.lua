-- Messages component for Telegram.nvim
local api = vim.api
local events = require('telegram.core.events')
local tdlib = require('telegram.core.tdlib')
local layout = require('telegram.ui.layout')

local M = {}

-- Messages state
local state = {
    messages = {},
    current_chat = nil,
    loading = false,
    buffer = nil,
    window = nil,
    last_message_id = 0,
    media_previews = {},
}

-- Format message content
local function format_message_content(message)
    if not message.content then
        return "Invalid message content"
    end

    local content_type = message.content["@type"]
    
    if content_type == "messageText" then
        return message.content.text.text
    elseif content_type == "messagePhoto" then
        return "[Photo]" .. (message.content.caption and message.content.caption.text or "")
    elseif content_type == "messageVideo" then
        return "[Video]" .. (message.content.caption and message.content.caption.text or "")
    elseif content_type == "messageDocument" then
        return "[Document: " .. (message.content.document.file_name or "Unnamed") .. "]"
    elseif content_type == "messageVoiceNote" then
        return "[Voice Message]" .. (message.content.caption and message.content.caption.text or "")
    elseif content_type == "messageSticker" then
        return "[Sticker: " .. (message.content.sticker.emoji or "") .. "]"
    elseif content_type == "messageAnimation" then
        return "[GIF]" .. (message.content.caption and message.content.caption.text or "")
    else
        return "[" .. content_type .. "]"
    end
end

-- Format timestamp
local function format_timestamp(timestamp)
    return os.date("%H:%M", timestamp)
end

-- Render message
local function render_message(message)
    local lines = {}
    local highlights = {}
    
    -- Format header
    local timestamp = format_timestamp(message.date)
    local sender = message.sender_id and message.sender_id.user_id or "Unknown"
    local header = string.format("[%s] %s:", timestamp, sender)
    
    table.insert(lines, header)
    
    -- Add header highlights
    table.insert(highlights, {
        group = "TelegramMessageTime",
        line = #lines - 1,
        col_start = 1,
        col_end = #timestamp + 2,
    })
    
    -- Format content
    local content = format_message_content(message)
    local wrapped_content = vim.split(content, "\n")
    
    for _, line in ipairs(wrapped_content) do
        table.insert(lines, "  " .. line)
    end
    
    -- Add content highlights
    local highlight_group = message.is_outgoing and "TelegramMessageOwn" or "TelegramMessageText"
    for i = 1, #wrapped_content do
        table.insert(highlights, {
            group = highlight_group,
            line = #lines - #wrapped_content + i - 1,
            col_start = 2,
            col_end = -1,
        })
    end
    
    -- Add separator
    table.insert(lines, "")
    
    return lines, highlights
end

-- Update messages display
local function update_display()
    if not state.buffer or not api.nvim_buf_is_valid(state.buffer) then
        return
    end
    
    -- Prepare lines and highlights
    local all_lines = {}
    local all_highlights = {}
    
    -- Add header
    if state.current_chat then
        table.insert(all_lines, state.current_chat.title)
        table.insert(all_lines, string.rep("─", 30))
        table.insert(all_lines, "")
    else
        table.insert(all_lines, "No chat selected")
        return
    end
    
    -- Add loading indicator
    if state.loading then
        table.insert(all_lines, "Loading messages...")
        table.insert(all_lines, "")
    end
    
    -- Sort messages by date
    local sorted_messages = vim.tbl_values(state.messages)
    table.sort(sorted_messages, function(a, b)
        return a.date < b.date
    end)
    
    -- Render each message
    for _, message in ipairs(sorted_messages) do
        local lines, highlights = render_message(message)
        
        -- Adjust highlight line numbers
        for _, hl in ipairs(highlights) do
            hl.line = hl.line + #all_lines
        end
        
        -- Add lines and highlights
        vim.list_extend(all_lines, lines)
        vim.list_extend(all_highlights, highlights)
    end
    
    -- Update buffer content
    api.nvim_buf_set_option(state.buffer, 'modifiable', true)
    api.nvim_buf_set_lines(state.buffer, 0, -1, false, all_lines)
    api.nvim_buf_set_option(state.buffer, 'modifiable', false)
    
    -- Apply highlights
    api.nvim_buf_clear_namespace(state.buffer, -1, 0, -1)
    for _, hl in ipairs(all_highlights) do
        api.nvim_buf_add_highlight(
            state.buffer,
            -1,
            hl.group,
            hl.line,
            hl.col_start,
            hl.col_end
        )
    end
    
    -- Scroll to bottom
    api.nvim_win_set_cursor(state.window, {#all_lines, 0})
end

-- Initialize messages view
function M.init()
    local handles = layout.get_handles()
    if not handles then return end
    
    state.buffer = handles.buffers.messages
    state.window = handles.windows.messages
    
    if not state.buffer or not api.nvim_buf_is_valid(state.buffer) then
        return
    end
    
    -- Set up keymaps
    local opts = { buffer = state.buffer, silent = true }
    
    -- Scrolling
    api.nvim_buf_set_keymap(state.buffer, 'n', '<C-u>', '', {
        callback = function() api.nvim_win_call(state.window, function()
            local current_line = api.nvim_win_get_cursor(state.window)[1]
            api.nvim_win_set_cursor(state.window, {current_line - vim.wo.scroll, 0})
        end) end,
        buffer = state.buffer,
        silent = true,
    })
    
    api.nvim_buf_set_keymap(state.buffer, 'n', '<C-d>', '', {
        callback = function() api.nvim_win_call(state.window, function()
            local current_line = api.nvim_win_get_cursor(state.window)[1]
            api.nvim_win_set_cursor(state.window, {current_line + vim.wo.scroll, 0})
        end) end,
        buffer = state.buffer,
        silent = true,
    })
    
    -- Set up event handlers
    events.on(events.events.UI_CHAT_SELECTED, function(chat)
        vim.notify("chat selected" .. vim.inspect(chat), vim.log.levels.INFO)
        M.load_chat(chat)
    end)
    
    events.on(events.events.MESSAGE_RECEIVED, function(message)
        if state.current_chat and message.chat_id == state.current_chat.id then
            state.messages[message.id] = message
            state.last_message_id = math.max(state.last_message_id, message.id)
            update_display()
        end
    end)
    
    events.on(events.events.MESSAGE_EDITED, function(update)
        if state.current_chat and update.chat_id == state.current_chat.id then
            if state.messages[update.message_id] then
                state.messages[update.message_id] = vim.tbl_extend("force",
                    state.messages[update.message_id],
                    update
                )
                update_display()
            end
        end
    end)
end

-- Load chat history
function M.load_chat(chat)
    if not chat then return end
    
    state.current_chat = chat
    state.messages = {}
    state.loading = true
    update_display()
    
    -- Load initial messages
    tdlib.get_chat_history(chat.id, 0, 50)
    
    -- Reset loading state after a delay
    vim.defer_fn(function()
        state.loading = false
        update_display()
    end, 1000)
end

-- Load more messages
function M.load_more_messages()
    if not state.current_chat or state.loading then return end
    
    state.loading = true
    update_display()
    
    tdlib.get_chat_history(
        state.current_chat.id,
        state.last_message_id,
        50
    )
    
    vim.defer_fn(function()
        state.loading = false
        update_display()
    end, 1000)
end

-- Handle media preview
function M.handle_media(message)
    if not message.content then return end
    
    local content_type = message.content["@type"]
    if content_type == "messagePhoto" then
        local photo = message.content.photo
        local file_id = photo.sizes[#photo.sizes].photo.id
        
        -- Download photo if needed
        if not state.media_previews[file_id] then
            tdlib.download_file(file_id, 1)
        end
    end
end

-- Clean up
function M.cleanup()
    state.messages = {}
    state.current_chat = nil
    state.loading = false
    state.buffer = nil
    state.window = nil
    state.last_message_id = 0
    state.media_previews = {}
end

return M
