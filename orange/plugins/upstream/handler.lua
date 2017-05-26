local pairs = pairs
local ipairs = ipairs
local ngx_re_sub = ngx_re_sub
local ngx_re_find = ngx_re_find
local string_sub = string.sub
local orange_db = require("orange.store.orange_db")
local handler_util = require("orange.utils.handle")
local BasePlugin = require("orange.plugins.base_handler")
local ngx_set_uri = ngx.req.set_uri
local ngx_set_uri_args = ngx.req.set_uri_args
local ngx_decode_args = ngx.decode_args


local UpstreamHandler = BasePlugin:extend()
UpstreamHandler.PRIORITY = 2000

function UpstreamHandler:new(store)
	UpstreamHandler.super.new(self, "Upstream-plugin")
	self.store = store
end

function UpstreamHandler:access(conf)
	
	-- body
end

return UpstreamHandler
