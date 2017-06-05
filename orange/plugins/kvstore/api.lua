local ipairs = ipairs
local type = type
local tostring = tostring
local string_format = string.format
local xpcall = xpcall
local traceback = debug.traceback
local json = require("orange.utils.json")
local orange_db = require("orange.store.orange_db")
local BaseAPI = require("orange.plugins.base_api")
local common_api = require("orange.plugins.common_api")
local utils = require("orange.utils.utils")
local dao = require("orange.store.dao")
local table_insert = table.insert
local kvstore = require("dashboard.routes.kvstore")

local plugin = "kvstore"

local function send_err_result(res, format, err)
    if format == "json" then
        res:status(500):json({
            success = false,
            msg = err
        })
    elseif format == "text" then
        res:status(500):send(err)
    elseif format == "html" then
        res:status(500):html(err)
    end
end

local function send_failed_result(res, format, err)
    if format == "json" then
        res:json({
            success = false,
            msg = err
        })
    elseif format == "text" then
        res:send(err)
    elseif format == "html" then
        res:html(err)
    end
end

local function send_success_result(res, format)
    if format == "json" then
        res:json({
            success = true,
            msg = "success"
        })
    elseif format == "text" then
        res:send("success")
    elseif format == "html" then
        res:html("success")
    end
end

local function send_result(res, format, value)
    if format == "json" then
        xpcall(function()
            value = json.decode(value)
        end, function(err)
            local trace = traceback(err, 2)
            ngx.log(ngx.ERR, "decode as json format error: ", trace)
        end)

        res:json({
            success = true,
            data = value
        })
    elseif format == "text" then
        res:send(value or "")
    elseif format == "html" then
        res:html(value or "")
    end
end


local API = BaseAPI:new("kvstore-api", 2)

API:merge_apis(common_api("kvstore"))

-- add key-value
API:post("/" .. plugin .. "/selectors/:id/rules",function(store) -- create
        return function(req, res, next)
            local selector_id = req.params.id
            local selector = dao.get_selector(plugin, store, selector_id)
            if not selector or not selector.value then
                return res:json({
                    success = false,
                    msg = "selector not found when creating rule"
                })
            end

            local current_selector = json.decode(selector.value)
            if not current_selector then
                return res:json({
                    success = false,
                    msg = "selector could not be decoded when creating rule"
                })
            end

            local rule = req.body.rule
            rule = json.decode(rule)
            rule.id = utils.new_id()
            rule.time = utils.now()

            -- 插入到mysql
            local insert_result = dao.create_rule(plugin, store, rule)

            -- 插入成功
            if insert_result then
                -- update selector
                current_selector.rules = current_selector.rules or {}
                table_insert(current_selector.rules, rule.id)
                local update_selector_result = dao.update_selector(plugin, store, current_selector)
                if not update_selector_result then
                    return res:json({
                        success = false,
                        msg = "update selector error when creating rule"
                    })
                end

                -- update local selectors
                local update_local_selectors_result = dao.update_local_selectors(plugin, store)
                if not update_local_selectors_result then
                    return res:json({
                        success = false,
                        msg = "error to update local selectors when creating rule"
                    })
                end

                local update_local_selector_rules_result = dao.update_local_selector_rules(plugin, store, selector_id)
                if not update_local_selector_rules_result then
                    return res:json({
                        success = false,
                        msg = "error to update local rules of selector when creating rule"
                    })
                end
            else
                return res:json({
                    success = false,
                    msg = "fail to create rule"
                })
            end

            -- 此时orange_db中的数据已经是最新的了, 新建upstream
            if rule.enable then
                local update_nginx_server_result = kvstore.add_kv(current_selector, rule) --kvstore.init_kvs(current_selector)
                if not update_nginx_server_result then
                    return res:json({
                        success = false,
                        msg = "fail to add dict and key-value to nginx"
                        })
                end
            end
            
            res:json({
                success = true,
                msg = "succeed to create rule"
            })
        end
    end)
