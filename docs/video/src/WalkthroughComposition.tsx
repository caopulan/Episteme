import type {CSSProperties} from "react";
import {
  AbsoluteFill,
  Img,
  interpolate,
  spring,
  staticFile,
  useCurrentFrame,
  useVideoConfig,
} from "remotion";
import {
  COLORS,
  FONT,
  VIDEO,
  scenes,
  walkthroughScenes,
  type ClosingScene,
  type ContextScene,
  type IntroScene,
  type Point,
  type Rect,
  type SceneBase,
  type VideoScene,
  type WalkthroughScene,
  type WorkflowScene,
} from "./videoPlan";

const clamp = (value: number, min: number, max: number) => Math.max(min, Math.min(max, value));

const sceneOpacity = (frame: number, scene: SceneBase, fadeFrames = 26) => {
  if (scene.from === 0) {
    return interpolate(frame, [0, scene.duration - fadeFrames, scene.duration], [1, 1, 0], {
      extrapolateLeft: "clamp",
      extrapolateRight: "clamp",
    });
  }

  return interpolate(
    frame,
    [scene.from, scene.from + fadeFrames, scene.from + scene.duration - fadeFrames, scene.from + scene.duration],
    [0, 1, 1, 0],
    {extrapolateLeft: "clamp", extrapolateRight: "clamp"},
  );
};

const localFrame = (frame: number, scene: SceneBase) => frame - scene.from;

const enterOpacity = (frame: number, delay = 0, duration = 22) =>
  interpolate(frame, [delay, delay + duration], [0, 1], {
    extrapolateLeft: "clamp",
    extrapolateRight: "clamp",
  });

const enterY = (frame: number, delay = 0, distance = 28) =>
  interpolate(frame, [delay, delay + 24], [distance, 0], {
    extrapolateLeft: "clamp",
    extrapolateRight: "clamp",
  });

const lerp = (from: number, to: number, progress: number) => from + (to - from) * progress;

const BrandMark = ({compact = false}: {compact?: boolean}) => (
  <div
    style={{
      display: "flex",
      alignItems: "center",
      gap: compact ? 12 : 22,
      color: COLORS.ink,
      fontWeight: 850,
      fontSize: compact ? 23 : 46,
      letterSpacing: 0,
      whiteSpace: "nowrap",
    }}
  >
    <Img
      src={staticFile("assets/app-icon.png")}
      style={{
        width: compact ? 40 : 92,
        height: compact ? 40 : 92,
        borderRadius: compact ? 12 : 26,
        boxShadow: "0 22px 54px rgba(31, 122, 255, 0.24)",
      }}
    />
    <span>Episteme</span>
  </div>
);

const ProgressRail = ({frame}: {frame: number}) => {
  const activeIndex = walkthroughScenes.reduce((current, scene, index) => (frame >= scene.from - 14 ? index : current), 0);
  const totalProgress = interpolate(frame, [0, VIDEO.durationInFrames], [0, 1], {
    extrapolateLeft: "clamp",
    extrapolateRight: "clamp",
  });

  return (
    <div style={{width: 780}}>
      <div
        style={{
          height: 6,
          borderRadius: 999,
          background: "rgba(20, 32, 51, 0.10)",
          overflow: "hidden",
        }}
      >
        <div
          style={{
            width: `${totalProgress * 100}%`,
            height: "100%",
            borderRadius: 999,
            background: `linear-gradient(90deg, ${COLORS.blue}, ${COLORS.green}, ${COLORS.orange})`,
          }}
        />
      </div>
      <div style={{display: "flex", justifyContent: "space-between", marginTop: 12}}>
        {walkthroughScenes.map((step, index) => {
          const active = index === activeIndex;
          const passed = frame >= step.from;
          return (
            <div
              key={step.id}
              style={{
                display: "flex",
                alignItems: "center",
                gap: 7,
                opacity: passed ? 1 : 0.38,
                color: active ? step.accent : COLORS.muted,
                fontSize: 14,
                fontWeight: active ? 850 : 650,
                whiteSpace: "nowrap",
              }}
            >
              <span
                style={{
                  width: active ? 10 : 7,
                  height: active ? 10 : 7,
                  borderRadius: 999,
                  background: active ? step.accent : "rgba(101, 117, 139, 0.40)",
                  boxShadow: active ? `0 0 0 6px ${step.accent}1F` : undefined,
                }}
              />
              {step.chapter.replace(/^\d+\s/, "")}
            </div>
          );
        })}
      </div>
    </div>
  );
};

