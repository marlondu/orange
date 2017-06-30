local ipairs = ipairs
local orange_db = require("orange.store.orange_db")
local stat = require("orange.plugins.monitor.stat")
local judge_util = require("orange.utils.judge")
local BasePlugin = require("orange.plugins.base_handler")
local limit = require("orange.plugins.interface.limit")
-- interface管理

local function filter_rules(sid, plugin, ngx_var_uri)
    local rules = orange_db.get_json(plugin .. ".selector." .. sid .. ".rules")
    if not rules or type(rules) ~= "table" or #rules <= 0 then
        return false
    end

    for i, rule in ipairs(rules) do
        if rule.enable == true then
            -- judge阶段
            local pass = judge_util.equals_rule(rule, plugin)
            -- 是否进行监控
            local monitor = rule.monitor
            -- handle阶段
            if pass and monitor then
                local key_suffix =  rule.id
                stat.count(key_suffix)

                local handle = rule.handle
                if handle then
                    if handle.log == true then
                        ngx.log(ngx.INFO, "[interface] ", rule.id, ":", ngx_var_uri)
                    end

                    if handle.continue == true then
                    else
                        return true -- 不再匹配后续的规则，即不再统计满足后续规则的监控
                    end
                end
            end
        end
    end

    return false
end


local URLMonitorHandler = BasePlugin:extend()
URLMonitorHandler.PRIORITY = 2000

function URLMonitorHandler:new(store)
    URLMonitorHandler.super.new(self, "interface-plugin")
    self.store = store
end

function URLMonitorHandler:access(store)
    URLMonitorHandler.super.access(self)
    local enable = orange_db.get("interface.enable")
    local meta = orange_db.get_json("interface.meta")
    -- groups
    local selectors = orange_db.get_json("interface.selectors")
    local ordered_selectors = meta and meta.selectors
    
    if not enable or enable ~= true or not meta or not ordered_selectors or not selectors then
        return
    end

    local ngx_var_uri = ngx.var.uri
    local pass = false
    local current_rule = nil
    for i,sid in ipairs(ordered_selectors) do
        ngx.log(ngx.INFO,"==[Interface ACCESS][PASS THROUGH SELECTOR:", sid, "]")
        local selector = selectors[sid]
        if selector and selector.enable then
            if selector.handle and selector.handle.log == true then
                ngx.log(ngx.INFO, "[Interface ACCESS][PASS-SELECTOR:", sid, "] ", ngx_var_uri)
            end
            local rules = orange_db.get_json("interface.selector." .. sid .. ".rules")
            repeat
                if not rules or type(rules) ~= "table" or #rules <= 0 then
                    pass = false
                    break
                end
                for i,rule in ipairs(rules) do
                    -- 找到此次请求的uri对应的rule
                    pass = rule.enable and judge_util.equals_rule(rule)
                    if pass then
                        current_rule = rule
                        break
                    end
                end
            until true
            if pass then
                break
            end
        end
    end
    if pass then
        if current_rule then
            limit.incoming(ngx_var_uri, current_rule)
        end
    else
        ngx.exit(ngx.HTTP_NOT_FOUND)
    end
end

function URLMonitorHandler:log(conf)
    URLMonitorHandler.super.log(self)

    local enable = orange_db.get("interface.enable")
    local meta = orange_db.get_json("interface.meta")
    -- groups
    local selectors = orange_db.get_json("interface.selectors")
    local ordered_selectors = meta and meta.selectors
    
    if not enable or enable ~= true or not meta or not ordered_selectors or not selectors then
        return
    end
    
    local ngx_var_uri = ngx.var.uri
    for i, sid in ipairs(ordered_selectors) do
        ngx.log(ngx.INFO, "==[Interface LOG][PASS THROUGH SELECTOR:", sid, "]")
        local selector = selectors[sid]
        if selector and selector.enable == true then
            if selector.handle and selector.handle.log == true then
                ngx.log(ngx.INFO, "[Interface LOG][PASS-SELECTOR:", sid, "] ", ngx_var_uri)
            end

            local stop = filter_rules(sid, "interface", ngx_var_uri)
            if stop then -- 不再执行此插件其他逻辑
                return
            end

            -- if continue or break the loop
            if selector.handle and selector.handle.continue == true then
                -- continue next selector
            else
                break
            end
        end
    end
    
end


return URLMonitorHandler