-- modofy key-value
API:put("/" .. plugin .. "/selectors/:id/rules",function(store) -- modify
        return function(req, res, next)
            local selector_id = req.params.id
            local rule = req.body.rule
            local selector = req.body.selector
            rule = json.decode(rule)
            rule.time = utils.now()
            selector= json.decode(selector)

            local update_result = dao.update_rule(plugin, store, rule)

            if update_result then
                local old_rules = orange_db.get_json(plugin .. ".selector." .. selector_id .. ".rules") or {}
                local new_rules = {}
                for _, v in ipairs(old_rules) do
                    if v.id == rule.id then
                        rule.time = utils.now()
                        table_insert(new_rules, rule)
                    else
                        table_insert(new_rules, v)
                    end
                end

                local success, err, forcible = orange_db.set_json(plugin .. ".selector." .. selector_id .. ".rules", new_rules)
                if err or forcible then
                    ngx.log(ngx.ERR, "update local rules error when modifing:", err, ":", forcible)
                    return res:json({
                        success = false,
                        msg = "update local rules error when modifing"
                    })
                end

                -- 此时orange_db中的数据已经是最新的了
                local update_nginx_server_result = false
                ngx.log(ngx.INFO, "update key-value, enable: ", rule.enable, " dict_name: ", selector.name, " key: ", rule.key)
                if rule.enable then
                    update_nginx_server_result = kvstore.add_kv(selector, rule) --kvstore.init_kvs(current_selector)
                else
                    update_nginx_server_result = kvstore.delete_kv(selector.name, rule.key)
                end
                if not update_nginx_server_result then
                    return res:json({
                        success = false,
                        msg = "fail to update dict and key-value to nginx"
                        })
                end

                return res:json({
                    success = success,
                    msg = success and "ok" or "failed"
                })
            end

            res:json({
                success = false,
                msg = "update rule to db error"
            })
        end
    end)
-- delete key-value
API:delete("/" .. plugin .. "/selectors/:id/rules",function(store)
        return function(req, res, next)
            local selector_id = req.params.id
            local selector = dao.get_selector(plugin, store, selector_id)
            if not selector or not selector.value then
                return res:json({
                    success = false,
                    msg = "selector not found when deleting rule"
                })
            end

            local current_selector = json.decode(selector.value)
            if not current_selector then
                return res:json({
                    success = false,
                    msg = "selector could not be decoded when deleting rule"
                })
            end

            local rule_id = tostring(req.body.rule_id)
            if not rule_id or rule_id == "" then
                return res:json({
                    success = false,
                    msg = "error param: rule id shoule not be null."
                })
            end

            -- 此时orange_db中的数据已经是最新的了
            local delete_ngx_kv_result, rv = kvstore.delete_key(current_selector, rule_id)
            if not delete_ngx_kv_result then
                ngx.log(ngx.ERR, "delete key-value error : ", rv)
                return res:json({
                    success = false,
                    msg = "fail to delete key-value from nginx"
                    })
            end

            local delete_result = store:delete({
                sql = "delete from " .. plugin .. " where `key`=? and `type`=?",
                params = { rule_id, "rule"}
            })

            if delete_result then
                -- update selector
                local old_rules_ids = current_selector.rules or {}
                local new_rules_ids = {}
                for _, orid in ipairs(old_rules_ids) do
                    if orid ~= rule_id then
                        table_insert(new_rules_ids, orid)
                    end
                end
                current_selector.rules = new_rules_ids

                local update_selector_result = dao.update_selector(plugin, store, current_selector)
                if not update_selector_result then
                    return res:json({
                        success = false,
                        msg = "update selector error when deleting rule"
                    })
                end

                -- update local selectors
                local update_local_selectors_result = dao.update_local_selectors(plugin, store)
                if not update_local_selectors_result then
                    return res:json({
                        success = false,
                        msg = "error to update local selectors when deleting rule"
                    })
                end

                -- update local rules of selector
                local update_local_selector_rules_result = dao.update_local_selector_rules(plugin, store, selector_id)
                if not update_local_selector_rules_result then
                    return res:json({
                        success = false,
                        msg = "error to update local rules of selector when creating rule"
                    })
                end
            else
                res:json({
                    success = false,
                    msg = "delete rule from db error"
                })
            end

            res:json({
                success = true,
                msg = "succeed to delete rule"
            })
        end
    end)

API:post("/kvstore/enable", function(store)
    return function(req, res, next)
        local enable = req.body.enable
        if enable == "1" then enable = true else enable = false end

        local result = false

        local kvstore_enable = "0"
        if enable then kvstore_enable = "1" end
        local update_result = store:update({
            sql = "replace into meta SET `key`=?, `value`=?",
            params = { "kvstore.enable", kvstore_enable }
        })

        if update_result then
            local success, err, forcible = orange_db.set("kvstore.enable", enable)
            result = success
        else
            result = false
        end

        if result then
            res:json({
                success = true,
                msg = (enable == true and "开启kvstore成功" or "关闭kvstore成功")
            })
        else
            res:json({
                success = false,
                data = (enable == true and "开启kvstore失败" or "关闭kvstore失败")
            })
        end
    end
end)

