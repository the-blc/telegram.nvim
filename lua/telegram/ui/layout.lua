-- Layout manager for Telegram.nvim
local api = vim.api
local events = require('telegram.core.events')

local M = {}

-- Layout configuration
local config = {
    chat_list = {
        width = "20%",
        position = "left",
    },
    messages = {
        width = "80%",
        position = "right",
    },
    input = {
        height = 3,
        position = "bottom",
    },
}

-- Layout state
local state = {
    windows = {
        chat_list = nil,
        messages = nil,
        input = nil,
    },
    buffers = {
        chat_list = nil,
        messages = nil,
        input = nil,
    },
    original_window = nil,
    layout_initialized = false,
}

-- Initialize layout configuration
function M.init(opts)
    config = vim.tbl_deep_extend("force", config, opts or {})
end

-- Calculate window dimensions
local function calculate_dimensions()
    local total_width = vim.o.columns
    local total_height = vim.o.lines - vim.o.cmdheight - 1
    
    -- Calculate chat list width
    local chat_list_width
    if type(config.chat_list.width) == "string" and config.chat_list.width:match("%%$") then
        local percentage = tonumber(config.chat_list.width:match("(%d+)%%"))
        chat_list_width = math.floor(total_width * percentage / 100)
    else
        chat_list_width = tonumber(config.chat_list.width) or math.floor(total_width * 0.2)
    end
    
    -- Calculate message view width
    local messages_width = total_width - chat_list_width
    
    -- Calculate heights
    local input_height = config.input.height
    local content_height = total_height - input_height
    
    return {
        total_width = total_width,
        total_height = total_height,
        chat_list_width = chat_list_width,
        messages_width = messages_width,
        content_height = content_height,
        input_height = input_height,
    }
end

-- Create buffer with options
local function create_buffer(name, options)
    local buf = api.nvim_create_buf(false, true)
    api.nvim_buf_set_name(buf, name)
    
    -- Set buffer options
    for opt, value in pairs(options or {}) do
        api.nvim_buf_set_option(buf, opt, value)
    end
    
    return buf
end

-- Create window with options
local function create_window(buf, options)
    local win = api.nvim_open_win(buf, false, options)
    
    -- Set window options
    api.nvim_win_set_option(win, 'wrap', false)
    api.nvim_win_set_option(win, 'number', false)
    api.nvim_win_set_option(win, 'relativenumber', false)
    api.nvim_win_set_option(win, 'signcolumn', 'no')
    
    return win
end

-- Create layout windows
function M.create(callback)
    -- Store current window
    state.original_window = api.nvim_get_current_win()
    
    -- Store callback for when layout is ready
    local on_ready = callback
    
    -- Calculate dimensions
    local dim = calculate_dimensions()
    
    -- Create chat list
    state.buffers.chat_list = create_buffer("TelegramChatList", {
        buftype = "nofile",
        swapfile = false,
        modifiable = false,
    })
    
    state.windows.chat_list = create_window(state.buffers.chat_list, {
        relative = 'editor',
        width = dim.chat_list_width,
        height = dim.content_height,
        row = 0,
        col = 0,
        style = 'minimal',
        border = 'single',
    })
    
    -- Create message view
    state.buffers.messages = create_buffer("TelegramMessages", {
        buftype = "nofile",
        swapfile = false,
        modifiable = false,
    })
    
    state.windows.messages = create_window(state.buffers.messages, {
        relative = 'editor',
        width = dim.messages_width,
        height = dim.content_height,
        row = 0,
        col = dim.chat_list_width,
        style = 'minimal',
        border = 'single',
    })
    
    -- Create input area
    state.buffers.input = create_buffer("TelegramInput", {
        buftype = "prompt",
        swapfile = false,
    })
    
    state.windows.input = create_window(state.buffers.input, {
        relative = 'editor',
        width = dim.total_width,
        height = dim.input_height,
        row = dim.content_height,
        col = 0,
        style = 'minimal',
        border = 'single',
    })
    
    -- Set up input prompt
    vim.fn.prompt_setprompt(state.buffers.input, "Message: ")
    
    -- Set up autocommands
    local group = api.nvim_create_augroup('TelegramLayout', { clear = true })
    
    -- Handle window close
    api.nvim_create_autocmd('WinClosed', {
        group = group,
        callback = function(args)
            local win_id = tonumber(args.match)
            if win_id and (
                win_id == state.windows.chat_list or
                win_id == state.windows.messages or
                win_id == state.windows.input
            ) then
                M.destroy()
            end
        end,
    })
    
    -- Handle VimResized
    api.nvim_create_autocmd('VimResized', {
        group = group,
        callback = function()
            M.resize()
        end,
    })
    
    -- Mark layout as initialized
    state.layout_initialized = true
    
    -- Initialize UI components
    
    -- Emit layout changed event
    events.emit(events.events.UI_LAYOUT_CHANGED, {
        windows = state.windows,
        buffers = state.buffers,
    })

    -- Call callback if provided
    if on_ready then
        vim.schedule(function()
            on_ready()
        end)
    end
end

-- Resize windows
function M.resize()
    if not state.layout_initialized then
        return
    end
    
    local dim = calculate_dimensions()
    
    -- Update chat list window
    api.nvim_win_set_config(state.windows.chat_list, {
        width = dim.chat_list_width,
        height = dim.content_height,
    })
    
    -- Update message view window
    api.nvim_win_set_config(state.windows.messages, {
        width = dim.messages_width,
        height = dim.content_height,
        col = dim.chat_list_width,
    })
    
    -- Update input window
    api.nvim_win_set_config(state.windows.input, {
        width = dim.total_width,
        height = dim.input_height,
        row = dim.content_height,
    })
    
    -- Emit layout changed event
    events.emit(events.events.UI_LAYOUT_CHANGED, {
        windows = state.windows,
        buffers = state.buffers,
    })
end

-- Destroy layout
function M.destroy()
    if not state.layout_initialized then
        return
    end
    
    -- Close windows
    for _, win in pairs(state.windows) do
        if win and api.nvim_win_is_valid(win) then
            api.nvim_win_close(win, true)
        end
    end
    
    -- Delete buffers
    for _, buf in pairs(state.buffers) do
        if buf and api.nvim_buf_is_valid(buf) then
            api.nvim_buf_delete(buf, { force = true })
        end
    end
    
    -- Clean up UI components
    local chat_list = require('telegram.ui.chat_list')
    chat_list.cleanup()
    
    -- Reset state
    state.windows = {
        chat_list = nil,
        messages = nil,
        input = nil,
    }
    state.buffers = {
        chat_list = nil,
        messages = nil,
        input = nil,
    }
    state.layout_initialized = false
    
    -- Return to original window if it exists
    if state.original_window and api.nvim_win_is_valid(state.original_window) then
        api.nvim_set_current_win(state.original_window)
    end
    
    -- Emit layout changed event
    events.emit(events.events.UI_LAYOUT_CHANGED, nil)
end

-- Get window and buffer handles
function M.get_handles()
    return {
        windows = state.windows,
        buffers = state.buffers,
    }
end

-- Check if layout is initialized
function M.is_initialized()
    return state.layout_initialized
end

return M
