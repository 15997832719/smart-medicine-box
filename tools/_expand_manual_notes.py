from pathlib import Path

path = Path(r'D:\smart-medicine-box\tools\build_copyright_materials.py')
text = path.read_text(encoding='utf-8')

def replace_once(old, new):
    global text
    count = text.count(old)
    if count != 1:
        raise SystemExit(f'replacement count {count} for: {old[:80]}')
    text = text.replace(old, new, 1)

replace_once(
"    add_text(doc, '为使文档中的技术名词和业务术语保持一致，本手册对以下常用术语进行说明。软件使用过程中涉及的相关概念，均以本节定义为准。')\n",
"    add_text(doc, '为使文档中的技术名词和业务术语保持一致，本手册对以下常用术语进行说明。软件使用过程中涉及的相关概念，均以本节定义为准。')\n    add_text(doc, '本手册中出现“老人端”时，指以老人账号登录后的功能界面；“家属端”指家属账号登录后用于查看绑定老人和进行照护协同的界面。API、JWT 等术语仅用于说明系统实现方式，不影响用户的基本操作。')\n"
)

replace_once(
"    add_text(doc, '软件在业务中主要承担信息记录、提醒和辅助识别作用，帮助家庭提高药品信息维护和服药过程管理的规范性。软件不替代医生诊断、处方、药师指导或药品说明书，涉及具体用药方案时应遵循专业医疗意见。')\n",
"    add_text(doc, '软件在业务中主要承担信息记录、提醒和辅助识别作用，帮助家庭提高药品信息维护和服药过程管理的规范性。软件不替代医生诊断、处方、药师指导或药品说明书，涉及具体用药方案时应遵循专业医疗意见。')\n    add_text(doc, '对于存在多种基础疾病、使用处方药或需要特殊剂量调整的用户，软件仅记录其自行维护的信息，不根据疾病名称自动推荐药品，也不根据历史数据调整剂量。')\n"
)

replace_once(
"    add_text(doc, '软件还提供拍照识药、说明书解析、家庭绑定和语音交互等辅助功能。AI 识别结果必须经过人工确认，家属只能访问已绑定老人的数据。通过数据关联、权限控制和人工复核机制，软件能够兼顾使用便利性与信息安全。')\n",
"    add_text(doc, '软件还提供拍照识药、说明书解析、家庭绑定和语音交互等辅助功能。AI 识别结果必须经过人工确认，家属只能访问已绑定老人的数据。通过数据关联、权限控制和人工复核机制，软件能够兼顾使用便利性与信息安全。')\n    add_text(doc, '软件还考虑了网络不可用、识别失败、权限关闭和重复确认等异常场景。出现异常时，界面会给出对应提示，用户可以改为手动录入、重新操作或稍后重试。')\n"
)

old_func_loop = """    for title, paragraphs in functions:
        doc.add_heading(title, level=3)
        for para in paragraphs:
            add_text(doc, para)
"""
new_func_loop = """    function_notes = {
        '4.1.1 用户注册与登录功能': '注册信息会保存到服务端，密码以不可逆摘要形式存储；移动端仅保存访问令牌和必要的当前用户信息。用户注销后，本地令牌会被清除。',
        '4.1.2 首页与用药概览功能': '首页数据由药品、计划、服药记录和告警接口汇总生成。若页面数据未及时更新，用户可以下拉刷新或重新进入首页。',
        '4.1.3 药品信息管理功能': '药品删除前应确认没有仍需使用的计划；历史服药记录不会因用户删除设备缓存而丢失，正式数据以服务端保存结果为准。',
        '4.1.4 AI 拍照识药功能': '图片仅用于本次识别，后端应在完成处理后删除临时文件。对于包装反光、文字缺失或存在多个药品名称的图片，建议重新拍摄。',
        '4.1.5 说明书解析功能': '解析结果只作为录入辅助，用户应将提取内容与说明书原文逐项核对；无法确认的禁忌和特殊人群信息不应自行推断。',
        '4.1.6 用药计划管理功能': '保存计划前，系统会校验药品、时间和剂量是否为空，并避免重复提交。计划时间发生变化后，以修改后的设置为准。',
        '4.1.7 服药提醒与确认功能': '不同手机厂商对后台通知限制不同，用户应按照系统提示允许必要权限。语音确认无法唯一匹配计划时，系统不会生成服药记录。',
        '4.1.8 风险告警功能': '告警只表示系统判断存在需要核对的情况，不代表医学结论。用户处理告警后，可更新库存、有效期或计划信息使页面状态恢复。',
        '4.1.9 家庭绑定功能': '邀请码具有时效性，不应公开发布。绑定关系解除后，家属端将无法继续读取老人数据，历史数据的处理应遵循双方约定和适用法律。',
        '4.1.10 语音助手与音箱接入功能': '语音识别结果和文字查询均由用户主动触发，系统不会在未授权情况下持续录音。音箱绑定完成后应与当前老人账号保持一致。',
    }
    for title, paragraphs in functions:
        doc.add_heading(title, level=3)
        for para in paragraphs:
            add_text(doc, para)
        if title in function_notes:
            add_text(doc, function_notes[title])
"""
replace_once(old_func_loop, new_func_loop)