const TopChrome = ({eyebrow}: {eyebrow: string}) => {
  const frame = useCurrentFrame();
  return (
    <div
      style={{
        position: "absolute",
        left: 54,
        right: 54,
        top: 34,
        height: 66,
        zIndex: 40,
        display: "flex",
        alignItems: "center",
        justifyContent: "space-between",
        padding: "0 22px",
        borderRadius: 24,
        background: "rgba(255, 255, 255, 0.84)",
        border: `1px solid ${COLORS.line}`,
        boxShadow: "0 18px 60px rgba(20, 32, 51, 0.12)",
        backdropFilter: "blur(16px)",
      }}
    >
      <div style={{display: "flex", alignItems: "center", gap: 22}}>
        <BrandMark compact />
        <div style={{fontSize: 19, color: COLORS.muted, fontWeight: 720}}>{eyebrow}</div>
      </div>
      <ProgressRail frame={frame} />
    </div>
  );
};

const Pill = ({label, color, delay}: {label: string; color: string; delay: number}) => {
  const frame = useCurrentFrame();
  return (
    <div
      style={{
        opacity: enterOpacity(frame, delay),
        transform: `translateY(${enterY(frame, delay, 18)}px)`,
        display: "inline-flex",
        alignItems: "center",
        borderRadius: 999,
        padding: "12px 18px",
        border: `1px solid ${color}4D`,
        background: `${color}18`,
        color,
        fontSize: 24,
        fontWeight: 840,
      }}
    >
      {label}
    </div>
  );
};

const Kicker = ({children, color}: {children: string; color: string}) => (
  <div
    style={{
      display: "inline-flex",
      alignItems: "center",
      gap: 10,
      padding: "9px 15px",
      borderRadius: 999,
      color,
      background: `${color}14`,
      border: `1px solid ${color}44`,
      fontSize: 20,
      fontWeight: 850,
      letterSpacing: 0,
    }}
  >
    <span style={{width: 9, height: 9, borderRadius: 999, background: color}} />
    {children}
  </div>
);

const IntroSceneView = ({scene}: {scene: IntroScene}) => {
  const frame = useCurrentFrame();
  const {fps} = useVideoConfig();
  const t = localFrame(frame, scene);
  const iconScale = 0.94 + spring({frame: t, fps, config: {damping: 18, stiffness: 130}}) * 0.06;

  return (
    <AbsoluteFill
      style={{
        opacity: sceneOpacity(frame, scene),
        background: "linear-gradient(135deg, #FFFFFF 0%, #F7FAFF 54%, #F4FBF7 100%)",
        fontFamily: FONT,
        overflow: "hidden",
      }}
    >
      <div
        style={{
          position: "absolute",
          inset: 0,
          background:
            "linear-gradient(90deg, rgba(255,255,255,0.92), rgba(255,255,255,0.62)), repeating-linear-gradient(0deg, rgba(20,32,51,0.035) 0 1px, transparent 1px 44px)",
        }}
      />
      <div style={{position: "absolute", left: 112, top: 120, width: 780}}>
        <div style={{transform: `scale(${iconScale})`, transformOrigin: "left center"}}>
          <BrandMark />
        </div>
        <div
          style={{
            marginTop: 42,
            fontSize: 82,
            lineHeight: 1.05,
            color: COLORS.ink,
            fontWeight: 940,
            letterSpacing: 0,
            opacity: enterOpacity(t, 20),
            transform: `translateY(${enterY(t, 20)}px)`,
          }}
        >
          {scene.title}
        </div>
        <div
          style={{
            marginTop: 28,
            fontSize: 32,
            lineHeight: 1.42,
            color: COLORS.muted,
            fontWeight: 560,
            opacity: enterOpacity(t, 36),
            transform: `translateY(${enterY(t, 36)}px)`,
          }}
        >
          {scene.body}
        </div>
        <div style={{display: "flex", gap: 14, flexWrap: "wrap", marginTop: 40}}>
          {scene.pills.map((pill, index) => (
            <Pill key={pill.label} label={pill.label} color={pill.color} delay={58 + index * 10} />
          ))}
        </div>
      </div>
      <div style={{position: "absolute", right: 90, top: 124, width: 830, height: 820}}>
        {[
          {src: "assets/screenshots/library-folder-filter.png", x: 30, y: 30, rotate: -2, delay: 24},
          {src: "assets/screenshots/discover.png", x: 0, y: 235, rotate: 1.4, delay: 38},
          {src: "assets/screenshots/in-app-image-preview.png", x: 58, y: 438, rotate: -1.1, delay: 52},
        ].map((screen) => (
          <div
            key={screen.src}
            style={{
              position: "absolute",
              left: screen.x,
              top: screen.y,
              width: 760,
              height: 428,
              borderRadius: 26,
              overflow: "hidden",
              background: COLORS.white,
              border: `1px solid ${COLORS.line}`,
              boxShadow: "0 28px 92px rgba(20, 32, 51, 0.18)",
              opacity: enterOpacity(t, screen.delay),
              transform: `translateY(${enterY(t, screen.delay, 40)}px) rotate(${screen.rotate}deg)`,
            }}
          >
            <Img src={staticFile(screen.src)} style={{width: "100%", height: "100%", objectFit: "cover"}} />
          </div>
        ))}
      </div>
    </AbsoluteFill>
  );
};

