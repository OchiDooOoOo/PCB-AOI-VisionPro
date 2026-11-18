# 样本来源

图像来自 Yang Zou、Jongheon Jeong、Latha Pemula、Dongqing Zhang 和 Onkar Dabeer 发布的 Visual Anomaly（VisA）数据集，使用 `pcb4` 子集。从公开镜像单张下载，图像和掩膜保留原始内容，文件名加上了子集、标签和原编号。

- [数据集官方发布页](https://github.com/amazon-science/spot-diff)
- [CC BY 4.0 许可](https://creativecommons.org/licenses/by/4.0/)
- [单张文件镜像](https://huggingface.co/datasets/imaadd05/visa-anomaly-detection/tree/main/pcb4)
- [PCB4 逐图标注](https://huggingface.co/datasets/imaadd05/visa-anomaly-detection/blob/main/pcb4/image_anno.csv)

| 本地文件 | `pcb4` 下的原路径 | 来源标注 | 当前用途 |
| --- | --- | --- | --- |
| `reference/visa_pcb4_normal_0000.jpg` | `Data/Images/Normal/0000.JPG` | `normal` | QuickBuild 导入和 PMAlign 基准图 |
| `raw/visa_pcb4_normal_0001.jpg` | `Data/Images/Normal/0001.JPG` | `normal` | 正常对照和换图调试 |
| `raw/visa_pcb4_missing_046.jpg` | `Data/Images/Anomaly/046.JPG` | `missing` | 验证板底小电阻有无。该元件在基准图中倒置，丝印读作 `122` |
| `raw/visa_pcb4_missing_049.jpg` | `Data/Images/Anomaly/049.JPG` | `missing` | 板底 `122` 小电阻仍在，可用于检查局部 ROI 是否受其他位置缺件干扰 |
| `raw/visa_pcb4_wrong_place_090.jpg` | `Data/Images/Anomaly/090.JPG` | `wrong place` | 观察板上方的异常位置，待确认偏位检测目标 |
| `raw/visa_pcb4_wrong_place_096.jpg` | `Data/Images/Anomaly/096.JPG` | `wrong place` | 观察板上方的异常位置，待确认偏位检测目标 |
| `masks/visa_pcb4_mask_{046,049,090,096}.png` | `Data/Masks/Anomaly/{046,049,090,096}.png` | 像素级缺陷标注 | 核对缺陷区域 |

以上图像用于开发调试。首版按指定元件判定，样本的预期结果由该元件的实际状态决定。后续用未参与调参的样本记录 QuickBuild 实测结果。
