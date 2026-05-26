# Paper Codex 界面展示

<p align="center">
  <strong>简体中文</strong> · <a href="showcase.md">English</a>
</p>

这个页面用真实的 macOS app 截图展示 Paper Codex 当前界面。截图来自一个真实本地论文库，因此展示的是日常使用流程，而不是占位 mockup。

## 1. 阅读器与 Codex 对话

![阅读器与 Codex 对话](assets/screenshots/reader-chat.png)

阅读器是主要工作界面。论文标签页固定在顶层 chrome，PDF 工具栏把页码和缩放放在文档附近，右侧面板把对话和笔记保留在同一个阅读上下文中。

这个界面展示了：

- 基于 PDFKit 的阅读、翻页和缩放控制。
- 类似浏览器的论文标签页，可以保留多个活跃论文。
- Codex 对话可以引用并回跳到 PDF 原文区域。
- 紧凑的会话控制，用于在对话和笔记之间切换。

## 2. 本地论文文库

![本地论文文库](assets/screenshots/library.png)

文库界面面向高频论文整理。左侧展示文件夹结构，中间列表保持适合扫描的密度，右侧详情面板可以在不离开列表的情况下检查元数据、标签和文件夹归属。

这个界面展示了：

- 带论文数量的嵌套文件夹。
- 按标题、作者、标签、类别、年份和来源搜索。
- 用 PDF 缩略图快速识别论文。
- 在一个本地工作区里完成收藏、阅读、标签和文件夹操作。

## 3. arXiv Discover

![arXiv Discover](assets/screenshots/discover.png)

Discover 把 arXiv 浏览变成本地优先的论文发现流程。它组合了日期/类别过滤、本地缩略图缓存、相似度分数、Codex 生成的中文总结，以及保存和打开动作。

这个界面展示了：

- 按日期范围和 arXiv 类别搜索。
- 本地缓存论文卡片、PDF 缩略图和元数据。
- Codex 增强生成中文标题、总结、贡献说明和标签。
- 从结果网格直接保存到文库或打开阅读器。

## 截图维护

这些截图是有意保留的真实产品截图。如果 UI 发生变化，可以先重建并打开 app：

```bash
scripts/build-app-bundle.sh
open "$HOME/Applications/PaperCodex.app"
```

然后替换以下图片：

```text
docs/assets/screenshots/
├── library.png
├── discover.png
└── reader-chat.png
```