const ContextCard = ({title, body, color, delay}: {title: string; body: string; color: string; delay: number}) => {
  const frame = useCurrentFrame();
  return (
    <div
      style={{
        opacity: enterOpacity(frame, delay),
        transform: `translateY(${enterY(frame, delay, 26)}px)`,
        borderRadius: 28,
        border: `1px solid ${COLORS.line}`,
        background: COLORS.white,
        padding: 30,
        boxShadow: "0 20px 64px rgba(20, 32, 51, 0.10)",
      }}
    >
      <div style={{width: 50, height: 50, borderRadius: 16, background: `${color}1A`, display: "grid", placeItems: "center"}}>
        <span style={{width: 16, height: 16, borderRadius: 999, background: color}} />
      </div>
      <div style={{fontSize: 32, fontWeight: 880, color: COLORS.ink, marginTop: 24}}>{title}</div>
      <div style={{fontSize: 23, lineHeight: 1.42, color: COLORS.muted, fontWeight: 560, marginTop: 12}}>{body}</div>
    </div>
  );
};

const ContextSceneView = ({scene}: {scene: ContextScene}) => {
  const frame = useCurrentFrame();
  const t = localFrame(frame, scene);
  return (
    <AbsoluteFill
      style={{
        opacity: sceneOpacity(frame, scene),
        background: "linear-gradient(135deg, #F8FBFF 0%, #FFFFFF 46%, #F7FBF4 100%)",
        fontFamily: FONT,
        padding: "72px 92px",
      }}
    >
      <TopChrome eyebrow={scene.eyebrow} />
      <div
        style={{
          marginTop: 140,
          width: 1180,
          opacity: enterOpacity(t, 8),
          transform: `translateY(${enterY(t, 8)}px)`,
        }}
      >
        <div style={{fontSize: 74, lineHeight: 1.05, fontWeight: 940, color: COLORS.ink, letterSpacing: 0}}>{scene.title}</div>
        <div style={{fontSize: 31, lineHeight: 1.42, color: COLORS.muted, marginTop: 26, fontWeight: 560}}>{scene.body}</div>
      </div>
      <div style={{display: "grid", gridTemplateColumns: "repeat(4, 1fr)", gap: 24, marginTop: 70}}>
        {scene.cards.map((card, index) => (
          <ContextCard key={card.title} {...card} delay={scene.from + 48 + index * 12} />
        ))}
      </div>
    </AbsoluteFill>
  );
};

