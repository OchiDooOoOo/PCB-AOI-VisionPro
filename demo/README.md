# 截图演示

项目使用可运行工程、实际结果截图及实测记录展示。推荐打开 `visionpro/PCB_AOI_position.vpp`，按 [演示操作说明](../演示操作说明.md)进行现场操作。

2026-11-19，正常和缺件两个分支已完成用户界面验收。

| 场景 | 结果 | 完整截图 |
| --- | --- | --- |
| 正常 `0001` | OK / PASS，BlobCount 2，目标找到 | [正常完整结果](../evidence/normal_0001_queue_fields.png) |
| 缺件 `046` | NG / TARGET_MISSING，BlobCount 0，目标未找到、坐标 NaN | [缺件完整结果](../evidence/missing_046_queue_fields.png) |
| 电阻模板定位 | 分数约 0.987，中心约 (215.99, 455.98) | [第二个 PMAlign 结果](../evidence/target_0001_position.png) |

可以在面试中展示工具流程，选择正常图运行，再切换缺件图运行。在 QuickBuild 主窗口的“显示 → 浮动结果”中，选择最新数据包查看 Decision、Reason、BlobCount 和图像。

图像来自 VisA PCB4，仅检查底部 `122` 电阻。真实目标偏位图片验证和独立测试集统计待补充。
