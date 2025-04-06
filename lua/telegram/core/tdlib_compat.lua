-- TDLib Compatibility Layer for Telegram.nvim
-- This module handles both standard and JSON client TDLib API versions

local ffi = require('ffi')
local vim = vim

local M = {}

-- Try to detect which TDLib API is available
function M.detect_tdlib_api(path)
    local success, lib = pcall(ffi.load, path)
    if not success then
        error("Failed to load TDLib: " .. lib)
    end
    
    -- Declare both types of APIs and see which one is available
    ffi.cdef[[
        // Standard TDLib API
        int td_create_client_id();
        void td_send(int client_id, const char *request);
        const char* td_receive(double timeout);
        const char* td_execute(const char *request);
        
        // JSON Client TDLib API
        void *td_json_client_create();
        void td_json_client_destroy(void *client);
        void td_json_client_send(void *client, const char *request);
        const char *td_json_client_receive(void *client, double timeout);
        const char *td_json_client_execute(void *client, const char *request);
    ]]
    
    -- Check which API is available
    local td_api_type
    local has_standard = pcall(function() return lib.td_create_client_id end)
    local has_json = pcall(function() return lib.td_json_client_create end)
    
    if has_standard then
        td_api_type = "standard"
        vim.notify("Using standard TDLib API", vim.log.levels.INFO)
    elseif has_json then
        td_api_type = "json"
        vim.notify("Using JSON client TDLib API", vim.log.levels.INFO)
    else
        error("No compatible TDLib API found in the library")
    end
    
    return {
        lib = lib,
        api_type = td_api_type
    }
end

-- Create a client wrapper for the detected API
function M.create_client_wrapper(tdlib_info)
    local wrapper = {
        tdlib = tdlib_info.lib,
        api_type = tdlib_info.api_type,
        client = nil,
    }
    
    -- Initialize client
    function wrapper:init()
        if self.api_type == "standard" then
            self.client = self.tdlib.td_create_client_id()
            if self.client == 0 then
                error("Failed to create TDLib client")
            end
            vim.notify("Created standard TDLib client with ID: " .. self.client, vim.log.levels.INFO)
        else  -- json
            self.client = self.tdlib.td_json_client_create()
            if self.client == nil or self.client == ffi.NULL then
                error("Failed to create TDLib JSON client")
            end
            vim.notify("Created TDLib JSON client", vim.log.levels.INFO)
        end
        return self.client
    end
    
    -- Send request
    function wrapper:send(json_request)
        if not self.client then
            error("Client not initialized")
        end
        
        --vim.notify("Sending request: " .. json_request, vim.log.levels.DEBUG)
        if self.api_type == "standard" then
            self.tdlib.td_send(self.client, json_request)
        else  -- json
            self.tdlib.td_json_client_send(self.client, json_request)
        end
    end
    
    -- Receive update
    function wrapper:receive(timeout)
        if not self.client then
            error("Client not initialized")
        end
        
        local response
        if self.api_type == "standard" then
            response = self.tdlib.td_receive(timeout)
        else  -- json
            response = self.tdlib.td_json_client_receive(self.client, timeout)
        end
        return response
    end
    
    -- Execute synchronous request
    function wrapper:execute(json_request)
        if not self.client then
            error("Client not initialized")
        end
        
        vim.notify("Executing request: " .. json_request, vim.log.levels.DEBUG)
        local response
        if self.api_type == "standard" then
            response = self.tdlib.td_execute(json_request)
        else  -- json
            response = self.tdlib.td_json_client_execute(self.client, json_request)
        end
        
        if response ~= nil and response ~= ffi.NULL then
            vim.notify("Received execute response", vim.log.levels.DEBUG)
        end
        return response
    end
    
    -- Cleanup/destroy client
    function wrapper:cleanup()
        if not self.client then
            return
        end
        
        if self.api_type == "json" then
            self.tdlib.td_json_client_destroy(self.client)
            vim.notify("Destroyed TDLib JSON client", vim.log.levels.INFO)
        else
            vim.notify("Cleaned up standard TDLib client", vim.log.levels.INFO)
        end
        self.client = nil
    end
    
    return wrapper
end

return M
