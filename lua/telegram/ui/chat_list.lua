-- Chat list component for Telegram.nvim
local api = vim.api
local baleia = require("baleia").setup()
local events = require('telegram.core.events')
local tdlib = require('telegram.core.tdlib')
local layout = require('telegram.ui.layout')
local uv = vim.loop
local M = {}
local photos = {}
-- Chat list state
local state = {
    chats = {},
    chat_positions = {}, -- Store chat positions
    selected_chat = nil,
    loading = false,
    buffer = nil,
    window = nil,
    current_list_type = "main", -- Track current chat list type
    current_filter_id = nil, -- For folder chat lists
    chat_folders = {}, -- Store chat folders
    main_chat_list_position = 0, -- Position of main chat list
    selected_folder_index = nil -- Track selected folder in the UI
}

local chat_types = {
    DIRECT = "direct",
    GROUP = "group",
    CHANNEL = "channel",
    BOT = "bot",
    PRIVATE_DIRECT = "private_direct"
}

-- Get chat display info
local function get_chat_info(chat)
    -- vim.notify(vim.inspect(chat), vim.log.levels.INFO)
    local name = chat.title or "Unknown Chat"
    local photo_path = nil
    local last_message = ""
    local chat_type = nil
    local unread_message_count = chat.unread_count

    -- Get user info for private chats
    if chat.type then
        if chat.type["@type"] == "chatTypePrivate" then
            local user = users.get_user(chat.type.user_id)
            if user then
                name = users.get_display_name(user.id)
                photo_path = users.get_profile_photo(user.id)
            end
            chat_type = chat_types.PRIVATE_DIRECT
        elseif chat.type["@type"] == "chatTypeSupergroup" then
            chat_type = chat_types.GROUP
        elseif chat.type["@type"] == "chatTypeSupergroup" and chat.type["@type"].is_channel then
            chat_type = chat_types.CHANNEL
        else 
            chat_type = chat_types.DIRECT
        end
    end

    

    -- Get last message
    if chat.last_message then
        -- Get sender name
        if chat.last_message.sender_id then
            if chat.last_message.sender_id["@type"] == "messageSenderUser" then
                local user = users.get_user(chat.last_message.sender_id.user_id)
                if user then
                    if user.is_premium then
                        last_message = "✔" .. user.first_name .. ": "
                    else 
                        last_message = user.first_name .. ": "
                    end
                else
                    if chat.last_message and chat.last_message.sender_id and chat.last_message.sender_id["@type"] ==
                        "messageSenderUser" then
                        users.add_user(chat.last_message.sender_id.user_id, {})
                        local tdlib = require('telegram.core.tdlib')
                        tdlib.get_user(chat.last_message.sender_id.user_id)
                    end
                end
            end
        end

        -- Get message content
        local content = ""
        if chat.last_message.content then
            if chat.last_message.content["@type"] == "messageText" then
                content = chat.last_message.content.text.text
            elseif chat.last_message.content["@type"] == "messagePhoto" then
                content = "📷 Photo"
            elseif chat.last_message.content["@type"] == "messageVideo" then
                content = "🎥 Video"
            elseif chat.last_message.content["@type"] == "messageDocument" then
                content = "📄 Document"
            elseif chat.last_message.content["@type"] == "messageSticker" then
                content = "😀 Sticker"
            elseif chat.last_message.content["@type"] == "messageVoiceNote" then
                content = "🎤 Voice"
            elseif chat.last_message.content["@type"] == "messageAnimation" then
                content = "🎬 GIF"
            else
                content = "[Media]"
            end
        end

        -- Format last message
        last_message = last_message .. content

        -- Add timestamp
        if chat.last_message.date then
            local time_str = os.date("%H:%M", chat.last_message.date)
            last_message = time_str .. " " .. last_message
        end

        -- Truncate if too long
        if #last_message > 50 then
            last_message = string.sub(last_message, 1, 47) .. "..."
        end
    end

    return name, photo_path, last_message, chat_type, unread_message_count
