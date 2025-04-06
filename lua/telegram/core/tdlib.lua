-- TDLib integration for Telegram.nvim
local ffi = require('ffi')
local compat = require('telegram.core.tdlib_compat')
local events = require('telegram.core.events')
local vim = vim
local api = vim.api
local uv = vim.loop

local M = {}

-- Local state
local state = {
    client_wrapper = nil,
    running = false,
    handlers = {},
    updates_timer = nil,
    auth_state = nil,
    config = nil -- Store TDLib config
}

-- Make config accessible to other modules
M.config = nil

-- JSON helpers
local json = {
    encode = vim.json.encode,
    decode = vim.json.decode
}

-- Generate request ID
local request_id = 0
local function get_request_id()
    request_id = request_id + 1
    return request_id
end

-- Initialize TDLib client
function M.init(config)
    if state.client_wrapper then
        return
    end

    -- Make config immediately available to other modules
    M.config = config
    state.config = config

    -- Detect and load TDLib
    local tdlib_info = compat.detect_tdlib_api(config.path)
    state.client_wrapper = compat.create_client_wrapper(tdlib_info)

    -- Create client
    state.client_wrapper:init()

    -- Set up a log file for TDLib
    local log_file = vim.fn.stdpath("cache") .. "/telegram-tdlib.log"

    -- Set up logging
    local log_request = json.encode({
        ["@type"] = "setLogStream",
        log_stream = {
            ["@type"] = "logStreamFile",
            path = log_file,
            max_file_size = 10 * 1024 * 1024, -- 10MB
            redirect_stderr = true
        }
    })

    state.client_wrapper:execute(log_request)

    -- Set minimal log verbosity
    local verbosity_request = json.encode({
        ["@type"] = "setLogVerbosityLevel",
        new_verbosity_level = 0 -- Minimal logging
    })

    state.client_wrapper:execute(verbosity_request)

    -- Set up update polling
    state.running = true
    state.updates_timer = uv.new_timer()

    -- Start update polling with error handling
    state.updates_timer:start(0, 10, vim.schedule_wrap(function()
        if not state.running then
            return
        end

        -- Protected update receiving
        local ok, response = pcall(function()
            return state.client_wrapper:receive(0.01)
        end)

        if not ok then
            vim.notify("Error receiving TDLib update: " .. response, vim.log.levels.ERROR)
            return
        end

        if response == nil or response == ffi.NULL then
            return
        end

        -- Protected update parsing
        local ok, update = pcall(json.decode, ffi.string(response))
        if not ok then
            -- Log to file instead of notifying
            local log_msg = string.format("Failed to parse TDLib update: %s\n", update)
            local log_file = io.open(vim.fn.stdpath("cache") .. "/telegram-tdlib-errors.log", "a")
            if log_file then
                log_file:write(os.date("%Y-%m-%d %H:%M:%S ") .. log_msg)
                log_file:close()
            end
            return
        end

        -- Protected update handling
        pcall(M.handle_update, update)
    end))

    -- Create required directories
    local db_dir = vim.fn.stdpath("data") .. "/telegram-tdlib"
    local files_dir = vim.fn.stdpath("data") .. "/telegram-files"
    vim.fn.mkdir(db_dir, "p")
    vim.fn.mkdir(files_dir, "p")

    -- Request current authorization state to start the auth flow
    vim.defer_fn(function()
        M.send({
            ["@type"] = "getAuthorizationState"
        })
        vim.notify("Starting authorization flow...", vim.log.levels.INFO)
    end, 100)
end

-- Send request to TDLib
function M.send(request)
    if not state.client_wrapper then
        error("TDLib client not initialized")
    end

    -- Add request ID if not present
    if not request["@extra"] then
        request["@extra"] = get_request_id()
    end

    -- Convert request to JSON
    local ok, json_request = pcall(json.encode, request)
    if not ok then
        error("Failed to encode request: " .. json_request)
    end

    -- Log request
    --vim.notify("Sending request: " .. vim.inspect(request), vim.log.levels.INFO)

    -- Send request
    state.client_wrapper:send(json_request)

    -- Log request ID
    -- vim.notify("Request sent with ID: " .. tostring(request["@extra"]), vim.log.levels.INFO)

    return request["@extra"]
end

-- Execute synchronous request
function M.execute(request)
    if not state.client_wrapper then
        error("TDLib client not initialized")
    end

    -- Convert request to JSON
    local ok, json_request = pcall(json.encode, request)
    if not ok then
        error("Failed to encode request: " .. json_request)
    end

    -- Execute request
    local response = state.client_wrapper:execute(json_request)
    if response == nil or response == ffi.NULL then
        return nil
    end

    -- Parse response
    local ok, result = pcall(json.decode, ffi.string(response))
    if not ok then
        error("Failed to parse response: " .. result)
    end

    return result
end

-- Register update handler
function M.on(update_type, handler)
    if not state.handlers[update_type] then
        state.handlers[update_type] = {}
    end
    table.insert(state.handlers[update_type], handler)
end

