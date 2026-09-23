import { defineConfig } from 'vitest/config';
import { fileURLToPath, URL } from 'node:url';

export default defineConfig({
  /*
   * Relative asset paths, so the same build works at the GitHub Pages project
   * subpath (/dark-fantasy-management/) and at a domain root without a rebuild.
   */
  base: './',
  resolve: {
    alias: {
      '@': fileURLToPath(new URL('./src', import.meta.url)),
      /*
       * The game content lives in the repository's top-level `data/` folder,
       * shared with the Godot project. Importing it from there rather than
       * copying it keeps one set of numbers for both builds.
       */
      '@data': fileURLToPath(new URL('../data', import.meta.url)),
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
    // `@data` resolves outside this folder; the dev server has to be allowed there.
    fs: { allow: ['..'] },
  },
  test: {
    environment: 'node',
    include: ['tests/**/*.test.ts'],
  },
});