end
-- Chat list rendering
local function render_chat(chat)
    local lines = {}
    local highlights = {}

    -- Get chat info
    -- vim.notify(vim.inspect(chat), vim.log.levels.INFO)
    local name, photo_path, last_message, chat_type, unread_message_count = get_chat_info(chat)

    -- Format title with unread count
    local title = name
    

    -- Add profile picture if available
    -- if photo_path then
    --     -- Use chafa to render profile picture
    --     -- vim.notify(photo_path, vim.log.levels.INFO)
    --     if not photos[photo_path] then
    --         local chafa_cmd = string.format("chafa --size 3x3 --clear --symbols space-extra %s", photo_path)
    --         local handle = io.popen(chafa_cmd) -- Can't parse as an integer string "2360633804385789893"
    --         if handle then
    --             local chafa_output = handle:read("*a")
    --             handle:close()
    --             photos[photo_path] = chafa_output
    --         end
    --     end
    --     local chafa_output = photos[photo_path]
    --     table.insert(lines, chafa_output .. ' ' .. title)
    -- else
    --     table.insert(lines, title)
    -- end

    -- Add chat title and last message
    if unread_message_count > 0 then
        title = string.format("%s [%d]", title, unread_message_count)
    end

    table.insert(lines, title)
    if last_message ~= "" then
        table.insert(lines, "  " .. last_message)
    end
    table.insert(lines, "") -- Add separator line

    -- Add highlight for unread messages
    if chat.unread_count and chat.unread_count > 0 then
        table.insert(highlights, {
            group = "TelegramUnread",
            line = #lines - 2, -- Adjust for the separator line
            col_start = #title - string.len(tostring(chat.unread_count)) - 2,
            col_end = #title
        })
    end

    -- Add highlight for selected chat
    if state.selected_chat and chat.id == state.selected_chat.id then
        table.insert(highlights, {
            group = "TelegramChatSelected",
            line = #lines - 2, -- Adjust for the separator line
            col_start = 0,
            col_end = #title
        })
    end

    return lines, highlights
end

-- Update chat list display
local function update_display()
    if not state.buffer or not api.nvim_buf_is_valid(state.buffer) then
        vim.notify("not valid buffer", vim.log.levels.INFO)
        return
    end
    -- vim.notify("update_display", vim.log.levels.INFO)

    -- Prepare lines and highlights
    local all_lines = {}
    local all_highlights = {}

    -- Add folders section
    table.insert(all_lines, "📁 Folders")
    table.insert(all_lines, string.rep("─", 30))

    -- Calculate folder section start line
    local folder_section_start = #all_lines

    -- Add Main chat list
    table.insert(all_lines, state.current_list_type == "main" and "▶ 📥 All Chats" or "  📥 All Chats")

    -- Add Archive
    table.insert(all_lines, state.current_list_type == "archive" and "▶ 🗄️ Archive" or "  🗄️ Archive")

    -- Add chat filters (folders)
    for i, filter in ipairs(state.chat_folders) do
        local prefix = state.current_list_type == "filter" and state.current_filter_id == filter.id and "▶ " or "  "
        table.insert(all_lines, string.format("%s📂 %s", prefix, filter.title))
    end

    -- Add separator
    table.insert(all_lines, "")
    table.insert(all_lines, "Chats")
    table.insert(all_lines, string.rep("─", 30))

    -- Add loading indicator or help text
    if state.loading then
        table.insert(all_lines, "Loading...")
    else
        table.insert(all_lines, "")
        table.insert(all_lines, "Commands:")
        table.insert(all_lines, "j/k - Navigate chats")
        table.insert(all_lines, "Tab/Shift+Tab - Navigate folders")
        table.insert(all_lines, "Enter - Open chat/folder")
        table.insert(all_lines, "r - Reload current list")
    end

    -- Store filter section info for navigation
    state.folder_section = {
        start = folder_section_start,
        main_index = folder_section_start,
        archive_index = folder_section_start + 1,
        folders_start = folder_section_start + 2,
        folders_end = folder_section_start + 1 + #state.chat_folders,
        filters = state.chat_folders -- Store reference to filters
    }

    -- Sort chats by position order and chat ID
    local sorted_chats = vim.tbl_values(state.chats)
    table.sort(sorted_chats, function(a, b)
        local a_pos = state.chat_positions[a.chat_id]
        local b_pos = state.chat_positions[b.chat_id]

        -- Handle missing positions
        if not a_pos then
            return a.chat_id > b.chat_id
        end
        if not b_pos then
            return a.chat_id > b.chat_id
        end

        -- Sort by position order
        if a_pos.order ~= b_pos.order then
            return a_pos.order > b_pos.order
        end

        -- Secondary sort by chat ID
        return a.chat_id > b.chat_id
    end)

    -- Render each chat
    for _, chat in ipairs(sorted_chats) do
        local lines, highlights = render_chat(chat)

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
    local fixed_lines = {}
    for _, line in ipairs(all_lines) do
        local split_lines = vim.split(line, "\n")
        for _, l in ipairs(split_lines) do
            table.insert(fixed_lines, l)
        end
    end
    baleia.buf_set_lines(state.buffer, 0, -1, false, fixed_lines)
    api.nvim_buf_set_option(state.buffer, 'modifiable', false)

    -- Apply highlights
    api.nvim_buf_clear_namespace(state.buffer, -1, 0, -1)

    -- Highlight selected folder
    if state.folder_section then
        local cursor = api.nvim_win_get_cursor(state.window)[1] - 1
        if cursor >= state.folder_section.start and cursor <= state.folder_section.folders_end then
            api.nvim_buf_add_highlight(state.buffer, -1, "TelegramFolderSelected", cursor, 0, -1)
        end
    end

    -- Apply chat highlights
    for _, hl in ipairs(all_highlights) do
        api.nvim_buf_add_highlight(state.buffer, -1, hl.group, hl.line, hl.col_start, hl.col_end)
    end
