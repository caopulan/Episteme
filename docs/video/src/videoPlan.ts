export const VIDEO = {
  fps: 30,
  width: 1920,
  height: 1080,
  durationInFrames: 2640,
};

export const COLORS = {
  ink: "#142033",
  muted: "#65758B",
  soft: "#F6F8FB",
  white: "#FFFFFF",
  blue: "#1F7AFF",
  green: "#20B26B",
  orange: "#F59E3D",
  cyan: "#28B7C8",
  violet: "#7567F4",
  red: "#EC5C5C",
  line: "rgba(20, 32, 51, 0.12)",
};

export const FONT =
  '-apple-system, BlinkMacSystemFont, "SF Pro Display", "PingFang SC", "Helvetica Neue", Arial, sans-serif';

export type Rect = {
  x: number;
  y: number;
  w: number;
  h: number;
};

export type Point = {
  x: number;
  y: number;
};

export type SceneBase = {
  id: string;
  from: number;
  duration: number;
};

export type IntroScene = SceneBase & {
  kind: "intro";
  title: string;
  body: string;
  pills: Array<{label: string; color: string}>;
};

export type ContextScene = SceneBase & {
  kind: "context";
  eyebrow: string;
  title: string;
  body: string;
  cards: Array<{title: string; body: string; color: string}>;
};

export type WalkthroughScene = SceneBase & {
  kind: "walkthrough";
  chapter: string;
  asset: string;
  accent: string;
  title: string;
  body: string;
  bullets: string[];
  focus: Rect;
  callout: {
    title: string;
    body: string;
    side: "left" | "right" | "top" | "bottom";
  };
  captionSide: "left" | "right";
  cursor: {
    from: Point;
    to: Point;
    clickAt: number;
  };
  zoom: {
    scale: number;
    delay: number;
  };
};

export type WorkflowScene = SceneBase & {
  kind: "workflow";
  title: string;
  body: string;
  steps: Array<{label: string; body: string; color: string}>;
};

export type ClosingScene = SceneBase & {
  kind: "closing";
  title: string;
  body: string;
  items: string[];
};

export type VideoScene = IntroScene | ContextScene | WalkthroughScene | WorkflowScene | ClosingScene;

