local orange_db = require "orange.store.orange_db"
local dyups = require "ngx.dyups"
local ngx_ups = require "ngx.upstream"
local table_insert = table.insert
local json = require("orange.utils.json")
local dao = require("orange.store.dao")
local utils = require("orange.utils.utils")
local string_format = string.format

local _M = {}

function _M.init_dicts()
	local plugin = "kvstore"
	local enable = orange_db.get(plugin .. ".enable")
	if enable then
		-- {"selectors":["a4fa3d23-75f2-4ef0-8404-d0fdd63730e9"]}
		-- local meta = orange_db.get_json(plugin .. ".meta") -- table
		-- {"a4fa3d23-75f2-4ef0-8404-d0fdd63730e9":{"time":"2017-05-23 16:48:28","enable":true,"id":"a4fa3d23-75f2-4ef0-8404-d0fdd63730e9","strategy":"ip_hash","name":"default_upstream","handle":{"log":false},"rules":["5359ef16-8378-4a80-b6fd-0a814b8cb425"]}}
		local selectors = orange_db.get_json(plugin .. ".selectors") -- table
		if selectors and type(selectors) == "table" then
			for id, dict in pairs(selectors) do
				if dict.enable then
					local status, rv = _M.init_kvs(dict)
					if not status then
						return os.exit(1)
					end
				end
			end
		end
	end
end

function _M.init_kvs(dict)
	local plugin = "kvstore"
	local enable = dict.enable
	local dict_id = dict.id
	local rules = orange_db.get_json(plugin .. ".selector." .. dict_id .. ".rules")
	local log = dict.handle.log
	if rules and type(rules) == "table" and table.getn(rules) > 0 then
		for _, kv in ipairs(rules) do
			if kv.enable then
				local key = kv.key
				local value = kv.value
				if not key or not value then
					ngx.log(ngx.ERR, 'key and value could not be nil, key: ', key, " value: ", value)
				else
					local ngx_shared_dict = ngx.shared[dict.name]
					if not ngx_shared_dict then
						ngx.log(ngx.ERR, "ngx.shared. " .. dict.name .. " is not exist")
					else
						local success, err, forcible = ngx_shared_dict:set(key, value)
						if not success then
							ngx.log(ngx.ERR, "set dict key ", key, " is failed: ", err)
						end
						if log then
				            ngx.log(ngx.INFO, string_format("kvstore-set, dict: %s, key: %s, value: [[%s]], success: %s", dict, key, value, success))
				        end
					end
				end
			end
		end
	end
	return true
end
-- 根据kv_id删除一个dict中的key-value
function _M.delete_key(dict, kv_id)
	local plugin = "kvstore"
	local enable = dict.enable
	local dict_name = dict.name
	ngx.log(ngx.ERR, "delete --- enable : ", enable, " kv_id : ", kv_id, " dict_name: ", dict_name)
	if enable and not kv_id or not dict_name then
		ngx.log(ngx.ERR, "key or dict is uncorrect , key_id: ", kv_id, " dict_name: ", dict_name)
		return false, "key or dict is nil"
	end
	local rules = orange_db.get_json(plugin .. ".selector." .. dict.id .. ".rules")
	for _, kv in pairs(rules) do
		if kv.id == kv_id then
			local key = kv.key
			return _M.delete_kv(dict_name, key)
		end
	end
	return false, "delete key-value error "
end

function _M.delete_kv(dict_name, key)
	if dict_name and key then
		local ngx_shared_dict = ngx.shared[dict_name]
		if ngx_shared_dict then
			local success,err,forcible = ngx_shared_dict:delete(key)
			if success then
				ngx.log(ngx.INFO, "-----delete dict_name :", dict_name, " 'key: ", key)
				return true
			else
				-- 删除失败
				ngx.log(ngx.ERR, " delete dict : ", dict_name, " failed, err: ", err)
				return false, err
			end
		end
	end
	return false, " delete key-value error, dict_name or key is nil"
end

-- 向dict添加一个key-value
function _M.add_kv(dict, kv)
	if dict.enable and kv.enable then
		local ngx_shared_dict = ngx.shared[dict.name]
		if not ngx_shared_dict then
			ngx.log(ngx.ERR, "ngx.shared. " .. dict.name .. " is not exist")
			return false, "ngx.shared. " .. dict.name .. " is not exist"
		else
			local key = kv.key
			local value = kv.value
			local success, err, forcible = ngx_shared_dict:set(key, value)
			if not success then
				ngx.log(ngx.ERR, "set dict key ", key, " is failed: ", err)
				return false, err
			end
			if log then
	            ngx.log(ngx.INFO, string_format("kvstore-set, dict: %s, key: %s, value: [[%s]], success: %s", dict, key, value, success))
	        end
	        return true
		end
	end
	return false,"add key-value error"
end

function _M.is_exist(dict, kv)

end
return _M