end

-- Initialize chat list
function M.init()
    vim.notify("Initializing chat list...", vim.log.levels.INFO)

    local handles = layout.get_handles()
    if not handles then
        vim.notify("No layout handles available", vim.log.levels.ERROR)
        return
    end

    vim.notify("Got handles: " .. vim.inspect(handles), vim.log.levels.INFO)

    state.buffer = handles.buffers.chat_list
    state.window = handles.windows.chat_list

    if not state.buffer then
        vim.notify("No chat list buffer", vim.log.levels.ERROR)
        return
    end

    if not api.nvim_buf_is_valid(state.buffer) then
        vim.notify("Invalid chat list buffer", vim.log.levels.ERROR)
        return
    end

    vim.notify("Chat list buffer and window initialized", vim.log.levels.INFO)

    -- Set up keymaps
    local opts = {
        buffer = state.buffer,
        silent = true
    }

    -- Navigation
    vim.keymap.set('n', 'j', M.select_next_chat, {
        buffer = state.buffer,
        silent = true
    })
    vim.keymap.set('n', 'k', M.select_previous_chat, {
        buffer = state.buffer,
        silent = true
    })
    vim.keymap.set('n', '<CR>', function()
        
        local cursor = api.nvim_win_get_cursor(state.window)[1] - 1
        if state.folder_section and cursor >= state.folder_section.start and cursor <= state.folder_section.folders_end then
            M.select_folder_at_line(cursor)
        else
            M.open_selected_chat()
        end
    end, {
        buffer = state.buffer,
        silent = true
    })

    -- Set up event handlers
    events.on(events.events.CHAT_LAST_MESSAGE_UPDATED, function(chat)
        -- Only store chat if we have a position for it in the current list
        -- vim.notify(vim.inspect(tdlib.get_chat(chat.chat_id)), vim.log.levels.INFO)
        -- state.chats[chat.chat_id] = tdlib.get_chat(chat.chat_id)
        if not state.chats[chat.chat_id] then
            tdlib.get_chat(chat.chat_id)
        else
            state.chats[chat.chat_id].last_message = chat.last_message
        end
        update_display()
    end)

    events.on(events.events.CHAT, function(chat)
        -- Only store chat if we have a position for it in the current list
        -- vim.notify(vim.inspect(tdlib.get_chat(chat.chat_id)), vim.log.levels.INFO)
        -- state.chats[chat.chat_id] = tdlib.get_chat(chat.chat_id)

        state.chats[chat.chat_id] = chat
        if chat.photo then
            if not chat.photo.small["local"].is_downloading_completed and chat.photo.small["local"].can_be_downloaded then
                tdlib.download_file(chat.photo.small.id)
            end
        end
        update_display()
    end)

    events.on(events.events.CHAT_DELETED, function(chat_id)
        if state.chats[chat_id] then
            state.chats[chat_id] = nil
        end
        if state.chat_positions[chat_id] then
            state.chat_positions[chat_id] = nil
        end
        update_display()
    end)

    events.on(events.events.CHAT_POSITION_UPDATED, function(data)
        -- Only update position if it matches our current list type
        if data.position.list["@type"] == "chatListMain" and state.current_list_type == "main" or
            data.position.list["@type"] == "chatListArchive" and state.current_list_type == "archive" or
            data.position.list["@type"] == "chatListFilter" and state.current_list_type == "filter" and
            data.position.list.chat_filter_id == state.current_filter_id then
            state.chat_positions[data.chat_id] = data.position
            update_display()
        end
    end)

    events.on(events.events.CHAT_FOLDERS_UPDATED, function(data)
        -- vim.notify("Chat filters update received: " .. vim.inspect(data), vim.log.levels.INFO)
        if data.chat_filters then
            state.chat_folders = data.chat_filters
            update_display()
        end
    end)

    events.on(events.events.CHATS, function(data)
        for _, chat_id in ipairs(data.chat_ids) do
            if not state.chats[chat_id] then
                tdlib.get_chat(chat.chat_id)
            end
        end
    end)

    events.on(events.events.CHAT_LIST_UPDATED, function(data)
        -- vim.notify("Chat list update received: " .. vim.inspect(data), vim.log.levels.INFO)
        -- Check if this update is for our current list type
        local matches = false
        if data.chat_list["@type"] == "chatListMain" and state.current_list_type == "main" then
            matches = true
        elseif data.chat_list["@type"] == "chatListArchive" and state.current_list_type == "archive" then
            matches = true
        elseif data.chat_list["@type"] == "chatListFilter" and state.current_list_type == "filter" and
            data.chat_list.chat_filter_id == state.current_filter_id then
            matches = true
        end

        if matches then
            state.loading = false
            -- Update positions if provided
            if data.positions then
                for _, position in ipairs(data.positions) do
                    if position.chat_id then
                        state.chat_positions[position.chat_id] = position
                    end
                end
            end
            -- Request info for any new chats
            if data.chat_ids then
                for _, chat_id in ipairs(data.chat_ids) do
                    if not state.chats[chat_id] then
                        state.chats[chat_id] = {}
                    end
                end
            end
            update_display()
        end
    end)

    -- Set up folder navigation keymaps
    vim.keymap.set('n', '<Tab>', M.select_next_folder, {
        buffer = state.buffer,
        silent = true
    })
    vim.keymap.set('n', '<S-Tab>', M.select_previous_folder, {
        buffer = state.buffer,
        silent = true
    })

    -- Request chat filters first
    -- vim.notify("Requesting chat filters...", vim.log.levels.INFO)
    -- local filters_id = tdlib.get_chat_filters()
    -- vim.notify("Chat filters request sent with ID: " .. tostring(filters_id), vim.log.levels.INFO)

    -- Load initial chat list after a delay to allow filters to load
    vim.defer_fn(function()
        vim.notify("Switching to main chat list...", vim.log.levels.INFO)
        M.switch_chat_list("main")
    end, 500)

    -- uv.new_timer():start(0, 10, vim.schedule_wrap(function()
    --     update_display()
    -- end))