replace_once(
"    fig_med = Figure('medicines', FIGURES[3].source, '药品管理功能', '图 4-1  药品管理功能', '药品管理页面。')\n    add_figure_page(doc, fig_med, fig_paths[fig_med.key])\n",
""
)
replace_once(
"    fig_ai = Figure('ai_recognize', FIGURES[5].source, 'AI 拍照识药功能', '图 4-2  AI 拍照识药功能', '拍照识药页面。')\n",
"    fig_ai = Figure('ai_recognize', FIGURES[5].source, 'AI 拍照识药功能', '图 4-1  AI 拍照识药功能', '拍照识药页面。')\n"
)
replace_once(
"    fig_plan = Figure('schedules', FIGURES[7].source, '用药计划管理功能', '图 4-3  用药计划管理功能', '用药计划列表页面。')\n",
"    fig_plan = Figure('schedules', FIGURES[7].source, '用药计划管理功能', '图 4-2  用药计划管理功能', '用药计划列表页面。')\n"
)

replace_once(
"    for title, text in technologies:\n        doc.add_heading(title, level=3)\n        add_text(doc, text)\n",
"""    technology_notes = {
        '5.2.1 前后端分离技术': '接口层统一处理错误码和鉴权信息，移动端根据状态码显示可理解的提示，便于问题定位和后续维护。',
        '5.2.2 图像识别与人工复核技术': '模型服务不可用或识别失败时，软件保留手动录入路径，不因第三方服务异常阻断基本药品管理功能。',
        '5.2.3 家庭数据隔离与授权技术': '每次访问老人数据时，后端都会重新校验关系，而不是仅依赖客户端状态，降低越权风险。',
        '5.2.4 药品-计划-记录关联模型': '库存扣减和记录写入在同一业务处理中完成，减少记录成功但库存未更新的情况。',
        '5.2.5 多端提醒与语音交互技术': '语音确认优先使用计划编号，其次按药品名称匹配；存在多个候选计划时要求用户进一步说明。',
        '5.2.6 安全配置与审计技术': '审计信息仅用于问题追踪和安全核查，生产环境应限制审计数据访问权限并定期备份。',
    }
    for title, text in technologies:
        doc.add_heading(title, level=3)
        add_text(doc, text)
        if title in technology_notes:
            add_text(doc, technology_notes[title])
"""
)

replace_once(
"    add_text(doc, '数据访问层通过统一的数据模型访问 SQLite 数据库，保存用户、药品、计划、提醒、服药记录、家庭关系、音箱关系和审计日志等信息。数据库对象之间通过用户标识和业务主键建立关联，为查询、统计和权限校验提供基础。')\n",
"    add_text(doc, '数据访问层通过统一的数据模型访问 SQLite 数据库，保存用户、药品、计划、提醒、服药记录、家庭关系、音箱关系和审计日志等信息。数据库对象之间通过用户标识和业务主键建立关联，为查询、统计和权限校验提供基础。')\n    add_text(doc, '该架构使界面展示、业务规则和数据存储相互分离。移动端升级不影响后端数据结构，后端增加新接口时也可以供音箱或其他终端复用。')\n"
)

