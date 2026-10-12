// Renders ui/install/background.html to Resources/dmg/background.png (660 x 400) and background@2x.png (1320 x 800), the picture
// behind the icons in Perch.dmg (scripts/make-dmg.sh joins them into one hi-dpi image). Run after changing the page:
//   node scripts/render-dmg-background.mjs        (needs playwright and its Chromium; any machine will do, fonts come from ui/dist)
import { chromium } from 'playwright';
import { fileURLToPath } from 'node:url';
import { mkdirSync } from 'node:fs';
const root = fileURLToPath(new URL('..', import.meta.url));
const out = root + 'Resources/dmg/';
mkdirSync(out, { recursive: true });
const browser = await chromium.launch({ executablePath: process.env.PERCH_CHROMIUM || undefined });
for (const [scale, name] of [[1, 'background.png'], [2, 'background@2x.png']]) {
  const page = await browser.newPage({ viewport: { width: 660, height: 400 }, deviceScaleFactor: scale });
  await page.goto('file://' + root + 'ui/install/background.html');
  await page.evaluate(() => document.fonts.ready);
  await page.screenshot({ path: out + name });
  await page.close();
}
await browser.close();
console.log('Wrote ' + out + 'background.png and background@2x.png');
