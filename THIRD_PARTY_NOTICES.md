# 第三方材料说明

## VisA PCB4

本仓库的 PCB 原图和缺陷掩膜来自 Visual Anomaly（VisA）数据集的 PCB4 子集。

作者为 Yang Zou、Jongheon Jeong、Latha Pemula、Dongqing Zhang 和 Onkar Dabeer。

相关论文为 *SPot-the-Difference Self-Supervised Pre-training for Anomaly Detection and Segmentation*，ECCV 2022。

- [数据集官方项目](https://github.com/amazon-science/spot-diff)
- [原始数据许可文件](https://github.com/amazon-science/spot-diff/blob/main/LICENSE-DATASET)
- [Creative Commons Attribution 4.0 International](https://creativecommons.org/licenses/by/4.0/)
- [单张下载所用公开镜像](https://huggingface.co/datasets/imaadd05/visa-anomaly-detection)

原图像素和掩膜内容保留原始数据。文件名增加子集、标签和编号前缀。原路径映射见 `images/SOURCES.md`。QuickBuild 工程中的训练图以及运行截图中的 PCB 图像同样来源于 VisA。

## Cognex VisionPro

VisionPro、QuickBuild 和 PatMax 属于 Cognex 的产品或技术名称。本项目的 `.vpp` 文件由 VisionPro QuickBuild 保存。运行环境和所需许可由使用者安装配置。

`evidence` 中的图片记录本项目的实际配置和检测结果。具体数值及证据范围见 `开发调试记录.md`。
