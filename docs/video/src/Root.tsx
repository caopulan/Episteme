import {Composition} from "remotion";
import {PaperCodexIntro} from "./IntroVideo";
import {VIDEO} from "./videoPlan";

export const RemotionRoot = () => {
  return (
    <Composition
      id="PaperCodexIntro"
      component={PaperCodexIntro}
      durationInFrames={VIDEO.durationInFrames}
      fps={VIDEO.fps}
      width={VIDEO.width}
      height={VIDEO.height}
    />
  );
};