-- delete dict
API:delete("/" .. plugin .. "/selectors", function(store) -- delete selector
        --- 1) delete selector
        --- 2) delete rules of it
        --- 3) update meta
        --- 4) update local meta & selectors
        return function(req, res, next)

            local selector_id = tostring(req.body.selector_id)
            if not selector_id or selector_id == "" then
                return res:json({
                    success = false,
                    msg = "error param: selector id shoule not be null."
                })
            end

            -- get selector
            local selector = dao.get_selector(plugin, store, selector_id)
            if not selector or not selector.value then
                return res:json({
                    success = false,
                    msg = "error: can not find selector#" .. selector_id
                })
            end

            -- delete rules of it
            local to_del_selector = json.decode(selector.value)
            if not to_del_selector then
                return res:json({
                    success = false,
                    msg = "error: decode selector#" .. selector_id .. " failed"
                })
            end

            local to_del_rules_ids = to_del_selector.rules or {}
            local d_result = dao.delete_rules_of_selector(plugin, store, to_del_rules_ids)
            ngx.log(ngx.ERR, "delete rules of selector:", d_result)

            -- update meta
            local meta = dao.get_meta(plugin, store)
            local current_meta = json.decode(meta.value)
            if not meta or not current_meta then
               return res:json({
                    success = false,
                    msg = "error: can not find meta"
                })
            end

            local current_selectors_ids = current_meta.selectors or {}
            local new_selectors_ids = {}
            for _, v in ipairs(current_selectors_ids) do
                if  selector_id ~= v then
                    table_insert(new_selectors_ids, v)
                end
            end
            current_meta.selectors = new_selectors_ids

            local update_meta_result = dao.update_meta(plugin, store, current_meta)
            if not update_meta_result then
                return res:json({
                    success = false,
                    msg = "error: update meta error"
                })
            end

            -- delete the very selector
            local delete_selector_result = dao.delete_selector(plugin, store, selector_id)
            if not delete_selector_result then
                return res:json({
                    success = false,
                    msg = "error: delete the very selector error"
                })
            end

            -- update local meta & selectors
            local update_local_meta_result = dao.update_local_meta(plugin, store)
            local update_local_selectors_result = dao.update_local_selectors(plugin, store)
            if update_local_meta_result and update_local_selectors_result then

                if plugin == "kvstore-dev" then
                    local status,rv = kvstore.delete_upstream(to_del_selector)
                    if not status then
                        ngx.log(ngx.ERR, "delete upstream error ", to_del_selector.name, "ERROR: ", rv)
                        return res:json({
                            success = false,
                            msg = "error to delete upstream from nginx"
                            })
                    end
                end
                -- set upstream
                return res:json({
                    success = true,
                    msg = "succeed to delete selector"
                })
            else
                ngx.log(ngx.ERR, "error to delete selector, update_meta:", update_local_meta_result, " update_selectors:", update_local_selectors_result)
                return res:json({
                    success = false,
                    msg = "error to udpate local data when deleting selector"
                })
            end
        end
    end)

-- add dict
API:post("/" .. plugin .. "/selectors", function(store) -- create a selector
    return function(req, res)
        local selector = req.body.selector
        selector = json.decode(selector)
        selector.id = utils.new_id()
        selector.time = utils.now()

        -- create selector
        local insert_result = dao.create_selector(plugin, store, selector)

        -- update meta
        local meta = dao.get_meta(plugin, store)
        local current_meta = json.decode(meta and meta.value or "{}")
        if not meta or not current_meta then
           return res:json({
                success = false,
                msg = "error: can not find meta when creating selector"
            })
        end
        current_meta.selectors = current_meta.selectors or {}
        table_insert(current_meta.selectors, selector.id)
        local update_meta_result = dao.update_meta(plugin, store, current_meta)
        if not update_meta_result then
            return res:json({
                success = false,
                msg = "error: update meta error when creating selector"
            })
        end

        -- update local meta & selectors
        if insert_result then
            local update_local_meta_result = dao.update_local_meta(plugin, store)
            local update_local_selectors_result = dao.update_local_selectors(plugin, store)
            if update_local_meta_result and update_local_selectors_result then

                -- created upstream in ngx.shared
                if plugin == "kvstore-dev" and type(selector) == "table" then
                    local status, rv = kvstore.add_upstream(selector, "new")
                    if not status then
                        ngx.log(ngx.ERR, " create upstream error ", rv)
                        return res:json({
                            success = false,
                            msg = "create upstream error "
                            })
                    end
                end

                return res:json({
                    success = true,
                    msg = "succeed to create selector"
                })
            else
                ngx.log(ngx.ERR, "error to create selector, update_meta:", update_local_meta_result, " update_selectors:", update_local_selectors_result)
                return res:json({
                    success = false,
                    msg = "error to udpate local data when creating selector"
                })
            end
        else
            return res:json({
                success = false,
                msg = "error to save data when creating selector"
            })
        end
    end
end)
-- modify dict
API:put("/" .. plugin .. "/selectors", function(store) -- update
        return function(req, res, next)
            local selector = req.body.selector
            selector = json.decode(selector)
            selector.time = utils.now()
            -- 更新selector
            local update_selector_result = dao.update_selector(plugin, store, selector)
            if update_selector_result then
                local update_local_selectors_result = dao.update_local_selectors(plugin, store)
                if not update_local_selectors_result then
                    return res:json({
                        success = false,
                        msg = "error to local selectors when updating selector"
                    })
                end
            else
                return res:json({
                    success = false,
                    msg = "error to update selector"
                })
            end

            -- 此时orange_db中的数据已经是最新的了
            --if plugin == "kvstore" then
            --    local update_nginx_server_result, rv = upstream.update_upstream(selector.id, "update")
            --    if not update_nginx_server_result then
            --        ngx.log(ngx.ERR, "update ngx upstream server: ", rv)
            --        return res:json({
            --            success = false,
            --            msg = "fail to add upstream and servers to nginx"
            --            })
            --    end
            --end                

            return res:json({
                success = true,
                msg = "succeed to update selector"
            })
        end
    end)