const FocusOverlay = ({target, color, frame}: {target: Rect; color: string; frame: number}) => {
  const alpha = interpolate(frame, [18, 42], [0, 1], {extrapolateLeft: "clamp", extrapolateRight: "clamp"});
  const pulse = interpolate(frame % 58, [0, 29, 58], [0.2, 0.36, 0.2], {
    extrapolateLeft: "clamp",
    extrapolateRight: "clamp",
  });
  const pad = 15;
  const rect = {
    x: target.x - pad,
    y: target.y - pad,
    w: target.w + pad * 2,
    h: target.h + pad * 2,
  };

  return (
    <AbsoluteFill style={{opacity: alpha, pointerEvents: "none"}}>
      <div style={{position: "absolute", left: 0, top: 0, right: 0, height: rect.y, background: "rgba(8, 16, 30, 0.28)"}} />
      <div style={{position: "absolute", left: 0, top: rect.y, width: rect.x, height: rect.h, background: "rgba(8, 16, 30, 0.28)"}} />
      <div
        style={{
          position: "absolute",
          left: rect.x + rect.w,
          top: rect.y,
          right: 0,
          height: rect.h,
          background: "rgba(8, 16, 30, 0.28)",
        }}
      />
      <div
        style={{
          position: "absolute",
          left: 0,
          top: rect.y + rect.h,
          right: 0,
          bottom: 0,
          background: "rgba(8, 16, 30, 0.28)",
        }}
      />
      <div
        style={{
          position: "absolute",
          left: rect.x,
          top: rect.y,
          width: rect.w,
          height: rect.h,
          borderRadius: 24,
          border: `5px solid ${color}`,
          boxShadow: `0 0 0 8px ${color}24, 0 0 82px ${color}${Math.round(pulse * 255)
            .toString(16)
            .padStart(2, "0")}`,
        }}
      />
      <div
        style={{
          position: "absolute",
          left: target.x + target.w / 2 - 10,
          top: target.y + target.h / 2 - 10,
          width: 20,
          height: 20,
          borderRadius: 999,
          background: color,
          boxShadow: `0 0 0 15px ${color}22`,
        }}
      />
    </AbsoluteFill>
  );
};

const cursorPoint = (from: Point, to: Point, frame: number, clickAt: number) => {
  const progress = interpolate(frame, [28, clickAt], [0, 1], {
    extrapolateLeft: "clamp",
    extrapolateRight: "clamp",
  });
  return {x: lerp(from.x, to.x, progress), y: lerp(from.y, to.y, progress)};
};

const AnimatedCursor = ({scene, frame}: {scene: WalkthroughScene; frame: number}) => {
  const point = cursorPoint(scene.cursor.from, scene.cursor.to, frame, scene.cursor.clickAt);
  const clickOpacity = interpolate(frame, [scene.cursor.clickAt, scene.cursor.clickAt + 30], [0.7, 0], {
    extrapolateLeft: "clamp",
    extrapolateRight: "clamp",
  });
  const clickScale = interpolate(frame, [scene.cursor.clickAt, scene.cursor.clickAt + 30], [0.3, 2.8], {
    extrapolateLeft: "clamp",
    extrapolateRight: "clamp",
  });

  return (
    <>
      <div
        style={{
          position: "absolute",
          left: scene.cursor.to.x - 24,
          top: scene.cursor.to.y - 24,
          width: 48,
          height: 48,
          borderRadius: 999,
          border: `4px solid ${scene.accent}`,
          opacity: clickOpacity,
          transform: `scale(${clickScale})`,
          boxShadow: `0 0 34px ${scene.accent}66`,
        }}
      />
      <div
        style={{
          position: "absolute",
          left: point.x,
          top: point.y,
          opacity: enterOpacity(frame, 18),
          transform: "translate(-3px, -3px) rotate(-10deg)",
          filter: "drop-shadow(0 12px 24px rgba(20, 32, 51, 0.30))",
        }}
      >
        <div
          style={{
            width: 34,
            height: 44,
            background: COLORS.white,
            clipPath: "polygon(0 0, 0 38px, 11px 29px, 19px 44px, 27px 40px, 19px 25px, 34px 25px)",
            border: `2px solid ${COLORS.ink}`,
          }}
        />
      </div>
    </>
  );
};

const calloutPosition = (target: Rect, side: WalkthroughScene["callout"]["side"]) => {
  const width = 452;
  const height = 164;
  const left =
    side === "left"
      ? clamp(target.x - width - 58, 72, VIDEO.width - width - 72)
      : side === "right"
        ? clamp(target.x + target.w + 58, 72, VIDEO.width - width - 72)
        : clamp(target.x + target.w / 2 - width / 2, 72, VIDEO.width - width - 72);
  const top =
    side === "top"
      ? clamp(target.y - height - 46, 122, VIDEO.height - height - 76)
      : side === "bottom"
        ? clamp(target.y + target.h + 40, 122, VIDEO.height - height - 76)
        : clamp(target.y + target.h / 2 - height / 2, 122, VIDEO.height - height - 76);
  return {left, top, width, height};
};

