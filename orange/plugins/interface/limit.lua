local lock = require("resty.lock")
local limit_req = require("resty.limit.req")
local orange_db = require("orange.store.orange_db")
local judge_util = require("orange.utils.judge")
-- 共享内存名称，用户存储限流数据
local my_limit_req_store = "rate_limit"
--local lim  = limit_req.new(my_limit_req_store, 200, 100)

-- 用户存储限制对象
local limit_map = {}

local _M = {}

-- 初始化limit_map，保存各个uri的limit对象
function _M.init()
	--local plugin = "interface"
	local enable = orange_db.get("interface.enable")
	local meta = orange_db.get_json("interface.meta")
    -- groups
    local selectors = orange_db.get_json("interface.selectors")
    local ordered_selectors = meta and meta.selectors
    
    if not enable or enable ~= true or not meta or not ordered_selectors or not selectors then
        return
    end

    for i,sid in ipairs(ordered_selectors) do
    	local selector = selectors[sid]
    	if selector and selector.enable then
    		if selector.handle and selector.handle.log == true then
                ngx.log(ngx.INFO, "[Interface ACCESS][PASS-SELECTOR:", sid, "] ", ngx_var_uri)
            end
            local rules = orange_db.get_json("interface.selector." .. sid .. ".rules")
            if rules then
            	for i,rule in ipairs(rules) do
            		_M.new_limit(rule)
            	end
            end
        end
    end
end

function _M.new_limit(rule)
	if rule and rule.enable then
		if rule.enable then
			local uri = rule.uri
			local limit_enable = rule.limit.enable
			if limit_enable then
				local limit_times = rule.limit.times
				local burst_times = rule.limit.burst
				local lim_key = limit_times .. ":" .. burst_times
				local lim = limit_map[lim_key]
				local err = nil
				if not lim then
					limit_times = tonumber(limit_times)
					burst_times = tonumber(burst_times)
					lim,err = limit_req.new(my_limit_req_store, limit_times, burst_times)
					ngx.log(ngx.INFO, "created limit object with key: ", lim_key)
					if not lim then
						ngx.log(ngx.ERR,
	                        "failed to instantiate a resty.limit.req object: ", err)
						return
					end
	                limit_map[lim_key] = lim
	                -- return ngx.exit(500)
	            end
	            return lim
	        end
		end
	end
	return nil
end

-- 统计控制uri访问控制
function _M.incoming(uri, rule)
	if not rule then
		return false, "rule can not be nil"
	end
	local lim = _M.new_limit(rule)
	if lim then
		-- 使用uri作为Key
		local key = uri
		local delay, err = lim:incoming(key, true)
		ngx.log(ngx.INFO,"-------delay :", delay, " ----------")
        if not delay then
            if err == "rejected" then
                return ngx.exit(503)
            end
            ngx.log(ngx.ERR, "failed to limit req: ", err)
            return ngx.exit(500)
        end

        if delay >= 0.001 then
            -- the 2nd return value holds the number of excess requests
            -- per second for the specified key. for example, number 31
            -- means the current request rate is at 231 req/sec for the
            -- specified key.
            local excess = err

            -- the request exceeding the 200 req/sec but below 300 req/sec,
            -- so we intentionally delay it here a bit to conform to the
            -- 200 req/sec rate.
            ngx.sleep(delay)
        end
    end

end

return _M


