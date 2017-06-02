local BaseAPI = require("orange.plugins.base_api")
local common_api = require("orange.plugins.common_api")
local ipairs = ipairs
local type = type
local tostring = tostring
local table_insert = table.insert
local json = require("orange.utils.json")
local orange_db = require("orange.store.orange_db")
local utils = require("orange.utils.utils")
local stringy = require("orange.utils.stringy")
local dao = require("orange.store.dao")
local upstream = require("dashboard.routes.upstream")

local API = BaseAPI:new("upstream-api", 2)
API:merge_apis(common_api("upstream"))

local plugin = "upstream"

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
            if plugin == "upstream" then
                local update_nginx_server_result = upstream.update_upstream(selector_id, "update")
                if not update_nginx_server_result then
                    return res:json({
                        success = false,
                        msg = "fail to add upstream and servers to nginx"
                        })
                end
            end
            
            res:json({
                success = true,
                msg = "succeed to create rule"
            })
        end
    end)

API:get("/" .. plugin .. "/selectors/:id/rules",function(store)
        return function(req, res, next)
            local selector_id = req.params.id

            local rules = orange_db.get_json(plugin .. ".selector." .. selector_id .. ".rules") or {}
            res:json({
                success = true,
                data = {
                    rules = rules
                }
            })
        end
    end)

API:put("/" .. plugin .. "/selectors/:id/rules",function(store) -- modify
        return function(req, res, next)
            local selector_id = req.params.id
            local rule = req.body.rule
            rule = json.decode(rule)
            rule.time = utils.now()

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
                if plugin == "upstream" then
                    
                    local update_nginx_server_result, rv = upstream.update_upstream(selector_id, "update")
                    if not update_nginx_server_result then
                        ngx.log(ngx.ERR, "update ngx upstream server: ", rv)
                        return res:json({
                            success = false,
                            msg = "fail to add upstream and servers to nginx"
                            })
                    end
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
    -- delete rules
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

            -- 此时orange_db中的数据已经是最新的了
            if plugin == "upstream" then
                local update_nginx_server_result, rv = upstream.update_upstream(selector_id, "update")
                if not update_nginx_server_result then
                    ngx.log(ngx.ERR, "delete userver error : ", rv)
                    return res:json({
                        success = false,
                        msg = "fail to add upstream and servers to nginx"
                        })
                end
            end

            res:json({
                success = true,
                msg = "succeed to delete rule"
            })
        end
    end)

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

                if plugin == "upstream" then
                    local status,rv = upstream.delete_upstream(to_del_selector)
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

                    -- created upstream in nginx 
                    if plugin == "upstream" and type(selector) == "table" then
                        local status, rv = upstream.add_upstream(selector, "new")
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
            if plugin == "upstream" then
                local update_nginx_server_result, rv = upstream.update_upstream(selector.id, "update")
                if not update_nginx_server_result then
                    ngx.log(ngx.ERR, "update ngx upstream server: ", rv)
                    return res:json({
                        success = false,
                        msg = "fail to add upstream and servers to nginx"
                        })
                end
            end                

            return res:json({
                success = true,
                msg = "succeed to update selector"
            })
        end
    end)

return API