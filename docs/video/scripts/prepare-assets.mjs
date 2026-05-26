import {copyFile, mkdir} from "node:fs/promises";
import {dirname, join} from "node:path";
import {fileURLToPath} from "node:url";

const videoDir = dirname(fileURLToPath(import.meta.url));
const projectDir = join(videoDir, "..");
const repoRoot = join(projectDir, "..", "..");
const publicDir = join(projectDir, "public", "assets");

const assets = [
  {
    from: join(repoRoot, "Sources", "PaperCodexApp", "Resources", "AppIcon.png"),
    to: join(publicDir, "app-icon.png"),
  },
  {
    from: join(repoRoot, "docs", "assets", "screenshots", "library.png"),
    to: join(publicDir, "screenshots", "library.png"),
  },
  {
    from: join(repoRoot, "docs", "assets", "screenshots", "discover.png"),
    to: join(publicDir, "screenshots", "discover.png"),
  },
  {
    from: join(repoRoot, "docs", "assets", "screenshots", "reader-chat.png"),
    to: join(publicDir, "screenshots", "reader-chat.png"),
  },
  {
    from: join(repoRoot, "docs", "assets", "screenshots", "settings.png"),
    to: join(publicDir, "screenshots", "settings.png"),
  },
  {
    from: join(repoRoot, "docs", "assets", "screenshots", "recent-conversations.png"),
    to: join(publicDir, "screenshots", "recent-conversations.png"),
  },
  {
    from: join(repoRoot, "docs", "assets", "screenshots", "generated-output.png"),
    to: join(publicDir, "screenshots", "generated-output.png"),
  },
  {
    from: join(repoRoot, "docs", "assets", "screenshots", "library-folder-filter.png"),
    to: join(publicDir, "screenshots", "library-folder-filter.png"),
  },
  {
    from: join(repoRoot, "docs", "assets", "screenshots", "session-generated-chat.png"),
    to: join(publicDir, "screenshots", "session-generated-chat.png"),
  },
  {
    from: join(repoRoot, "docs", "assets", "screenshots", "in-app-image-preview.png"),
    to: join(publicDir, "screenshots", "in-app-image-preview.png"),
  },
];

await mkdir(join(publicDir, "screenshots"), {recursive: true});

for (const asset of assets) {
  await copyFile(asset.from, asset.to);
}

console.log(`Prepared ${assets.length} Remotion assets.`);
