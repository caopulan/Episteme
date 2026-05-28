# Episteme 界面展示

<p align="center">
  <strong>简体中文</strong> · <a href="showcase.md">English</a>
</p>

这个页面用真实的 macOS app 截图展示 Episteme 当前界面。截图来自一个真实本地论文库，因此展示的是日常使用流程和实际产品状态。

## 介绍视频

Remotion 源码位于 [docs/video](video)。渲染后的视频是详细版产品介绍，使用真实 Episteme 截图、生成图像结果、app 内预览截图，以及会推进到对应控件的动态聚焦镜头：

[docs/assets/videos/episteme-intro.mp4](assets/videos/episteme-intro.mp4)

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

文库界面面向高频论文整理。左侧展示文件夹结构，中间列表保持适合扫描的密度，右侧详情面板同步呈现元数据、标签和文件夹归属。

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

## 4. 生成图像结果

![生成图像结果](assets/screenshots/generated-output.png)

生成图像也可以成为研究 session 的一部分。Episteme 会把资产保留在会话工作区里，并让它回到阅读流程中进行应用内预览。

![app 内生成图像预览](assets/screenshots/in-app-image-preview.png)

视频会使用这个真实预览状态，展示生成图像在 Episteme 内部完成检查和放大查看。

## 5. 会话和设置

![最近会话](assets/screenshots/recent-conversations.png)

Recent Conversations 让之前的研究工作可以继续。每个会话都能回到对应论文上下文和 session 详情。

![设置](assets/screenshots/settings.png)

设置页暴露真实工作流需要的本地控制项：语言、arXiv 订阅、本地排序来源、Codex 增强、embedding 服务和可复用快捷 Prompt。

## 6. 聚焦演示截图

![文件夹筛选后的文库](assets/screenshots/library-folder-filter.png)

新版视频使用文件夹筛选后的文库、阅读器和对话截图，让镜头可以移动到正在介绍的具体 UI 区域。

![阅读器与活跃 Codex session](assets/screenshots/session-generated-chat.png)

## 截图维护

这些截图是有意保留的真实产品截图。如果 UI 发生变化，可以先重建并打开 app：

```bash
scripts/build-app-bundle.sh
open "$HOME/Applications/Episteme.app"
```

然后替换以下图片：

```text
docs/assets/screenshots/
├── library.png
├── discover.png
├── reader-chat.png
├── generated-output.png
├── in-app-image-preview.png
├── library-folder-filter.png
├── session-generated-chat.png
├── recent-conversations.png
└── settings.png
```
