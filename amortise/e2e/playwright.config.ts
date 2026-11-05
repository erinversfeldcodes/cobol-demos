import { defineConfig, devices } from "@playwright/test";

export default defineConfig({
  testDir: "./tests",
  fullyParallel: true,
  workers: process.env.CI ? 2 : 4,
  retries: process.env.CI ? 1 : 0,
  reporter: process.env.CI ? "github" : "list",
  use: {
    baseURL: process.env.BASE_URL ?? "http://127.0.0.1:8080",
    trace: "retain-on-failure",
  },
  // The API and MCP suites make HTTP and stdio calls, so they run once
  // rather than once per browser.
  projects: [
    { name: "chromium", use: { ...devices["Desktop Chrome"] }, testIgnore: /(api|mcp)\.spec\.ts/ },
    { name: "mobile", use: { ...devices["Pixel 7"] }, testIgnore: /(api|mcp)\.spec\.ts/ },
    { name: "api", use: { ...devices["Desktop Chrome"] }, testMatch: /(api|mcp)\.spec\.ts/ },
  ],
});
