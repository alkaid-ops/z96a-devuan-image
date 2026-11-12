#!/usr/bin/env node
// Render the Alkaid boot SVG to PNG frames with Chromium (SMIL supported).
// Usage: node render-svg-frames.js <svg> <outdir> <fps> <seconds> [scale]
const fs = require('fs');
const path = require('path');
const { chromium } = require('playwright');

(async () => {
  const svgPath = path.resolve(process.argv[2]);
  const outDir = path.resolve(process.argv[3]);
  const fps = Number(process.argv[4] || 10);
  const seconds = Number(process.argv[5] || 6);
  const scale = Number(process.argv[6] || 1);

  const svg = fs.readFileSync(svgPath, 'utf8');
  const W = 1920, H = 1080;
  fs.mkdirSync(outDir, { recursive: true });

  const browser = await chromium.launch({
    executablePath: process.env.PW_CHROME ||
      path.join(process.env.HOME, '.cache/ms-playwright/chromium-1243/chrome-linux64/chrome'),
    args: ['--no-sandbox', '--disable-gpu', '--force-device-scale-factor=1'],
  });
  const page = await browser.newPage({
    viewport: { width: W, height: H },
    deviceScaleFactor: 1,
  });

  const html = `<!doctype html><html><head><meta charset="utf-8">
<style>html,body{margin:0;padding:0;background:#000;overflow:hidden}
svg{display:block;width:${W}px;height:${H}px}</style></head>
<body>${svg}</body></html>`;

  await page.setContent(html, { waitUntil: 'load' });
  await page.waitForTimeout(500);
  await page.evaluate(() => document.fonts && document.fonts.ready);

  const total = Math.round(fps * seconds);
  for (let i = 0; i < total; i++) {
    const t = i / fps;
    await page.evaluate((time) => {
      const s = document.querySelector('svg');
      if (s.pauseAnimations) s.pauseAnimations();
      if (s.setCurrentTime) s.setCurrentTime(time);
    }, t);
    await page.waitForTimeout(60);
    const file = path.join(outDir, `frame_${String(i).padStart(4, '0')}.png`);
    await page.screenshot({ path: file, clip: { x: 0, y: 0, width: W * scale, height: H * scale }, type: 'png' });
    if (i % 10 === 0) process.stdout.write(`.`);
  }
  // final hold frame at the end of the intro
  await page.evaluate((time) => {
    const s = document.querySelector('svg');
    s.pauseAnimations(); s.setCurrentTime(time);
  }, seconds);
  await page.waitForTimeout(80);
  const holdFile = path.join(outDir, `frame_${String(total).padStart(4, '0')}.png`);
  await page.screenshot({ path: holdFile, clip: { x: 0, y: 0, width: W * scale, height: H * scale }, type: 'png' });

  await browser.close();
  console.log(`\nframes: ${total + 1} at ${fps} fps, ${seconds}s -> ${outDir}`);
})().catch((e) => { console.error(e); process.exit(1); });