const connectorPoints = (target: Rect, box: {left: number; top: number; width: number; height: number}, side: WalkthroughScene["callout"]["side"]) => {
  const anchor = {x: target.x + target.w / 2, y: target.y + target.h / 2};
  const start =
    side === "left"
      ? {x: box.left + box.width, y: box.top + box.height / 2}
      : side === "right"
        ? {x: box.left, y: box.top + box.height / 2}
        : side === "top"
          ? {x: box.left + box.width / 2, y: box.top + box.height}
          : {x: box.left + box.width / 2, y: box.top};
  return {start, anchor};
};

const FocusCallout = ({scene, frame}: {scene: WalkthroughScene; frame: number}) => {
  const box = calloutPosition(scene.focus, scene.callout.side);
  const points = connectorPoints(scene.focus, box, scene.callout.side);
  const dx = points.anchor.x - points.start.x;
  const dy = points.anchor.y - points.start.y;
  const length = Math.sqrt(dx * dx + dy * dy);
  const angle = Math.atan2(dy, dx);

  return (
    <>
      <div
        style={{
          position: "absolute",
          left: points.start.x,
          top: points.start.y,
          width: length,
          height: 3,
          borderRadius: 999,
          background: `linear-gradient(90deg, ${scene.accent}, ${scene.accent}55)`,
          transform: `rotate(${angle}rad) scaleX(${enterOpacity(frame, 42)})`,
          transformOrigin: "0 50%",
          opacity: enterOpacity(frame, 38),
          zIndex: 18,
        }}
      />
      <div
        style={{
          position: "absolute",
          left: box.left,
          top: box.top,
          width: box.width,
          minHeight: box.height,
          padding: "22px 25px",
          borderRadius: 24,
          background: "rgba(255, 255, 255, 0.94)",
          border: `1px solid ${scene.accent}44`,
          boxShadow: "0 24px 80px rgba(20, 32, 51, 0.20)",
          opacity: enterOpacity(frame, 40),
          transform: `translateY(${enterY(frame, 40, 20)}px)`,
          zIndex: 20,
        }}
      >
        <div style={{display: "flex", alignItems: "center", gap: 12}}>
          <span style={{width: 12, height: 12, borderRadius: 999, background: scene.accent}} />
          <div style={{fontSize: 24, fontWeight: 900, color: scene.accent}}>{scene.callout.title}</div>
        </div>
        <div style={{fontSize: 22, lineHeight: 1.38, color: COLORS.ink, fontWeight: 680, marginTop: 12}}>{scene.callout.body}</div>
      </div>
    </>
  );
};

const CaptionPanel = ({scene, frame}: {scene: WalkthroughScene; frame: number}) => {
  const placement: CSSProperties = scene.captionSide === "left" ? {left: 70} : {right: 70};
  return (
    <div
      style={{
        position: "absolute",
        bottom: 58,
        width: 705,
        padding: "26px 30px",
        borderRadius: 28,
        background: "rgba(246, 248, 251, 0.92)",
        border: `1px solid ${COLORS.line}`,
        boxShadow: "0 24px 84px rgba(20, 32, 51, 0.16)",
        opacity: enterOpacity(frame, 26),
        transform: `translateY(${enterY(frame, 26, 24)}px)`,
        zIndex: 22,
        ...placement,
      }}
    >
      <Kicker color={scene.accent}>{scene.chapter}</Kicker>
      <div style={{fontSize: 48, lineHeight: 1.08, fontWeight: 930, color: COLORS.ink, marginTop: 16, letterSpacing: 0}}>
        {scene.title}
      </div>
      <div style={{fontSize: 24, lineHeight: 1.42, color: COLORS.muted, fontWeight: 560, marginTop: 16}}>{scene.body}</div>
      <div style={{display: "grid", gap: 11, marginTop: 20}}>
        {scene.bullets.map((bullet, index) => (
          <div
            key={bullet}
            style={{
              display: "flex",
              alignItems: "center",
              gap: 12,
              opacity: enterOpacity(frame, 54 + index * 9),
              transform: `translateY(${enterY(frame, 54 + index * 9, 12)}px)`,
              fontSize: 22,
              color: COLORS.ink,
              fontWeight: 720,
            }}
          >
            <span
              style={{
                width: 24,
                height: 24,
                borderRadius: 8,
                background: `${scene.accent}1F`,
                border: `1px solid ${scene.accent}55`,
                color: scene.accent,
                display: "grid",
                placeItems: "center",
                fontSize: 15,
                fontWeight: 900,
              }}
            >
              {index + 1}
            </span>
            {bullet}
          </div>
        ))}
      </div>
    </div>
  );
};

