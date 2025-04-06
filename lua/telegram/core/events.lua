-- Event system for Telegram.nvim
local api = vim.api
local uv = vim.loop

local M = {}

-- Event types
M.events = {
    -- Chat events
    CHATS = "chats",
    CHAT = "chat",
    CHAT_UPDATED = "chat_updated",
    CHAT_DELETED = "chat_deleted",
    CHAT_TITLE_UPDATED = "chat_title_updated",
    CHAT_PHOTO_UPDATED = "chat_photo_updated",
    CHAT_PERMISSIONS_UPDATED = "chat_permissions_updated",
    CHAT_LAST_MESSAGE_UPDATED = "chat_last_message_updated",
    CHAT_POSITION_UPDATED = "chat_position_updated",
    CHAT_LIST_UPDATED = "chat_list_updated",
    CHAT_FOLDERS_UPDATED = "chat_folders_updated",
    CHAT_FOLDER_INFO_UPDATED = "chat_folder_info_updated",
    CHAT_READ_INBOX_UPDATED = "chat_read_inbox_updated",
    CHAT_READ_OUTBOX_UPDATED = "chat_read_outbox_updated",
    
    -- Message events
    MESSAGE_RECEIVED = "message_received",
    MESSAGE_EDITED = "message_edited",
    MESSAGE_DELETED = "message_deleted",
    MESSAGE_PINNED = "message_pinned",
    MESSAGE_UNPINNED = "message_unpinned",
    
    -- Media events
    FILE_DOWNLOAD_STARTED = "file_download_started",
    FILE_DOWNLOAD_PROGRESS = "file_download_progress",
    FILE_DOWNLOAD_COMPLETED = "file_download_completed",
    FILE_UPLOAD_STARTED = "file_upload_started",
    FILE_UPLOAD_PROGRESS = "file_upload_progress",
    FILE_UPLOAD_COMPLETED = "file_upload_completed",
    
    -- User events
    USER_STATUS_UPDATED = "user_status_updated",
    USER_PROFILE_UPDATED = "user_profile_updated",
    
    -- Connection events
    CONNECTION_STATE_CHANGED = "connection_state_changed",
    AUTHORIZATION_STATE_CHANGED = "authorization_state_changed",
    
    -- UI events
    UI_CHAT_SELECTED = "ui_chat_selected",
    UI_MESSAGE_SELECTED = "ui_message_selected",
    UI_LAYOUT_CHANGED = "ui_layout_changed",
    UI_ERROR = "ui_error",
}

-- Local state
local state = {
    handlers = {},
    queued_events = {},
    processing = false,
    timer = nil,
}

-- Initialize event system
function M.init()
    -- Set up event processing timer
    state.timer = uv.new_timer()
    state.timer:start(0, 10, vim.schedule_wrap(function()
        M.process_events()
    end))
end

-- Subscribe to event
function M.on(event_type, handler)
    if not state.handlers[event_type] then
        state.handlers[event_type] = {}
    end
    table.insert(state.handlers[event_type], handler)
end

-- Unsubscribe from event
function M.off(event_type, handler)
    if not state.handlers[event_type] then
        return
    end
    
    for i, h in ipairs(state.handlers[event_type]) do
        if h == handler then
            table.remove(state.handlers[event_type], i)
            break
        end
    end
end

-- Emit event
function M.emit(event_type, data)
    data.chat_id = tostring(data.chat_id)
    table.insert(state.queued_events, {
        type = event_type,
        data = data,
        time = uv.now(),
    })
end

-- Process queued events
function M.process_events()
    if state.processing or #state.queued_events == 0 then
        return
    end
    
    state.processing = true
    
    -- Process all queued events
    while #state.queued_events > 0 do
        local event = table.remove(state.queued_events, 1)
        
        -- Call handlers
        if state.handlers[event.type] then
            for _, handler in ipairs(state.handlers[event.type]) do
                local ok, err = pcall(handler, event.data)
                if not ok then
                    vim.notify(
                        string.format("Error in event handler for %s: %s", event.type, err),
                        vim.log.levels.ERROR
                    )
                end
            end
        end
    end
    
    state.processing = false
end

