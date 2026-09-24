import { defineConfig } from 'vitest/config';
import { execSync } from 'node:child_process';
import { readFileSync } from 'node:fs';
import { fileURLToPath, URL } from 'node:url';

const pkg = JSON.parse(readFileSync(new URL('./package.json', import.meta.url), 'utf8')) as {
  version: string;
};

/** The commit being built: the Actions variable on a deploy, else git, else unknown. */
function buildCommit(): string {
  if (process.env.GITHUB_SHA) return process.env.GITHUB_SHA.slice(0, 7);
  try {
    return execSync('git rev-parse --short=7 HEAD', { stdio: ['ignore', 'pipe', 'ignore'] })
      .toString()
      .trim();
  } catch {
    return '';
  }
}

export default defineConfig({
  /*
   * Relative asset paths, so the same build works at the GitHub Pages project
   * subpath (/dark-fantasy-management/) and at a domain root without a rebuild.
   */
  base: './',
  // Which build this is, for the version line on the main menu and in Settings.
  define: {
    __APP_VERSION__: JSON.stringify(pkg.version),
    __APP_COMMIT__: JSON.stringify(buildCommit()),
    __BUILD_DATE__: JSON.stringify(new Date().toISOString().slice(0, 10)),
  },
  resolve: {
    alias: {
      '@': fileURLToPath(new URL('./src', import.meta.url)),
    },
  },
  build: {
    target: 'es2022',
    // Phaser alone is well over the 500 kB default, and it sits in its own
    // long-cached chunk, so the warning says nothing actionable here.
    chunkSizeWarningLimit: 2000,
    rollupOptions: {
      output: {
        manualChunks: { phaser: ['phaser'] },
      },
    },
  },
  server: {
    port: 5173,
    host: true,
  },
  test: {
    environment: 'node',
    include: ['tests/**/*.test.ts'],
  },
});
