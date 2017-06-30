(function(L){
	//var _this = null;
	// L.interface = L.interface || {};
	var _this = L.interface = {
		// 用于存数据
		data: {

		},
		dialogTitle: {
			selector: "组",
			rule: "接口"
		},
		// L.common对象在static/js/orange.js中定义
		init: function(){
			L.Common.loadConfigs("interface", _this, true);// 向/upstream/selectors发送请求, 获取配置，存储在data中
			_this.initEvents();
			console.log(_this.data);
		},
		initEvents: function(){
			$("#table-view h4").text("接口组列表");
            $("#rules-section-header").text("接口列表");
            $("#add-btn span").text("添加新接口");
            $("#add-selector-btn span").text("添加接口组")
            $("#searcher").show();

            L.Common.initKeywordChangeEvent("interface", _this);

            L.Common.initRuleAddDialog("interface", _this);//添加规则对话框
            L.Common.initRuleDeleteDialog("interface", _this);//删除规则对话框
            L.Common.initRuleEditDialog("interface", _this);//编辑规则对话框
            L.Common.initRuleSortEvent("interface", _this);

            L.Common.initSelectorAddDialog("interface", _this);
            L.Common.initSelectorDeleteDialog("interface", _this);
            L.Common.initSelectorEditDialog("interface", _this);
            L.Common.initSelectorSortEvent("interface", _this);
            L.Common.initSelectorClickEvent("interface", _this);
            // 添加联系人
            L.Common.initConditionAddOrRemove();//添加或删除条件

            L.Common.initViewAndDownloadEvent("interface", _this);
            L.Common.initSwitchBtn("interface", _this);//redirect关闭、开启
            L.Common.initSyncDialog("interface", _this);//编辑规则对话框

            _this.initStatisticBtnEvent();
            _this.initLimitClickEvent();
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
            var enable = $('#selector-enable').is(':checked');
            result.data.enable = enable;

            result.success = true;
            return result;
		},
		buildRule: function(){
			var result = {
				success: false,
				data: {
					name: null,
					handle: {},
					charge: {},// 存放负责人
					limit:{}
				}
			};
			var name = $("#rule-name").val();
			if(!name){
				result.success = false;
				result.data = "名称不能为空";
				return result;
			}
			result.data.name = name;

			var uri = $("#rule-uri").val();
			if(!uri){
				result.success = false;
				result.data = "URI不能为空";
				return result;
			}
			result.data.uri = uri;
			// build charge
			var charge = _this.buildCharge();
			if(!charge.success){
				result.data = charge.message;
				return result;
			}
			result.data.charge.users = charge.users;

			// limit
			var limit_enable = $("#rule-limit").is(':checked');
			var limit_times = $("[name='rule-limit-times']").val() || 200;
			var burst_times = $("[name='rule-burst-times']").val() || 100;
			result.data.limit.enable = limit_enable;
			result.data.limit.times = limit_times;
			result.data.limit.burst = burst_times;

			result.data.desc = $("#rule-desc").val();
            result.data.monitor = $('#rule-monitor').is(':checked');
			result.data.handle.log = $("#rule-handle-log").val() === "true";
			result.data.enable = $("#rule-enable").is(':checked');
			result.success = true;
			return result;
		},
		buildCharge: function(){
			var charge = {
				success: false,
				message: "",
				users: []
			};
			var users = [];
			var temp_success = true;
			$(".condition-holder").each(function(){
				var self = $(this);
				var user = {};
				user.name = self.find("input[name=rule-user-name]").val();
				if(!user.name){
					temp_success = false;
					charge.message = "负责人姓名不能为空";
				}
				user.phone = self.find("input[name=rule-user-phone]").val();
				var phoneRegex = /^1(3[0-9]|4[57]|5[0-35-9]|7[0135678]|8[0-9])\d{8}$/;
				if(!phoneRegex.test(user.phone)){
					temp_success = false;
					charge.message = "负责人" + user.name + "手机号输入有误";
				}
				user.email = self.find("input[name=rule-user-email]").val();
				var emailRegex = /^([a-zA-Z0-9_-])+@([a-zA-Z0-9_-])+(.[a-zA-Z0-9_-])+/;
				if(!emailRegex.test(user.email)){
					temp_success = false;
					charge.message = "负责人" + user.name + "邮箱输入有误";
				}
				users.push(user);
			});

			charge.users = users;
			charge.success = temp_success;
			return charge;
		},
		initStatisticBtnEvent:function(){
            $(document).on( "click",".statistic-btn", function(){
                var self = $(this);
                var rule_id = self.attr("data-id");
                var rule_name = self.attr("data-name");
                var rule_uri = self.attr("data-uri");
                if(!rule_id){
                    return;
                }
                window.location.href = "/monitor/rule/statistic?rule_id="+rule_id+"&rule_name="+encodeURI(rule_name)+"&rule_uri=" + encodeURI(rule_uri);
            });

        },
        initKeywordChangeEvent: function(type, context){
        	var op_type = type;
        	$("#keyword").keyup(function(){
        		var keyword = $(this).val();
        		var words = [];
        		var keywords = keyword.split(/[\s]+/i);
        		var len = keywords.length;
        		for(var i = 0;i < len;i++){
        			if(keywords[i]){
        				words.push(keywords[i])
        			}
        		}
        		var selector_id = $("#add-btn").attr("data-id");
        		_this.loadRulesWithKeywords(op_type, context, selector_id, words);
        	});
        },
        loadRulesWithKeywords: function (type, context, selector_id, words) {
            var op_type = type;
            $.ajax({
                url: '/' + op_type + '/selectors/' + selector_id + "/rules",
                type: 'get',
                cache: false,
                data: {},
                dataType: 'json',
                success: function (result) {
                    if (result.success) {
                        $("#switch-btn").show();
                        $("#view-btn").show();

                        var total_rules = result.data.rules;
                        var filtered_rules = [];
                        if(words){
                        	for(i in total_rules){
                        		var uri = total_rules[i].uri;
                        		var flag = true;
                        		for(j in words){
                        			if(uri.indexOf(words[j]) == -1){
                        				flag = false;
                        				break;
                        			}
                        		}
                        		if(flag){
                        			filtered_rules.push(total_rules[i]);
                        		}
                        	}
                        	//if(filtered_rules.length > 0){
	                        	result.data.rules = filtered_rules;
	                        //}
                        }
                        //重新设置数据
                        context.data.selector_rules = context.data.selector_rules || {};
                        context.data.selector_rules[selector_id] = result.data.rules;
                        L.Common.renderRules(result.data);
                    } else {
                        L.Common.showErrorTip("错误提示", "查询" + op_type + "规则发生错误");
                    }
                },
                error: function () {
                    L.Common.showErrorTip("提示", "查询" + op_type + "规则发生异常");
                }
            });
        },
        initLimitClickEvent: function(){
        	$(document).on('load', '#judge-area', function(event){
        		var enable = $(this).is(":checked");
        		$("[name='rule-limit-times']").attr('disabled',!enable);
        		$("[name='rule-burst-times']").attr('disabled', !enable);
        	});
        	$(document).on('click', '#judge-area #rule-limit', function(event){
        		var enable = $(this).is(":checked");
        		$("[name='rule-limit-times']").attr('disabled',!enable);
        		$("[name='rule-burst-times']").attr('disabled', !enable);
        	});
        }
	}

})(APP);