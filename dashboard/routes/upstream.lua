local orange_db = require "orange.store.orange_db"
local dyups = require "ngx.dyups"
local ngx_ups = require "ngx.upstream"
local table_insert = table.insert
local json = require("orange.utils.json")
local dao = require("orange.store.dao")
local utils = require("orange.utils.utils")

local default_server_params = {
	weight="", max_fails="", fail_timeout="", backup=0, down=0, resolve=0,max_conns="",service="",route="",slow_start=""
}

local _M = {}

function _M.is_exist(ups_name)
	local get_upstreams = ngx_ups.get_upstreams
	local upstreams = get_upstreams()
	if upstreams then
		for _, v in ipairs(upstreams) do
			if v == ups_name then 
				return true
			end
		end
	end
	return false
end

-- 只在nginx启动或者重启worker的时候调用一次，用于初始化upstreams到nginx中
function _M.init_upstreams()
	local plugin = "upstream"
	local enable = orange_db.get(plugin .. ".enable")
	if enable then
		-- {"selectors":["a4fa3d23-75f2-4ef0-8404-d0fdd63730e9"]}
		-- local meta = orange_db.get_json(plugin .. ".meta") -- table
		-- {"a4fa3d23-75f2-4ef0-8404-d0fdd63730e9":{"time":"2017-05-23 16:48:28","enable":true,"id":"a4fa3d23-75f2-4ef0-8404-d0fdd63730e9","strategy":"ip_hash","name":"default_upstream","handle":{"log":false},"rules":["5359ef16-8378-4a80-b6fd-0a814b8cb425"]}}
		local selectors = orange_db.get_json(plugin .. ".selectors") -- table
		if selectors and type(selectors) == "table" then
			for id, ups in pairs(selectors) do
				if ups.enable then
					local status, rv = _M.add_upstream(ups)
					if not status then
						return os.exit(1)
					end
				end
			end
		end
	end
	-- body
end
-- 当向nginx 更新upstream失败时, nginx这个的upstreamh和数据库中以及orange_db中的就会不一致、
-- 该方法使从nginx中获取upstream,然后重置orange_db和mysql_db使数据一致
function _M.reset_upstream_with_nginx(upstream)
	local plugin = "upstream"
	local get_upstreams = ngx_ups.get_upstreams
	local get_servers = ngx_ups.get_servers
	local us = get_upstreams()
	if us then
		for _, upsname in ipairs(us) do
			if upsname == upstream.name then
				local servers = get_servers(upsname)
				if not servers then
					ngx.log(ngx.ERR, "reset upstream by nginx not found servers")
					return
				end
				-- servers in db
				local rules = orange_db.get_json(plugin .. ".selector." .. upstream.id .. ".rules")
				for k,serv in ipairs(servers) do
					if type(serv) == "table" then
						repeat
							local rule = _M.find_rule_by_host(rules, serv.name)
							if not rule then
								break
							end
							for n,m in pairs(default_server_params) do
								if not utils.table_contains_key(serv,n) then
									rule[n] = m
								else
									rule[n] = serv[n]
								end
							end
							ngx.log(ngx.INFO, "------rule------: ", json.encode(rule))
							dao.update_rule(plugin, context.store, rule)
						until true
					end
				end
				orange_db.set_json(plugin .. ".selector." .. upstream.id .. ".rules", rules)
			end
		end
	end
end

function _M.find_rule_by_host(rules, host)
	if rules then
		for _, v in pairs(rules) do
			if v.host == host then
				return v
			end
		end
	end
	return nil
end