const WalkthroughSceneView = ({scene}: {scene: WalkthroughScene}) => {
  const frame = useCurrentFrame();
  const {fps} = useVideoConfig();
  const t = localFrame(frame, scene);
  const focusProgress = spring({frame: t - scene.zoom.delay, fps, config: {damping: 22, stiffness: 78}});
  const exitRelax = interpolate(t, [scene.duration - 72, scene.duration], [0, 1], {
    extrapolateLeft: "clamp",
    extrapolateRight: "clamp",
  });
  const scale = 1 + (scene.zoom.scale - 1) * focusProgress - exitRelax * 0.035;
  const originX = scene.focus.x + scene.focus.w / 2;
  const originY = scene.focus.y + scene.focus.h / 2;

  return (
    <AbsoluteFill
      style={{
        opacity: sceneOpacity(frame, scene),
        background: COLORS.soft,
        fontFamily: FONT,
        overflow: "hidden",
      }}
    >
      <AbsoluteFill
        style={{
          transformOrigin: `${originX}px ${originY}px`,
          transform: `scale(${scale})`,
          filter: "saturate(1.04)",
        }}
      >
        <Img src={staticFile(scene.asset)} style={{width: "100%", height: "100%", objectFit: "cover"}} />
        <FocusOverlay target={scene.focus} color={scene.accent} frame={t} />
        <AnimatedCursor scene={scene} frame={t} />
      </AbsoluteFill>
      <TopChrome eyebrow="animated walkthrough from real app captures" />
      <FocusCallout scene={scene} frame={t} />
      <CaptionPanel scene={scene} frame={t} />
    </AbsoluteFill>
  );
};

const WorkflowSceneView = ({scene}: {scene: WorkflowScene}) => {
  const frame = useCurrentFrame();
  const t = localFrame(frame, scene);
  return (
    <AbsoluteFill
      style={{
        opacity: sceneOpacity(frame, scene),
        background: "linear-gradient(135deg, #FFFFFF 0%, #F8FBFF 52%, #F7FBF4 100%)",
        fontFamily: FONT,
        overflow: "hidden",
      }}
    >
      <TopChrome eyebrow="complete research loop" />
      <div style={{position: "absolute", left: 110, top: 148, width: 880}}>
        <Kicker color={COLORS.green}>research loop</Kicker>
        <div
          style={{
            fontSize: 70,
            lineHeight: 1.06,
            color: COLORS.ink,
            fontWeight: 940,
            letterSpacing: 0,
            marginTop: 22,
            opacity: enterOpacity(t, 8),
            transform: `translateY(${enterY(t, 8)}px)`,
          }}
        >
          {scene.title}
        </div>
        <div
          style={{
            fontSize: 30,
            lineHeight: 1.42,
            color: COLORS.muted,
            fontWeight: 560,
            marginTop: 24,
            opacity: enterOpacity(t, 22),
            transform: `translateY(${enterY(t, 22)}px)`,
          }}
        >
          {scene.body}
        </div>
      </div>
      <div style={{position: "absolute", left: 120, right: 120, bottom: 132, height: 360}}>
        <div
          style={{
            position: "absolute",
            left: 76,
            right: 76,
            top: 166,
            height: 5,
            borderRadius: 999,
            background: "rgba(20, 32, 51, 0.12)",
          }}
        />
        {scene.steps.map((step, index) => {
          const delay = 48 + index * 24;
          const left = index * 338;
          return (
            <div
              key={step.label}
              style={{
                position: "absolute",
                left,
                top: index % 2 === 0 ? 28 : 74,
                width: 300,
                opacity: enterOpacity(t, delay),
                transform: `translateY(${enterY(t, delay, 30)}px)`,
              }}
            >
              <div
                style={{
                  width: 108,
                  height: 108,
                  borderRadius: 34,
                  display: "grid",
                  placeItems: "center",
                  background: `${step.color}18`,
                  border: `2px solid ${step.color}4D`,
                  boxShadow: `0 20px 58px ${step.color}20`,
                  margin: "0 auto",
                  color: step.color,
                  fontSize: 34,
                  fontWeight: 930,
                }}
              >
                {index + 1}
              </div>
              <div style={{textAlign: "center", fontSize: 32, fontWeight: 900, color: COLORS.ink, marginTop: 18}}>{step.label}</div>
              <div style={{textAlign: "center", fontSize: 21, lineHeight: 1.36, fontWeight: 600, color: COLORS.muted, marginTop: 8}}>
                {step.body}
              </div>
            </div>
          );
        })}
      </div>
      <div
        style={{
          position: "absolute",
          right: 102,
          top: 150,
          width: 610,
          height: 342,
          borderRadius: 28,
          overflow: "hidden",
          border: `1px solid ${COLORS.line}`,
          boxShadow: "0 28px 90px rgba(20, 32, 51, 0.16)",
          opacity: enterOpacity(t, 44),
          transform: `translateY(${enterY(t, 44, 34)}px)`,
        }}
      >
        <Img src={staticFile("assets/screenshots/session-generated-chat.png")} style={{width: "100%", height: "100%", objectFit: "cover"}} />
      </div>
    </AbsoluteFill>
  );
};