end

-- Switch chat list type
function M.switch_chat_list(list_type, filter_id)
    vim.notify("Switching chat list to: " .. list_type .. (filter_id and (" (filter " .. filter_id .. ")") or ""),
        vim.log.levels.INFO)

    state.loading = true
    state.current_list_type = list_type
    state.current_filter_id = filter_id
    state.chats = {} -- Clear current chats
    state.chat_positions = {} -- Clear positions
    update_display()

    -- Get appropriate chat list
    local chat_list
    if list_type == "main" then
        chat_list = tdlib.get_chat_list_main()
    elseif list_type == "archive" then
        chat_list = tdlib.get_chat_list_archive()
    elseif list_type == "filter" then
        chat_list = tdlib.get_chat_list_filter(filter_id)
    end

    -- Load chats for the selected list
    local request_id = tdlib.load_chats(chat_list, 100)
    vim.notify("Loading chats for " .. list_type .. " list with request ID: " .. tostring(request_id),
        vim.log.levels.INFO)

    -- Reset loading state after a longer delay
    vim.defer_fn(function()
        if state.loading then
            state.loading = false
            update_display()
            vim.notify("Chat list load timeout - displaying available chats. Try reloading with 'r'",
                vim.log.levels.WARN)
        end
    end, 5000)

    -- Ensure reload keymap exists
    pcall(vim.keymap.del, 'n', 'r', {
        buffer = state.buffer
    })
    vim.keymap.set('n', 'r', M.load_chats, {
        buffer = state.buffer,
        silent = true
    })
end

-- Load chats from TDLib
function M.load_chats()
    M.switch_chat_list(state.current_list_type, state.current_filter_id)
end

-- Select next chat
function M.select_next_chat()
    local sorted_chats = vim.tbl_values(state.chats)
    if #sorted_chats == 0 then
        return
    end

    local current_index = 1
    if state.selected_chat then
        for i, chat in ipairs(sorted_chats) do
            if chat.id == state.selected_chat.id then
                current_index = i
                break
            end
        end
    end

    local next_index = current_index % #sorted_chats + 1
    state.selected_chat = sorted_chats[next_index]

    update_display()
    events.emit(events.events.UI_CHAT_SELECTED, state.selected_chat)