-- Map TDLib updates to events
function M.handle_tdlib_update(update)
    if not update["@type"] then return end
    
    -- Chat updates
    if update["@type"] == "updateNewChat" then
        M.emit(M.events.CHAT_UPDATED, update.chat)
    elseif update["@type"] == "updateChatTitle" then
        M.emit(M.events.CHAT_TITLE_UPDATED, {
            chat_id = update.chat_id,
            title = update.title,
        })
    elseif update["@type"] == "updateChatPhoto" then
        M.emit(M.events.CHAT_PHOTO_UPDATED, {
            chat_id = update.chat_id,
            photo = update.photo,
        })
    elseif update["@type"] == "chat" then
        update.chat_id = update.id
        M.emit(M.events.CHAT, update)
    elseif update["@type"] == "updateChatLastMessage" then
        -- Update chat positions if provided
        if update.positions and #update.positions > 0 then
            for _, position in ipairs(update.positions) do
                M.emit(M.events.CHAT_POSITION_UPDATED, {
                    chat_id = update.chat_id,
                    position = position
                })
            end
        end
        
        -- Emit last message update
        M.emit(M.events.CHAT_LAST_MESSAGE_UPDATED, {
            chat_id = update.chat_id,
            last_message = update.last_message
        })
    elseif update["@type"] == "updateChatPosition" then
        M.emit(M.events.CHAT_POSITION_UPDATED, {
            chat_id = update.chat_id,
            position = update.position
        })
    elseif update["@type"] == "updateChatFolders" then
        M.emit(M.events.CHAT_FOLDERS_UPDATED, {
            chat_filters = update.chat_filters
        })
    elseif update["@type"] == "updateChatAddedToList" then
        M.emit(M.events.CHAT_LIST_UPDATED, {
            chat_id = update.chat_id,
            chat_list = update.chat_list
        })
    elseif update["@type"] == "chats" then
        -- When we receive the chat list, emit a list update event
        if update.chat_list then
            M.emit(M.events.CHATS, {
                chat_list = update.chat_list,
                total_count = update.total_count
            })
        end
    elseif update["@type"] == "updateChatAddedToList" then
        -- When a chat is added to a list, emit a list update event
        M.emit(M.events.CHAT_LIST_UPDATED, {
            chat_id = update.chat_id,
            chat_list = update.chat_list,
            positions = update.positions
        })
    elseif update["@type"] == "updateChatRemovedFromList" then
        -- When a chat is removed from a list
        M.emit(M.events.CHAT_LIST_UPDATED, {
            chat_id = update.chat_id,
            chat_list = update.chat_list
        })
    elseif update["@type"] == "updateChatReadInbox" then
        M.emit(M.events.CHAT_READ_INBOX_UPDATED, {
            chat_id = update.chat_id,
            last_read_inbox_message_id = update.last_read_inbox_message_id,
            unread_count = update.unread_count
        })
    elseif update["@type"] == "updateChatReadOutbox" then
        M.emit(M.events.CHAT_READ_OUTBOX_UPDATED, {
            chat_id = update.chat_id,
            last_read_outbox_message_id = update.last_read_outbox_message_id
        })
    elseif update["@type"] == "updateChatPermissions" then
        M.emit(M.events.CHAT_PERMISSIONS_UPDATED, {
            chat_id = update.chat_id,
            permissions = update.permissions
        })
    elseif update["@type"] == "updateChatDraftMessage" then
        M.emit(M.events.CHAT_LAST_MESSAGE_UPDATED, {
            chat_id = update.chat_id,
            draft_message = update.draft_message,
            positions = update.positions
        })
    elseif update["@type"] == "updateChatUnreadMentionCount" then
        M.emit(M.events.CHAT_UPDATED, {
            chat_id = update.chat_id,
            unread_mention_count = update.unread_mention_count
        })
    elseif update["@type"] == "updateChatUnreadReactionCount" then
        M.emit(M.events.CHAT_UPDATED, {
            chat_id = update.chat_id,
            unread_reaction_count = update.unread_reaction_count
        })
    elseif update["@type"] == "updateChatVideoChat" then
        M.emit(M.events.CHAT_UPDATED, {
            chat_id = update.chat_id,
            video_chat = update.video_chat
        })
    elseif update["@type"] == "updateChatMessageSender" then
        M.emit(M.events.CHAT_UPDATED, {
            chat_id = update.chat_id,
            message_sender = update.message_sender
        })
    elseif update["@type"] == "updateChatHasScheduledMessages" then
        M.emit(M.events.CHAT_UPDATED, {
            chat_id = update.chat_id,
            has_scheduled_messages = update.has_scheduled_messages
        })
    elseif update["@type"] == "updateChatIsMarkedAsUnread" then
        M.emit(M.events.CHAT_UPDATED, {
            chat_id = update.chat_id,
            is_marked_as_unread = update.is_marked_as_unread
        })
    
    -- Message updates
    elseif update["@type"] == "updateNewMessage" then
        M.emit(M.events.MESSAGE_RECEIVED, update.message)
    elseif update["@type"] == "updateMessageEdited" then
        M.emit(M.events.MESSAGE_EDITED, {
            chat_id = update.chat_id,
            message_id = update.message_id,
            edit_date = update.edit_date,
            reply_markup = update.reply_markup,
        })
    elseif update["@type"] == "updateMessageContent" then
        M.emit(M.events.MESSAGE_EDITED, {
            chat_id = update.chat_id,
            message_id = update.message_id,
            new_content = update.new_content,
        })
    elseif update["@type"] == "updateDeleteMessages" then
        M.emit(M.events.MESSAGE_DELETED, {
            chat_id = update.chat_id,
            message_ids = update.message_ids,
            is_permanent = update.is_permanent,
            from_cache = update.from_cache
        })
    elseif update["@type"] == "updateMessageIsPinned" then
        if update.is_pinned then
            M.emit(M.events.MESSAGE_PINNED, {
                chat_id = update.chat_id,
                message_id = update.message_id
            })
        else
            M.emit(M.events.MESSAGE_UNPINNED, {
                chat_id = update.chat_id,
                message_id = update.message_id
            })
        end
    elseif update["@type"] == "updateMessageInteractionInfo" then
        M.emit(M.events.MESSAGE_EDITED, {
            chat_id = update.chat_id,
            message_id = update.message_id,
            interaction_info = update.interaction_info
        })
    elseif update["@type"] == "updateMessageSendSucceeded" then
        M.emit(M.events.MESSAGE_EDITED, {
            chat_id = update.message.chat_id,
            message = update.message,
            old_message_id = update.old_message_id
        })
    elseif update["@type"] == "updateMessageSendFailed" then
        M.emit(M.events.UI_ERROR, {
            chat_id = update.message.chat_id,
            message = update.message,
            old_message_id = update.old_message_id,
            error = update.error
        })
    
    -- File updates
    elseif update["@type"] == "updateFile" then
        local file = update.file
        if file.local_.is_downloading_active then
            M.emit(M.events.FILE_DOWNLOAD_PROGRESS, {
                file_id = file.id,
                downloaded_size = file.local_.downloaded_size,
                total_size = file.size,
            })
        elseif file.local_.is_downloading_completed then
            M.emit(M.events.FILE_DOWNLOAD_COMPLETED, {
                file_id = file.id,
                path = file.local_.path,
            })
        elseif file.remote.is_uploading_active then
            M.emit(M.events.FILE_UPLOAD_PROGRESS, {
                file_id = file.id,
                uploaded_size = file.remote.uploaded_size,
                total_size = file.size,
            })
        elseif file.remote.is_uploading_completed then
            M.emit(M.events.FILE_UPLOAD_COMPLETED, {
                file_id = file.id,
                remote_id = file.remote.id,
            })
        end
    
    -- User updates
    elseif update["@type"] == "updateUser" then
        M.emit(M.events.USER_PROFILE_UPDATED, update.user)
    elseif update["@type"] == "updateUserStatus" then
        M.emit(M.events.USER_STATUS_UPDATED, {
            user_id = update.user_id,
            status = update.status,
        })
    elseif update["@type"] == "updateUserFullInfo" then
        M.emit(M.events.USER_PROFILE_UPDATED, {
            user_id = update.user_id,
            user_full_info = update.user_full_info
        })
    elseif update["@type"] == "updateBasicGroup" then
        M.emit(M.events.CHAT_UPDATED, {
            basic_group = update.basic_group
        })
    elseif update["@type"] == "updateSupergroup" then
        M.emit(M.events.CHAT_UPDATED, {
            supergroup = update.supergroup
        })
    elseif update["@type"] == "updateBasicGroupFullInfo" then
        M.emit(M.events.CHAT_UPDATED, {
            basic_group_id = update.basic_group_id,
            basic_group_full_info = update.basic_group_full_info
        })
    elseif update["@type"] == "updateSupergroupFullInfo" then
        M.emit(M.events.CHAT_UPDATED, {
            supergroup_id = update.supergroup_id,
            supergroup_full_info = update.supergroup_full_info
        })
    
    -- Connection updates
    elseif update["@type"] == "updateConnectionState" then
        M.emit(M.events.CONNECTION_STATE_CHANGED, update.state)
    elseif update["@type"] == "updateAuthorizationState" then
        M.emit(M.events.AUTHORIZATION_STATE_CHANGED, update.authorization_state)
    end
end

-- Clean up
function M.cleanup()
    if state.timer then
        state.timer:stop()
        state.timer:close()
        state.timer = nil
    end
    
    state.handlers = {}
    state.queued_events = {}
    state.processing = false
end

return M
