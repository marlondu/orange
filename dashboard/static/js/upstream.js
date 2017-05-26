(function(L){
	var _this = null;
	L.upstream = L.upstream || {};
	_this = L.upstream = {
		// 用于存数据
		data: {

		},
		dialogTitle: {
			selector: "Upstream",
			rule: "Server"
		},
		// L.common对象在static/js/orange.js中定义
		init: function(){
			L.Common.loadConfigs("upstream", _this, true);// 向/upstream/selectors发送请求, 获取配置，存储在data中
			_this.initEvents();
		},
		initEvents:function(){
			L.Common.initRuleAddDialog("upstream", _this);//添加规则对话框
            L.Common.initRuleDeleteDialog("upstream", _this);//删除规则对话框
            L.Common.initRuleEditDialog("upstream", _this);//编辑规则对话框
            L.Common.initRuleSortEvent("upstream", _this);

            this.initSelectorAddDialog("upstream", _this);
            L.Common.initSelectorDeleteDialog("upstream", _this);
            this.initSelectorEditDialog("upstream", _this);
            L.Common.initSelectorSortEvent("upstream", _this);
            this.initSelectorClickEvent("upstream", _this);

            /* L.Common.initSelectorTypeChangeEvent();//选择器类型选择事件
            L.Common.initConditionAddOrRemove();//添加或删除条件
            L.Common.initJudgeTypeChangeEvent();//judge类型选择事件
            L.Common.initConditionTypeChangeEvent();//condition类型选择事件

            L.Common.initExtractionAddOrRemove();//添加或删除条件
            L.Common.initExtractionTypeChangeEvent();//extraction类型选择事件
            L.Common.initExtractionAddBtnEvent();//添加提前项按钮事件
            L.Common.initExtractionHasDefaultValueOrNotEvent();//提取项是否有默认值选择事件 */

            L.Common.initViewAndDownloadEvent("upstream", _this);
            L.Common.initSwitchBtn("upstream", _this);//redirect关闭、开启
            L.Common.initSyncDialog("upstream", _this);//编辑规则对话框
		},
		buildRule: function(){
			var result = {
				success: false,
				data: {
					name: null,
					handle: {}
				}
			};
			var name = $("#rule-name").val();
			if(!name){
				result.success = false;
				result.data = "名称不能为空";
				return result;
			}
			result.data.name = name;
			var host = $("#rule-host").val();
			if(!host){
				result.success = false;
				result.data = "host不能为空";
				return result;
			}
			result.data.host = host;

			var weight = $("#rule-weight").val();
			if(weight && isNaN(weight)){
				result.success = false;
				result.data = "Weight只能是整型数字或空";
				return result;
			}
			result.data.weight = weight;

			var max_conns = $("#rule-max_conns").val();
			if(max_conns && isNaN(max_conns)){
				result.success = false;
				result.data = "max_conns只能是整型数字或空";
				return result;
			}
			result.data.max_conns = max_conns;

			var max_fails = $("#rule-max_fails").val();
			if(max_fails && isNaN(max_fails)){
				result.success = false;
				result.data = "max_fails只能是整型数字或空";
				return result;
			}
			result.data.max_fails = max_fails;

			var fail_timeout = $("#rule-fail_timeout").val();
			if(fail_timeout && isNaN(fail_timeout)){
				result.success = false;
				result.data = "max_fails只能是整型数字或空";
				return result;
			}
			result.data.fail_timeout = fail_timeout;
			result.data.backup = $("#rule-backup").is(':checked');
			result.data.down = $("#rule-down").is(':checked');
			result.data.resolve = $("#rule-resolve").is(':checked');
			result.data.route = $("#rule-route").val();
			result.data.service = $("#rule-service").val();
			result.data.slow_start = $("#rule-slow_start").val();

			result.data.handle.log = $("#rule-handle-log").val() === "true";
			result.data.enable = $("#rule-enable").is(':checked');
			result.success = true;
			return result;
		},
		buildHandle: function(){

		},
		initSelectorClickEvent: function(type, context){
			var op_type = type;
            $(document).on("click", ".selector-item", function () {
                var self = $(this);
                var upstream_id = self.attr("data-id");
                var upstream_name = self.attr("data-name");
                if(upstream_name){
                    $("#rules-section-header").text("Upstream【" + upstream_name + "】Server列表");
                }

                $(".selector-item").each(function(){
                    $(this).removeClass("selected-selector");
                })
                self.addClass("selected-selector");

                $("#add-btn").attr("data-id", upstream_id);
                L.Common.loadRules(op_type, context, upstream_id);
            });
		},
		buildSelector: function(){
            var result = {
                success: false,
                data: {
                    name: null,
                    strategy: "",
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
            result.data.strategy = $("#selector-strategy").val();

            //build handle
            // result.data.handle.continue = ($("#selector-continue").val() === "true");
            result.data.handle.log = ($("#selector-log").val() === "true");

            //enable or not
            var enable = $('#selector-enable').is(':checked');
            result.data.enable = enable;

            result.success = true;
            return result;
        },
		initSelectorAddDialog: function (type, context) {
            var op_type = type;
            $("#add-selector-btn").click(function () {
                var current_selected_id;
                var current_selected_selector = $("#selector-list li.selected-selector");
                if(current_selected_selector){
                    current_selected_id = $(current_selected_selector[0]).attr("data-id");
                }

                var content = $("#add-selector-tpl").html()
                var d = dialog({
                    title: '添加Upstream',
                    width: 720,
                    content: content,
                    modal: true,
                    button: [{
                        value: '取消'
                    },{
                        value: '确定',
                        autofocus: false,
                        callback: function () {
                            var result = _this.buildSelector();
                            if (result.success) {
                                $.ajax({
                                    url: '/' + op_type + '/selectors',
                                    type: 'post',
                                    data: {
                                        selector: JSON.stringify(result.data)
                                    },
                                    dataType: 'json',
                                    success: function (result) {
                                        if (result.success) {
                                            //重新渲染
                                            L.Common.loadConfigs(op_type, context, false, function(){
                                                $("#selector-list li[data-id=" + current_selected_id+"]").addClass("selected-selector");
                                            });
                                            return true;
                                        } else {
                                            L.Common.showErrorTip("提示", result.msg || "添加选择器发生错误");
                                            return false;
                                        }
                                    },
                                    error: function () {
                                        L.Common.showErrorTip("提示", "添加选择器请求发生异常");
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
                d.show();
            });
        },
        initSelectorEditDialog: function(type, context){
            var op_type = type;

            $(document).on("click", ".edit-selector-btn", function (e) {
                e.stopPropagation();// 阻止冒泡
                var tpl = $("#edit-selector-tpl").html();
                var selector_id = $(this).attr("data-id");
                var selectors = context.data.selectors;
                selector = selectors[selector_id];
                if (!selector_id || !selector) {
                    L.Common.showErrorTip("提示", "要编辑的选择器不存在或者查找出错");
                    return;
                }

                var html = juicer(tpl, {
                    s: selector
                });

                var d = dialog({
                    title: "编辑Upstream",
                    width: 680,
                    content: html,
                    modal: true,
                    button: [{
                        value: '取消'
                    }, {
                        value: '预览',
                        autofocus: false,
                        callback: function () {
                            var s = _this.buildSelector();
                            L.Common.showRulePreview(s);
                            return false;
                        }
                    }, {
                        value: '保存修改',
                        autofocus: false,
                        callback: function () {
                            var result = _this.buildSelector();
                            result.data.id = selector.id;//拼上要修改的id
                            result.data.rules = selector.rules;//拼上已有的rules

                            if (result.success == true) {
                                $.ajax({
                                    url: '/' + op_type + '/selectors',
                                    type: 'put',
                                    data: {
                                        selector: JSON.stringify(result.data)
                                    },
                                    dataType: 'json',
                                    success: function (result) {
                                        if (result.success) {
                                            //重新渲染规则
                                            L.Common.loadConfigs(op_type, context);
                                            return true;
                                        } else {
                                            L.Common.showErrorTip("提示", result.msg || "编辑选择器发生错误");
                                            return false;
                                        }
                                    },
                                    error: function () {
                                        L.Common.showErrorTip("提示", "编辑选择器请求发生异常");
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
                d.show();
            });
        }
	}

})(APP);// 该APP对象在common_js.html中定义