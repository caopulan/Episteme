import {Composition} from "remotion";
import {EpistemeIntro} from "./IntroVideo";
import {VIDEO} from "./videoPlan";

export const RemotionRoot = () => {
  return (
    <Composition
      id="EpistemeIntro"
      component={EpistemeIntro}
      durationInFrames={VIDEO.durationInFrames}
      fps={VIDEO.fps}
      width={VIDEO.width}
      height={VIDEO.height}
    />
  );
};
