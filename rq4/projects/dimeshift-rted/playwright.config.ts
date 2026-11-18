import { defineConfig } from '@playwright/test';

export default defineConfig({
  testDir: './tests',
  timeout: 180_000,
  expect: { timeout: 5_000 },
  fullyParallel: false,
  workers: 1,
  retries: 0,
  use: { viewport: { width: 1200, height: 890 }, actionTimeout: 5_000, navigationTimeout: 30_000 },
});