replace_once(
"    for title, paragraphs in operations:\n        doc.add_heading(title, level=2)\n        for para in paragraphs:\n            add_text(doc, para)\n",
"""    operation_notes = {
        '6.1 软件启动与登录': '若无法登录，应检查账号、密码和网络状态；未实现找回功能时联系技术支持，不应尝试使用他人账号。',
        '6.2 软件首页使用': '首页统计以当前登录用户或已选择老人的数据为准，家属切换老人后应确认页面标题是否正确。',
        '6.3 药品管理操作': '保存药品后建议再次核对名称、剂量和有效期。软件记录只影响本软件，不改变药品实际包装上的说明。',
        '6.4 AI 拍照识药操作': '识别过程中不要重复提交，避免产生多个临时结果。保存前应确认当前药品没有被误识别为其他名称。',
        '6.5 用药计划管理操作': '设置提醒时间时应考虑老人作息和手机系统限制，避免多个计划使用完全相同的提醒时间造成通知叠加。',
        '6.6 提醒中心与服药确认操作': '确认服药应由实际执行人完成。家属代确认前应与老人核实，避免记录与实际服药不一致。',
        '6.7 家庭绑定操作': '邀请码泄露时，老人应重新生成邀请码，旧邀请码失效后不能被继续用于绑定。',
        '6.8 音箱接入操作': '如果音箱提示绑定失败，应先确认配对码未过期、账号未绑定其他音箱，并检查网络连接。',
        '6.9 家属端操作': '家属查看数据时应尊重老人隐私。新增、修改或删除老人药品前，应先取得老人或照护责任人的确认。',
    }
    for title, paragraphs in operations:
        doc.add_heading(title, level=2)
        for para in paragraphs:
            add_text(doc, para)
        if title in operation_notes:
            add_text(doc, operation_notes[title])
"""
)

replace_once(
"    for title, paragraphs in stages:\n        doc.add_heading(title, level=2)\n        for para in paragraphs:\n            add_text(doc, para)\n",
"""    stage_notes = {
        '7.1 需求分析阶段': '需求分析结果形成软件功能清单和主要业务流程图，作为后续设计和验收依据。',
        '7.2 架构设计阶段': '架构设计阶段同时考虑接口安全、数据库备份、移动端权限和第三方模型服务异常等情况。',
        '7.3 功能开发阶段': '开发过程中对核心业务规则保留必要说明，并按模块进行自测，减少后期联调成本。',
        '7.4 联调测试阶段': '测试覆盖正常流程、异常输入、重复操作和无权限访问等情况，并对重要问题保留处理记录。',
        '7.5 问题修正与发布整理阶段': '发布前对软件名称、版本号、包名、源代码和文档进行一致性检查，并将申报文件单独归档。',
    }
    for title, paragraphs in stages:
        doc.add_heading(title, level=2)
        for para in paragraphs:
            add_text(doc, para)
        if title in stage_notes:
            add_text(doc, stage_notes[title])
"""
)

replace_once(
"    add_text(doc, '为避免数据泄露，请通过约定的支持渠道反馈问题，不要将数据库、密钥、完整病历或无关药品信息发送给未授权人员。生产环境应定期备份数据库，并妥善管理账号和密钥。')\n",
"    add_text(doc, '为避免数据泄露，请通过约定的支持渠道反馈问题，不要将数据库、密钥、完整病历或无关药品信息发送给未授权人员。生产环境应定期备份数据库，并妥善管理账号和密钥。')\n    add_text(doc, '技术支持单位、联系人、电话和邮箱由软件提供方填写。未正式发布的应用应通过项目约定的内部渠道反馈问题，不应在公共平台传播安装包或测试账号。')\n    add_text(doc, '使用过程中应遵循最小必要原则，不在非必要场景上传身份证、病历或其他敏感资料。与软件功能无关的数据不需要提供给技术支持人员。')\n"
)

path.write_text(text, encoding='utf-8')
print('manual expansion patch applied')
