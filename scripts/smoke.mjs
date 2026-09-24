/**
 * Browser smoke test: serve the production build, start a game, open a zone.
 *
 * The unit suite never boots Phaser or the DOM shell, so this is what catches
 * a build that type-checks but throws on load, a missing asset, or a map that
 * no longer answers a tap. Fails on any page error or console error.
 *
 * Run `npm run build` first. Chromium comes from `npx playwright-core install
 * chromium`, or from CHROMIUM_PATH when a browser is already on the machine.
 */

import { chromium } from 'playwright-core';
import { preview } from 'vite';

const server = await preview({ preview: { port: 4174, strictPort: true }, logLevel: 'warn' });
const url = server.resolvedUrls?.local[0] ?? 'http://localhost:4174/';
const browser = await chromium.launch({ executablePath: process.env.CHROMIUM_PATH || undefined });
const errors = [];

try {
  const page = await browser.newPage({ viewport: { width: 1280, height: 800 } });
  page.on('pageerror', (error) => errors.push(`page error: ${error.message}`));
  // Only the game's own files count: the web fonts are a nicety, and may be
  // unreachable from a sandboxed runner.
  const ours = (target) => target.startsWith(url);
  page.on('console', (message) => {
    if (message.type() !== 'error' || message.text().startsWith('Failed to load resource')) return;
    errors.push(`console error: ${message.text()}`);
  });
  page.on('requestfailed', (request) => {
    if (ours(request.url())) errors.push(`request failed: ${request.url()}`);
  });
  page.on('response', (response) => {
    if (response.status() >= 400 && ours(response.url()))
      errors.push(`HTTP ${response.status()}: ${response.url()}`);
  });

  await page.goto(url);
  await page.getByRole('button', { name: 'Credits' }).click();
  await page.getByText('game-icons.net').first().waitFor();
  await page.getByRole('button', { name: 'Back', exact: true }).click();
  await page.getByRole('button', { name: 'New Game' }).click();
  const canvas = page.locator('#stage canvas');
  await canvas.waitFor();
  // Let Phaser boot, load the icons and paint the terrain.
  await page.waitForTimeout(2000);

  // Tap the zone east of home. The map opens centred on home, five zones across.
  const box = await canvas.boundingBox();
  if (!box) throw new Error('the map canvas has no size');
  const step = 117;
  const zoom = Math.min(Math.max(Math.min(box.width, box.height) / (step * 5), 0.25), 1);
  await page.mouse.click(box.x + box.width / 2 + step * zoom, box.y + box.height / 2);
  await page.getByRole('button', { name: 'Begin Clearing' }).waitFor({ timeout: 5000 });

  for (const screen of ['Settlements', 'Heroes', 'Inventory', 'Log', 'Saves', 'World']) {
    await page.locator('nav .nav-item', { hasText: screen }).click();
    await page.waitForTimeout(150);
  }
} catch (error) {
  errors.push(error instanceof Error ? error.message : String(error));
} finally {
  await browser.close();
  await new Promise((resolve) => server.httpServer.close(resolve));
}

if (errors.length > 0) {
  console.error(`Smoke test failed:\n${errors.map((e) => `  ${e}`).join('\n')}`);
  process.exit(1);
}
console.log('Smoke test passed.');