end

-- Select previous chat
function M.select_previous_chat()
    local sorted_chats = vim.tbl_values(state.chats)
    if #sorted_chats == 0 then
        return
    end

    local current_index = 1
    if state.selected_chat then
        for i, chat in ipairs(sorted_chats) do
            if chat.id == state.selected_chat.id then
                current_index = i
                break
            end
        end
    end

    local prev_index = (current_index - 2) % #sorted_chats + 1
    state.selected_chat = sorted_chats[prev_index]

    update_display()
    events.emit(events.events.UI_CHAT_SELECTED, state.selected_chat)
end

-- Open selected chat
function M.open_selected_chat()
    if not state.selected_chat then
        return
    end
    events.emit(events.events.UI_CHAT_SELECTED, state.selected_chat)
end

-- Open chat by ID
function M.open_chat(chat_id)
    local chat = state.chats[chat_id]
    if chat then
        state.selected_chat = chat
        update_display()
        events.emit(events.events.UI_CHAT_SELECTED, chat)
    end
end

-- Get current chat
function M.get_current_chat()
    return state.selected_chat
end

-- Select next folder
function M.select_next_folder()
    if not state.folder_section then
        return
    end

    local cursor = api.nvim_win_get_cursor(state.window)[1] - 1
    local next_line

    -- If cursor is not in folder section, move to first folder
    if cursor < state.folder_section.start or cursor > state.folder_section.folders_end then
        next_line = state.folder_section.main_index
    else
        next_line = cursor + 1
        if next_line > state.folder_section.folders_end then
            next_line = state.folder_section.main_index
        end
    end

    api.nvim_win_set_cursor(state.window, {next_line + 1, 0})
    M.select_folder_at_line(next_line)
end

-- Select previous folder
function M.select_previous_folder()
    if not state.folder_section then
        return
    end

    local cursor = api.nvim_win_get_cursor(state.window)[1] - 1
    local prev_line

    -- If cursor is not in folder section, move to last folder
    if cursor < state.folder_section.start or cursor > state.folder_section.folders_end then
        prev_line = state.folder_section.folders_end
    else
        prev_line = cursor - 1
        if prev_line < state.folder_section.main_index then
            prev_line = state.folder_section.folders_end
        end
    end

    api.nvim_win_set_cursor(state.window, {prev_line + 1, 0})
    M.select_folder_at_line(prev_line)
end

-- Select folder at line
function M.select_folder_at_line(line)
    if not state.folder_section then
        return
    end

    -- Main chat list
    if line == state.folder_section.main_index then
        M.switch_chat_list("main")
        return
    end

    -- Archive
    if line == state.folder_section.archive_index then
        M.switch_chat_list("archive")
        return
    end

    -- Chat filters (folders)
    if line >= state.folder_section.folders_start and line <= state.folder_section.folders_end then
        local filter_index = line - state.folder_section.folders_start + 1
        local filter = state.folder_section.filters[filter_index]
        if filter then
            vim.notify("Switching to filter: " .. vim.inspect(filter), vim.log.levels.INFO)
            M.switch_chat_list("filter", filter.id)
        end
    end
end

-- Clean up
function M.cleanup()
    -- Clean up keymaps if buffer is still valid
    if state.buffer and api.nvim_buf_is_valid(state.buffer) then
        pcall(vim.keymap.del, 'n', 'j', {
            buffer = state.buffer
        })
        pcall(vim.keymap.del, 'n', 'k', {
            buffer = state.buffer
        })
        pcall(vim.keymap.del, 'n', '<CR>', {
            buffer = state.buffer
        })
        pcall(vim.keymap.del, 'n', '<Tab>', {
            buffer = state.buffer
        })
        pcall(vim.keymap.del, 'n', '<S-Tab>', {
            buffer = state.buffer
        })
        pcall(vim.keymap.del, 'n', 'r', {
            buffer = state.buffer
        })
    end

    -- Reset state
    state.chats = {}
    state.chat_positions = {}
    state.selected_chat = nil
    state.loading = false
    state.buffer = nil
    state.window = nil
    state.current_list_type = "main"
    state.current_filter_id = nil
    state.chat_folders = {}
    state.main_chat_list_position = 0
    state.selected_folder_index = nil
    state.folder_section = nil
end

return M
