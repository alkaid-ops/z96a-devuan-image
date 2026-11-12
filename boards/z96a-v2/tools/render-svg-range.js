#!/usr/bin/env node
// Render a time range of the SMIL SVG to PNG frames.
// Usage: node render-svg-range.js <svg> <outdir> <fps> <startSec> <endSec>
const fs = require('fs');
const path = require('path');
const { chromium } = require('playwright');

(async () => {
  const svgPath = path.resolve(process.argv[2]);
  const outDir = path.resolve(process.argv[3]);
  const fps = Number(process.argv[4] || 10);
  const start = Number(process.argv[5] || 6);
  const end = Number(process.argv[6] || 12);
  const W = 1920, H = 1080;

  const svg = fs.readFileSync(svgPath, 'utf8');
  fs.mkdirSync(outDir, { recursive: true });

  const browser = await chromium.launch({
    executablePath: process.env.PW_CHROME ||
      path.join(process.env.HOME, '.cache/ms-playwright/chromium-1243/chrome-linux64/chrome'),
    args: ['--no-sandbox', '--disable-gpu', '--force-device-scale-factor=1'],
  });
  const page = await browser.newPage({ viewport: { width: W, height: H }, deviceScaleFactor: 1 });
  const html = `<!doctype html><html><head><meta charset="utf-8">
<style>html,body{margin:0;padding:0;background:#000;overflow:hidden}
svg{display:block;width:${W}px;height:${H}px}</style></head><body>${svg}</body></html>`;
  await page.setContent(html, { waitUntil: 'load' });
  await page.waitForTimeout(400);
  await page.evaluate(() => document.fonts && document.fonts.ready);

  const step = 1 / fps;
  let n = 0;
  for (let t = start; t <= end + 1e-6; t += step) {
    await page.evaluate((time) => {
      const s = document.querySelector('svg');
      s.pauseAnimations(); s.setCurrentTime(time);
    }, t);
    await page.waitForTimeout(60);
    await page.screenshot({
      path: path.join(outDir, `frame_${String(n).padStart(4, '0')}.png`),
      clip: { x: 0, y: 0, width: W, height: H }, type: 'png',
    });
    n++;
  }
  await browser.close();
  console.log(`${n} frames ${start}-${end}s @ ${fps}fps -> ${outDir}`);
})().catch((e) => { console.error(e); process.exit(1); });