-- 添加upstream
function _M.add_upstream(upstream)
	local enable = upstream.enable
	local ups_id = upstream.id
	local strategy = upstream.strategy
	local ups_name = upstream.name
	local command = ""
	local rules = orange_db.get_json("upstream.selector." .. ups_id .. ".rules")
	if rules and type(rules) == "table" and table.getn(rules) > 0 then
		for k,rule in ipairs(rules) do
			-- rule: {
			-- "host":"127.0.0.1:9999",
			-- "weight":"",
			-- "max_fails":"",
			-- "resolve":false,
			-- "service":"",
			-- "name":"s1",
			-- "handle":{"log":false},
			-- "id":"5359ef16-8378-4a80-b6fd-0a814b8cb425",
			-- "time":"2017-05-22 14:02:33",
			-- "enable":false,
			-- "route":"",
			-- "fail_timeout":"",
			-- "slow_start":"",
			-- "backup":false,
			-- "down":false}
			if rule.enable then
				command = command .. "server "
				local host = rule.host
				if host then
					command = command .. host .. " "
				end

				if rule.down then
					command = command .. "down; "
					break
				end

				local weight = rule.weight
				if weight and string.len(weight) > 0 then
					command = command .. "weight=" .. weight .. " "
				end

				local max_conns = rule.max_conns
				if max_conns and string.len(max_conns) > 0 then
					command = command .. "max_conns=" .. max_conns .. " "
				end

				local max_fails = rule.max_fails
				if max_fails and string.len(max_fails) > 0 then
					command = command .. "max_fails=" .. max_fails .. " "
				end

				local resolve = rule.resolve
				if resolve then
					command = command .. "resolve "
				end

				local service = rule.service
				if service and string.len(service) > 0 then
					command = command .. "service=" .. service .. " "
				end

				local route = rule.route
				if route and string.len(route) > 0 then
					command = command .. "route=" .. route .. " "
				end

				local fail_timeout = rule.fail_timeout
				if fail_timeout and string.len(fail_timeout) > 0 then
					command = command .. "fail_timeout=" .. fail_timeout .. " "
				end

				local slow_start = rule.slow_start
				if slow_start and string.len(slow_start) > 0 then
					command = command .. "slow_start=" .. slow_start .. " "
				end

				local backup = rule.backup
				if backup then
					command = command .. "backup "
				end

				command = command .. ";"
			end
		end
		if strategy and string.len(strategy) > 0 then
			command = command .. strategy .. ";"
		end
	end
	ngx.log(ngx.ERR, "[upstream name]: ", ups_name, " [command]: ", command)
	if string.len(command) > 0 then
		local status, rv = dyups.update(ups_name,command)
    	ngx.log(ngx.INFO, " status: ", status, "----rv -----: ",rv)
	    if status ~= ngx.HTTP_OK then
	        ngx.log(ngx.ERR,"create or update upstreams error ", status," result: ", rv)
	        -- 如果更新upstream失败，将数据库中server(rule)设为disable
	        --dao.update_selector("upstream", context.store, upstream)
	        _M.reset_upstream_with_nginx(upstream)
	        return false, rv
	    end
	    ngx.log(ngx.INFO, "update success")
	else
		if _M.is_exist(ups_name) then
			return _M.delete_upstream(upstream)
		end
	end
	return true
end

-- update upstream for nginx by upstream_id
function _M.update_upstream(upstream_id, opt)
	local plugin = "upstream"
	local enable = orange_db.get(plugin .. ".enable")
	if enable then
		-- {"selectors":["a4fa3d23-75f2-4ef0-8404-d0fdd63730e9"]}
		-- local meta = orange_db.get_json(plugin .. ".meta") -- table
		-- {"a4fa3d23-75f2-4ef0-8404-d0fdd63730e9":{"time":"2017-05-23 16:48:28","enable":true,"id":"a4fa3d23-75f2-4ef0-8404-d0fdd63730e9","strategy":"ip_hash","name":"default_upstream","handle":{"log":false},"rules":["5359ef16-8378-4a80-b6fd-0a814b8cb425"]}}
		local selectors = orange_db.get_json(plugin .. ".selectors") -- table
		if selectors and type(selectors) == "table" then
			for id, ups in pairs(selectors) do
				if ups.id == upstream_id then
					if ups.enable then
						local status, rv =  _M.add_upstream(ups)
						if status then
							return true
						else
							return false, rv
						end
					else
						if opt == "new" then
							return true
						else
							return _M.delete_upstream(ups)
						end
					end
				end
			end
		end
	else
		return true
	end
end

-- delete upstream from nginx
function _M.delete_upstream(upstream)
	local ups_name = upstream.name
	if ups_name and string.len(ups_name) > 0 then
		if _M.is_exist(ups_name) then
			local status, rv = dyups.delete(ups_name)
			if status ~= ngx.HTTP_OK then
				ngx.log(ngx.ERR, "[delete upstream " .. ups_name .." err status : ", status,  "result : ", rv)
				return false, rv
			end
			ngx.log(ngx.INFO, "delete upstream " .. ups_name .. "success")
		end
	end
	return true
end


return _M