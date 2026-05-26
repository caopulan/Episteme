# Paper Codex Remotion Video

This folder contains the Remotion source for the Paper Codex introduction video. The current composition is an 88-second, config-driven product walkthrough built from real app screenshots, generated-image output, in-app preview captures, animated cursor motion, focus zoom targets, callouts, and a chapter progress rail.

The production structure follows the same workflow used by walkthrough-video and Remotion production skills:

- gather consistent app captures
- define a screen manifest with timing, asset paths, zoom targets, callouts, and cursor paths
- render each screen through reusable Remotion components
- preview still frames and contact sheets before committing the final MP4

Key files:

```text
src/videoPlan.ts              # video spec, scene plan, screen manifest
src/WalkthroughComposition.tsx # reusable Remotion scenes and focus effects
src/Root.tsx                  # Remotion composition metadata
scripts/prepare-assets.mjs    # copies tracked screenshots into public/assets
```

Render the video from this folder:

```bash
npm install
npm run render
```

The render script copies the current app icon and documentation screenshots into the local Remotion `public/` folder, then writes:

```text
../assets/videos/paper-codex-intro.mp4
```

The generated `public/` directory is intentionally ignored because it only mirrors assets already tracked elsewhere in the repository.