API:get("/kvstore/fetch_config", function(store)
    return function(req, res, next)
        local data = {}

        -- 查找enable
        local enable, err1 = store:query({
            sql = "select `value` from meta where `key`=?",
            params = { "kvstore.enable" }
        })

        if err1 then
            return res:json({
                success = false,
                msg = "get enable error"
            })
        end

        if enable and type(enable) == "table" and #enable == 1 and enable[1].value == "1" then
            data.enable = true
        else
            data.enable = false
        end

        -- 查找其他配置
        local conf, err2 = store:query({
            sql = "select `value` from meta where `key`=?",
            params = { "kvstore.conf" }
        })
        if err2 then
            return res:json({
                success = false,
                msg = "get conf error"
            })
        end

        if conf and type(conf) == "table" and #conf == 1 then
            data.conf = json.decode(conf[1].value)
        else
            data.conf = {}
        end

        res:json({
            success = true,
            data = data
        })
    end
end)

-- update the local cache to data stored in db
API:post("/kvstore/sync", function(store)
    return function(req, res, next)
        local data = {}
        -- 查找enable
        local enable, err1 = store:query({
            sql = "select `value` from meta where `key`=?",
            params = { "kvstore.enable" }
        })

        if err1 then
            return res:json({
                success = false,
                msg = "get enable error"
            })
        end

        if enable and type(enable) == "table" and #enable == 1 and enable[1].value == "1" then
            data.enable = true
        else
            data.enable = false
        end

        -- 查找其他配置，如rules 、conf等
        local conf, err2 = store:query({
            sql = "select `value` from meta where `key`=?",
            params = { "kvstore.conf" }
        })
        if err2 then
            return res:json({
                success = false,
                msg = "get conf error"
            })
        end

        if conf and type(conf) == "table" and #conf == 1 then
            data.conf = json.decode(conf[1].value)
        else
            data.conf = {}
        end

        local ss, err3, forcible = orange_db.set("kvstore.enable", data.enable)
        if not ss or err3 then
            return res:json({
                success = false,
                msg = "update local enable error"
            })
        end
        ss, err3, forcible = orange_db.set_json("kvstore.conf", data.conf)
        if not ss or err3 then
            return res:json({
                success = false,
                msg = "update local conf error"
            })
        end

        res:json({
            success = true
        })
    end
end)
-- 获取kv store配置
API:get("/kvstore/configs", function(store)
    return function(req, res, next)
        res:json({
            success = true,
            data = {
                enable = orange_db.get("kvstore.enable"),
                conf = orange_db.get_json("kvstore.conf")
            }
        })
    end
end)

-- new
API:post("/kvstore/configs", function(store)
    return function(req, res, next)
        local conf = req.body.conf
        local success, data = false, {}

        -- 插入或更新到mysql
        local update_result = store:update({
            sql = "replace into meta SET `key`=?, `value`=?",
            params = { "kvstore.conf", conf }
        })

        if update_result then
            local result, err, forcible = orange_db.set("kvstore.conf", conf)
            success = result
            if success then
                data.conf = json.decode(conf)
                data.enable = orange_db.get("kvstore.enable")
            end
        else
            success = false
        end

        res:json({
            success = success,
            data = data
        })
    end
end)

 -- modify