export const scenes: VideoScene[] = [
  {
    id: "intro",
    kind: "intro",
    from: 0,
    duration: 155,
    title: "一个围绕论文上下文运转的本地研究台",
    body: "从 arXiv 发现、本地文库、PDF 阅读，到 Codex 对话和生成图像，全程串成一条可复盘的研究线。",
    pills: [
      {label: "本地文库", color: COLORS.blue},
      {label: "原文锚定问答", color: COLORS.green},
      {label: "arXiv Discover", color: COLORS.orange},
      {label: "可检查的会话工作区", color: COLORS.violet},
    ],
  },
  {
    id: "context",
    kind: "context",
    from: 132,
    duration: 185,
    eyebrow: "production goal",
    title: "研究体验的关键，是让上下文连续起来",
    body: "Paper Codex 把论文、文件夹、标签、页面、AI 记录和生成资产放在同一个工作面里，让每一步都能自然接上下一步。",
    cards: [
      {title: "文库归位", body: "文件夹、标签、收藏和论文详情在同一屏持续同步。", color: COLORS.blue},
      {title: "阅读锚定", body: "页面、缩放、论文选择和问答面板保持稳定关系。", color: COLORS.green},
      {title: "AI 可复盘", body: "prompt、回答、图片和 session 资产形成可追踪记录。", color: COLORS.orange},
      {title: "发现可沉淀", body: "arXiv 卡片、筛选、保存和本地相似度进入文库循环。", color: COLORS.violet},
    ],
  },
  {
    id: "library-folders",
    kind: "walkthrough",
    chapter: "01 Library",
    from: 290,
    duration: 260,
    asset: "assets/screenshots/library-folder-filter.png",
    accent: COLORS.blue,
    title: "文件夹从导航到保存都贴着论文流",
    body: "左侧树、顶部筛选、论文数量和详情面板在同一屏响应，切换文件夹保持轻快。",
    bullets: ["文件夹树指向真实分类", "20 papers 等数量跟随筛选", "详情面板即时更新"],
    focus: {x: 56, y: 758, w: 244, h: 54},
    callout: {
      title: "自然的文件夹树",
      body: "拐角线连接层级，选中状态和数量一起说明当前集合。",
      side: "right",
    },
    captionSide: "right",
    cursor: {from: {x: 230, y: 905}, to: {x: 181, y: 787}, clickAt: 98},
    zoom: {scale: 1.24, delay: 20},
  },
  {
    id: "library-paper-row",
    kind: "walkthrough",
    chapter: "02 Paper Row",
    from: 520,
    duration: 250,
    asset: "assets/screenshots/library-folder-filter.png",
    accent: COLORS.green,
    title: "论文卡片把 PDF、标签和操作集中到一行",
    body: "搜索、阅读、all levels 和操作按钮组成一条紧凑工具带，阅读入口保持在视线中央。",
    bullets: ["顶部工具条单行展开", "阅读按钮靠近筛选条件", "标签与详情联动"],
    focus: {x: 348, y: 52, w: 1120, h: 45},
    callout: {
      title: "单行控制带",
      body: "搜索、论文数量、层级筛选和主要动作在同一视觉轨道上。",
      side: "bottom",
    },
    captionSide: "left",
    cursor: {from: {x: 1180, y: 190}, to: {x: 1060, y: 70}, clickAt: 86},
    zoom: {scale: 1.2, delay: 18},
  },
  {
    id: "discover-cards",
    kind: "walkthrough",
    chapter: "03 Discover",
    from: 740,
    duration: 260,
    asset: "assets/screenshots/discover.png",
    accent: COLORS.orange,
    title: "arXiv Discover 用卡片呈现高密度信息",
    body: "摘要、标签、PDF 缩略图、保存状态和打开按钮一起出现，筛选后就能进入文库。",
    bullets: ["多列卡片便于快速比较", "摘要与标签同屏判断", "保存状态清晰可见"],
    focus: {x: 365, y: 306, w: 1508, h: 580},
    callout: {
      title: "卡片即研究入口",
      body: "每张卡都保留 PDF 线索、中文摘要、标签和后续动作。",
      side: "top",
    },
    captionSide: "left",
    cursor: {from: {x: 1530, y: 900}, to: {x: 1585, y: 847}, clickAt: 106},
    zoom: {scale: 1.16, delay: 18},
  },
  {
    id: "discover-filters",
    kind: "walkthrough",
    chapter: "04 Filters",
    from: 970,
    duration: 240,
    asset: "assets/screenshots/discover.png",
    accent: COLORS.cyan,
    title: "搜索与处理动作聚合在顶部",
    body: "关键词、类别、日期和 Process Results 同行排列，适合连续浏览和批量判断。",
    bullets: ["时间范围直接可调", "类别和方法筛选并列", "处理动作靠近结果区"],
    focus: {x: 352, y: 83, w: 944, h: 66},
    callout: {
      title: "筛选就是工作流",
      body: "顶部条件聚合后，探索过程保持连续，画面重心稳定。",
      side: "bottom",
    },
    captionSide: "right",
    cursor: {from: {x: 560, y: 230}, to: {x: 1030, y: 131}, clickAt: 88},
    zoom: {scale: 1.24, delay: 16},
  },
  {
    id: "reader-codex",
    kind: "walkthrough",
    chapter: "05 Reader",
    from: 1185,
    duration: 300,
    asset: "assets/screenshots/session-generated-chat.png",
    accent: COLORS.green,
    title: "阅读页把 PDF 和 Codex 放在同一个研究场",
    body: "左侧看原文，右侧直接提问，回答贴着当前论文与页面展开。",
    bullets: ["PDF、页码和缩放同栏控制", "对话/笔记切换保持紧凑", "回答带着当前论文上下文"],
    focus: {x: 992, y: 112, w: 862, h: 744},
    callout: {
      title: "原文旁边直接追问",
      body: "用户的问题、Codex 回答和当前 PDF 页面同屏出现。",
      side: "left",
    },
    captionSide: "left",
    cursor: {from: {x: 1740, y: 1000}, to: {x: 1445, y: 522}, clickAt: 114},
    zoom: {scale: 1.14, delay: 20},
  },
  {
    id: "image-preview",
    kind: "walkthrough",
    chapter: "06 Image",
    from: 1460,
    duration: 300,
    asset: "assets/screenshots/in-app-image-preview.png",
    accent: COLORS.violet,
    title: "生成图像在 app 内直接放大",
    body: "imagegen 结果进入会话工作区，点击后以阅读器式预览查看细节。",
    bullets: ["生成图像归档到 session", "预览层支持放大检查", "论文阅读上下文仍在背后"],
    focus: {x: 984, y: 100, w: 900, h: 950},
    callout: {
      title: "内置大图预览",
      body: "图像作为研究资产保留在软件内部，放大检查路径更顺手。",
      side: "left",
    },
    captionSide: "left",
    cursor: {from: {x: 1712, y: 1002}, to: {x: 1458, y: 560}, clickAt: 110},
    zoom: {scale: 1.08, delay: 18},
  },
  {
    id: "sessions",
    kind: "walkthrough",
    chapter: "07 Sessions",
    from: 1735,
    duration: 250,
    asset: "assets/screenshots/recent-conversations.png",
    accent: COLORS.blue,
    title: "Recent Conversations 让研究过程可回到现场",
    body: "每个 session 关联论文、时间和入口，后续继续讨论有明确起点。",
    bullets: ["会话列表按研究对象组织", "右侧展示关联论文", "Open Session 回到同一现场"],
    focus: {x: 355, y: 94, w: 1080, h: 484},
    callout: {
      title: "研究记录可追踪",
      body: "论文、笔记标题、更新时间和进入按钮共同构成回访路径。",
      side: "right",
    },
    captionSide: "right",
    cursor: {from: {x: 1660, y: 246}, to: {x: 1436, y: 129}, clickAt: 92},
    zoom: {scale: 1.15, delay: 18},
  },
  {
    id: "settings",
    kind: "walkthrough",
    chapter: "08 Settings",
    from: 1948,
    duration: 245,
    asset: "assets/screenshots/settings.png",
    accent: COLORS.red,
    title: "设置页把订阅、排序和 Codex 偏好集中管理",
    body: "arXiv 分类、本地排序、Codex 增强和 prompt 配置都留在同一配置面板。",
    bullets: ["订阅范围一眼可见", "相似类别影响本地排序", "Codex prompt 可直接维护"],
    focus: {x: 740, y: 236, w: 760, h: 515},
    callout: {
      title: "配置直接服务研究流",
      body: "订阅、排序和增强选项连接到文库与发现页表现。",
      side: "left",
    },
    captionSide: "left",
    cursor: {from: {x: 520, y: 205}, to: {x: 1090, y: 562}, clickAt: 100},
    zoom: {scale: 1.13, delay: 20},
  },
  {
    id: "workflow",
    kind: "workflow",
    from: 2148,
    duration: 310,
    title: "最终效果：论文进入持续循环",
    body: "Paper Codex 的核心价值，是把发现、保存、阅读、提问、生成和复盘连成一个稳定的桌面研究系统。",
    steps: [
      {label: "发现", body: "arXiv 卡片筛选候选论文", color: COLORS.orange},
      {label: "保存", body: "进入本地文库和文件夹", color: COLORS.blue},
      {label: "阅读", body: "PDF、页面和标签同步", color: COLORS.green},
      {label: "讨论", body: "Codex 回答贴着论文上下文", color: COLORS.violet},
      {label: "复盘", body: "session、图片和笔记持续留存", color: COLORS.cyan},
    ],
  },
  {
    id: "closing",
    kind: "closing",
    from: 2398,
    duration: 242,
    title: "Paper Codex",
    body: "面向真实研究工作的 macOS 论文工作台。",
    items: ["本地优先", "上下文连续", "AI 过程可检查"],
  },
];

export const walkthroughScenes = scenes.filter((scene): scene is WalkthroughScene => scene.kind === "walkthrough");
