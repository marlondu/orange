(function (L) {
    var _this = null;
    L.KVStore = L.KVStore || {};
    _this = L.KVStore = {
        data: {
        },
        dialogTitle: {
            selector: "DICT",
            rule: "Key-Value"
        },
        init: function () {
            //_this.initEvents();

            /*var op_type = "kvstore";
            $.ajax({
                url: '/kvstore/configs',
                type: 'get',
                cache: false,
                data: {},
                dataType: 'json',
                success: function (result) {
                    if (result.success) {
                        console.log(result);
                        L.Common.resetSwitchBtn(result.data.enable, op_type);
                        $("#switch-btn").show();
                        $("#view-btn").show();
                        var enable = result.data.enable;

                        //重新设置数据
                        _this.data.enable = enable;

                        $("#op-part").css("display", "block");
                    } else {
                        $("#op-part").css("display", "none");
                        L.Common.showErrorTip("错误提示", "查询" + op_type + "配置请求发生错误");
                    }
                },
                error: function () {
                    $("#op-part").css("display", "none");
                    L.Common.showErrorTip("提示", "查询" + op_type + "配置请求发生异常");
                }
            });*/
            L.Common.loadConfigs("kvstore", _this, true);// 向/upstream/selectors发送请求, 获取配置，存储在data中
            _this.initEvents();

            $("#table-view h4").text("DICT列表");
            $("#rules-section-header").text("DICT-KV列表");
            $("#add-btn span").text("添加新Key-Value");
        },

        initEvents: function(){
            var op_type = "kvstore";
            L.Common.initViewAndDownloadEvent(op_type, _this);
            L.Common.initSwitchBtn(op_type, _this);//redirect关闭、开启
            L.Common.initSyncDialog(op_type, _this);//编辑规则对话框

            L.Common.initSelectorAddDialog(op_type, _this);
            L.Common.initSelectorEditDialog(op_type, _this);
            L.Common.initSelectorDeleteDialog(op_type, _this);
            L.Common.initSelectorClickEvent(op_type, _this);

            L.Common.initRuleAddDialog(op_type, _this);
            this.initRuleEditDialog(op_type, _this);
            L.Common.initRuleDeleteDialog(op_type, _this);
            L.Common.initRuleSortEvent(op_type, _this);
        },
        buildSelector: function(){
            var result = {
                success: false,
                data: {
                    name: null,
                    handle: {}
                }
            };

            // build name
            var name = $("#selector-name").val();
            if (!name) {
                result.success = false;
                result.data = "名称不能为空";
                return result;
            }
            result.data.name = name;

            // build strategy
            result.data.desc = $("#selector-desc").val();

            //build handle
            // result.data.handle.continue = ($("#selector-continue").val() === "true");
            result.data.handle.log = ($("#selector-log").val() === "true");

            //enable or not
            var enable = true;//$('#selector-enable').is(':checked');
            result.data.enable = enable;

            result.success = true;
            return result;
        },
        buildRule: function(){
            var result = {
                success: false,
                data: {
                    name:null,
                    handle: {}
                }
            };
            var key = $("#rule-key").val();
            if(!key){
                result.success = false;
                result.data = "Key不能为空";
                return result;
            }
            result.data.name = key;
            result.data.key = key;
            var value = $("#rule-value").val();
            if(!value){
                result.success = false;
                result.data = "Value不能为空";
                return result;
            }
            result.data.value = value;
            result.data.handle.log = $("#rule-handle-log").val() === "true";
            result.data.enable = $("#rule-enable").is(':checked');
            result.success = true;
            return result;
        },
        initRuleEditDialog: function (type, context) {
            var op_type = type;
            var dialogTitle = context.dialogTitle || _this.dialogTitle;
            $(document).on("click", ".edit-btn", function () {
                var selector_id = $("#add-btn").attr("data-id");

                var tpl = $("#edit-tpl").html();
                var rule_id = $(this).attr("data-id");
                var rule = {};
                var rules = context.data.selector_rules[selector_id];
                var selector = context.data.selectors[selector_id];
                for (var i = 0; i < rules.length; i++) {
                    var r = rules[i];
                    if (r.id == rule_id) {
                        rule = r;
                        break;
                    }
                }
                if (!rule_id || !rule) {
                    L.Common.showErrorTip("提示", "要编辑的规则不存在或者查找出错");
                    return;
                }

                var html = juicer(tpl, {
                    r: rule
                });

                var d = dialog({
                    title: "编辑" + dialogTitle.rule,
                    width: 680,
                    content: html,
                    modal: true,
                    button: [{
                        value: '取消'
                    }, {
                        value: '预览',
                        autofocus: false,
                        callback: function () {
                            var rule = context.buildRule();
                            L.Common.showRulePreview(rule);
                            return false;
                        }
                    }, {
                        value: '保存修改',
                        autofocus: false,
                        callback: function () {
                            var result = context.buildRule();
                            result.data.id = rule.id;//拼上要修改的id
                            if (result.success == true) {
                                $.ajax({
                                    url: '/' + op_type + '/selectors/' + selector_id + "/rules",
                                    type: 'put',
                                    data: {
                                        rule: JSON.stringify(result.data),
                                        selector: JSON.stringify(selector)
                                    },
                                    dataType: 'json',
                                    success: function (result) {
                                        if (result.success) {
                                            //重新渲染规则
                                            L.Common.loadRules(op_type, context, selector_id);
                                            return true;
                                        } else {
                                            L.Common.showErrorTip("提示", result.msg || "编辑"+dialogTitle.rule+"发生错误");
                                            return false;
                                        }
                                    },
                                    error: function () {
                                        L.Common.showErrorTip("提示", "编辑"+dialogTitle.rule+"请求发生异常");
                                        return false;
                                    }
                                });

                            } else {
                                L.Common.showErrorTip("错误提示", result.data);
                                return false;
                            }
                        }
                    }
                    ]
                });

                L.Common.resetAddConditionBtn();//删除增加按钮显示与否
                L.Common.resetAddExtractionBtn();
                context.resetAddCredentialBtn && context.resetAddCredentialBtn();
                d.show();
            });
        },
    };
}(APP));
