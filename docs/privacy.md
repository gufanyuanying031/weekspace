# 数据与隐私

- 计划、课表、任务池、归档、总结位于 `~/Library/Application Support/Weekspace/planner.json`。
- 日常上一份存档为 `planner.previous.json`；从旧版升级时保留 `planner.pre-v002.json`。
- API Key 独立位于 `~/Library/Application Support/Weekspace-Private/api-key`。此文件为明文，目录权限为 700，文件权限为 600，不包含在计划导出中。
- 不读取旧钥匙串项目，不需要 Mac 登录密码。不内置 API Key。
- 每日哲思会请求一言接口，发送分类和长度等公共参数，不发送任务内容。
- AI 复盘与排程由用户点击触发，发送所选七天的记录、任务池和填写的目标。
- Excel、CSV、TSV 在本机解析。只有明确选择 AI 辅助识别并点击发送后，才会向配置的模型接口发送课表文本。
- 没有遥测或云端账户同步；应用的数据不会自动上传到此 GitHub 仓库。

导出 JSON 可以备份计划。恢复前先彻底退出应用，保存现有文件，再替换 `planner.json`。避免同时运行多个版本修改同一份数据库。

公开报告问题时，请使用合成课表，移除真实姓名、学号、课程账号和密钥。