API:put("/kvstore/configs", function(store)
    return function(req, res, next)
        local conf = req.body.conf
        local success, data = false, {}

        -- 插入或更新到mysql
        local update_result = store:update({
            sql = "replace into meta SET `key`=?, `value`=?",
            params = { "kvstore.conf", conf }
        })

        if update_result then
            local result, err, forcible = orange_db.set("kvstore.conf", conf)
            success = result
            if success then
                data.conf = json.decode(conf)
                data.enable = orange_db.get("kvstore.enable")
            end
        else
            success = false
        end

        res:json({
            success = success,
            data = data
        })
    end
end)

API:get("/kvstore/get", function(store)
    return function(req, res, next)
        local dict = req.query.dict
        local key = req.query.key
        local format = req.query.format
        if format ~= "html" and format ~= "text" and format ~= "json" then
            format = "json"
        end

        if not dict or not key or dict == "" or key == "" then
            return send_err_result(res, format, "error params.")
        end

        local block = false
        local conf = orange_db.get_json("kvstore.conf")
        if conf then
            local blacklist, whitelist = conf.blacklist, conf.whitelist
            if blacklist and next(blacklist) then
                for _, v in ipairs(blacklist) do
                    if v.dict == dict and v.key == key then
                        block = true
                        break
                    end
                end
            end

            local contains
            if whitelist and next(whitelist) then
                for _, v in ipairs(whitelist) do
                    if v.dict == dict and v.key == key then
                        contains = true
                        break
                    end
                end
            end

            if contains then
                block = false
            end
        end

        if block == true then
            return send_err_result(res, format, string_format("not allowed to get ngx.shared.%s[%s]", dict, key))
        end

        local ngx_shared_dict = ngx.shared[dict]
        if not ngx_shared_dict then
            return send_err_result(res, format, string_format("ngx.shared.%s not exists", dict))
        end

        local value = ngx_shared_dict:get(key)
        ngx.log(ngx.INFO, dict, " ", key, " ", format, " v:", value)
        send_result(res, format, value)
    end
end)

API:post("/kvstore/set", function(store)
    return function(req, res, next)
        local dict = req.body.dict
        local key = req.body.key
        local value = req.body.value
        local exptime = req.body.exptime -- seconds
        local vtype = req.body.vtype
        local format = req.body.format
        local log = req.body.log

        if format ~= "html" and format ~= "text" and format ~= "json" then
            format = "json"
        end

        if exptime and tonumber(exptime) then
            exptime = tonumber(exptime)
        end

        if vtype ~= "number" and vtype ~= "string" then
            vtype = "string"
        end

        if vtype == "number" then
            value = tonumber(value)
            if not value then
                return send_failed_result(res, format, "value is nil or it's not a number.")
            end
        elseif type == "string" then
            value = tostring(value)
        end

        if log == "true" then
            log = true
        end

        if not dict or not key or dict == "" or key == "" then
            return send_failed_result(res, format, "error params.")
        end

        local block = false
        local conf = orange_db.get_json("kvstore.conf")
        if conf then
            local blacklist, whitelist = conf.blacklist, conf.whitelist
            if blacklist and next(blacklist) then
                for _, v in ipairs(blacklist) do
                    if v.dict == dict and v.key == key then
                        block = true
                        break
                    end
                end
            end

            local contains
            if whitelist and next(whitelist) then
                for _, v in ipairs(whitelist) do
                    if v.dict == dict and v.key == key then
                        contains = true
                        break
                    end
                end
            end

            if contains then
                block = false
            end
        end

        if block == true then
            return send_failed_result(res, format, string_format("not allowed to set ngx.shared.%s[%s]", dict, key))
        end

        local ngx_shared_dict = ngx.shared[dict]
        if not ngx_shared_dict then
            return send_failed_result(res, format, string_format("ngx.shared.%s not exists", dict))
        end

        local success, err, forcible
        if exptime and exptime >= 0 then
            success, err, forcible = ngx_shared_dict:set(key, value, exptime)
        else
            success, err, forcible = ngx_shared_dict:set(key, value)
        end

        if log then
            ngx.log(ngx.INFO, string_format("kvstore-set, dict: %s, key: %s, value: [[%s]], success: %s", dict, key, value, success))
        end

        if success then
            send_success_result(res, format)
        else
            send_failed_result(res, format, err)
        end
    end
end)


return API