const ClosingSceneView = ({scene}: {scene: ClosingScene}) => {
  const frame = useCurrentFrame();
  const {fps} = useVideoConfig();
  const t = localFrame(frame, scene);
  const scale = spring({frame: t - 6, fps, config: {damping: 16, stiffness: 110}});

  return (
    <AbsoluteFill
      style={{
        opacity: sceneOpacity(frame, scene, 30),
        background: "linear-gradient(135deg, #F7FAFF 0%, #FFFFFF 52%, #F4FBF7 100%)",
        fontFamily: FONT,
        display: "grid",
        placeItems: "center",
        textAlign: "center",
      }}
    >
      <div style={{transform: `scale(${scale})`, opacity: enterOpacity(t, 8)}}>
        <Img
          src={staticFile("assets/app-icon.png")}
          style={{
            width: 168,
            height: 168,
            borderRadius: 42,
            boxShadow: "0 34px 86px rgba(31, 122, 255, 0.26)",
          }}
        />
        <div style={{fontSize: 84, fontWeight: 950, color: COLORS.ink, letterSpacing: 0, marginTop: 34}}>{scene.title}</div>
        <div style={{fontSize: 32, lineHeight: 1.42, color: COLORS.muted, fontWeight: 560, marginTop: 18}}>{scene.body}</div>
        <div style={{display: "flex", justifyContent: "center", gap: 16, marginTop: 34}}>
          {scene.items.map((item, index) => (
            <div
              key={item}
              style={{
                opacity: enterOpacity(t, 54 + index * 10),
                transform: `translateY(${enterY(t, 54 + index * 10, 16)}px)`,
                padding: "13px 18px",
                borderRadius: 999,
                border: `1px solid ${COLORS.line}`,
                background: COLORS.white,
                color: COLORS.ink,
                fontSize: 24,
                fontWeight: 760,
                boxShadow: "0 16px 44px rgba(20, 32, 51, 0.10)",
              }}
            >
              {item}
            </div>
          ))}
        </div>
      </div>
    </AbsoluteFill>
  );
};

const SceneRenderer = ({scene}: {scene: VideoScene}) => {
  if (scene.kind === "intro") {
    return <IntroSceneView scene={scene} />;
  }
  if (scene.kind === "context") {
    return <ContextSceneView scene={scene} />;
  }
  if (scene.kind === "walkthrough") {
    return <WalkthroughSceneView scene={scene} />;
  }
  if (scene.kind === "workflow") {
    return <WorkflowSceneView scene={scene} />;
  }
  return <ClosingSceneView scene={scene} />;
};

export const EpistemeIntro = () => (
  <AbsoluteFill style={{background: COLORS.soft}}>
    {scenes.map((scene) => (
      <SceneRenderer key={scene.id} scene={scene} />
    ))}
  </AbsoluteFill>
);