-- Handle update from TDLib
function M.handle_update(update)
    if not update["@type"] then
        return
    end

    if update.chat_id then
        update.chat_id = tostring(update.chat_id)
    end

    local updates_dir = "./event_responses" -- change to your desired directory path
    local filename = updates_dir .. "/" .. update["@type"] .. ".txt"

    -- If the file does not exist then write to it.
    if not uv.fs_stat(filename) then
        local f = io.open(filename, "w")
        if f then
            local content = vim.inspect(update)
            f:write(content)
            f:close()
  --          vim.notify("Wrote update to file: " .. filename, vim.log.levels.INFO)
        else
--            vim.notify("Failed to write update to file: " .. filename, vim.log.levels.ERROR)
        end
    end

    -- vim.notify("Received update: " .. vim.inspect(update), vim.log.levels.INFO)

    -- Special handling for authentication states
    if update["@type"] == "updateAuthorizationState" then
        state.auth_state = update.authorization_state["@type"]
        vim.notify("Auth state changed: " .. state.auth_state, vim.log.levels.INFO)

        if state.auth_state == "authorizationStateClosed" then
            M.cleanup()
        end
    end

    -- Call registered handlers
    local handlers = state.handlers[update["@type"]]
    if handlers then
        for _, handler in ipairs(handlers) do
            local ok, err = pcall(handler, update)
            if not ok then
                vim.notify("Error in handler for " .. update["@type"] .. ": " .. err, vim.log.levels.ERROR)
            end
        end
    else 
        events.handle_tdlib_update(update)
    end
end

-- Clean up TDLib client
function M.cleanup()
    if state.updates_timer then
        state.updates_timer:stop()
        state.updates_timer:close()
        state.updates_timer = nil
    end

    if state.client_wrapper then
        state.client_wrapper:cleanup()
        state.client_wrapper = nil
    end

    state.running = false
    state.handlers = {}
    state.auth_state = nil
end

-- Get current authorization state
function M.get_auth_state()
    return state.auth_state
end

-- High-level API functions

-- Send message
function M.send_message(chat_id, text)
    return M.send({
        ["@type"] = "sendMessage",
        chat_id = chat_id,
        input_message_content = {
            ["@type"] = "inputMessageText",
            text = {
                ["@type"] = "formattedText",
                text = text
            }
        }
    })
end

-- Send file
function M.send_file(chat_id, path)
    -- First upload the file
    local file_id = M.send({
        ["@type"] = "uploadFile",
        file = {
            ["@type"] = "inputFileLocal",
            path = path
        },
        priority = 1
    })

    -- Then send it as a document
    return M.send({
        ["@type"] = "sendMessage",
        chat_id = chat_id,
        input_message_content = {
            ["@type"] = "inputMessageDocument",
            document = {
                ["@type"] = "inputFileId",
                id = file_id
            }
        }
    })
end

-- Chat list functions
function M.get_chat_list_main()
    return {
        ["@type"] = "chatListMain"
    }
end

-- Get chat filters (folders)
function M.get_chat_filters()
    return M.send({
        ["@type"] = "getChatFilters"
    })
end

function M.get_chat_list_archive()
    return {
        ["@type"] = "chatListArchive"
    }
end

function M.get_chat_list_filter(filter_id)
    return {
        ["@type"] = "chatListFilter",
        chat_filter_id = filter_id
    }
end

-- Load chats from a specific chat list
function M.load_chats(chat_list, limit)
    vim.notify("Loading chats for list: " .. vim.inspect(chat_list), vim.log.levels.INFO)

    -- First request to load chats
    local request_id = M.send({
        ["@type"] = "loadChats",
        chat_list = chat_list,
        limit = limit or 100
    })

    -- Then request to get loaded chats
    vim.defer_fn(function()
        local get_chats_id = M.send({
            ["@type"] = "getChats",
            chat_list = chat_list,
            limit = limit or 100
        })
        vim.notify("Requested chat list with ID: " .. tostring(get_chats_id), vim.log.levels.INFO)
    end, 500) -- Increased delay to ensure loadChats completes

    return request_id
end

-- Handle chat list response
M.on("chats", function(response)
    vim.notify("Received chats response: " .. vim.inspect(response), vim.log.levels.INFO)
    if response.chat_list then
        M.handle_update({
            ["@type"] = "chats",
            chat_list = response.chat_list,
            total_count = response.total_count,
            chat_ids = response.chat_ids
        })
    end
end)

-- Get chat info
function M.get_chat(chat_id)
    return M.send({
        ["@type"] = "getChat",
        chat_id = chat_id
    })
end

-- Get chat history
function M.get_chat_history(chat_id, from_message_id, limit)
    return M.send({
        ["@type"] = "getChatHistory",
        chat_id = chat_id,
        from_message_id = from_message_id,
        offset = 0,
        limit = limit or 50
    })
end

-- Download file
function M.download_file(file_id, priority)
    return M.send({
        ["@type"] = "downloadFile",
        file_id = file_id,
        priority = priority or 1
    })
end

return M
