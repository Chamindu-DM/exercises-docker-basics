// Drives a real browser to load the given page and confirms some expected
// text is visible on it, instead of curling the raw HTML (which, for a
// client-side rendered React app, is just an empty shell before its JS
// bundle runs).
//
// Usage: node check-page-text.mjs <app-url> "<expected text>"

import { chromium } from "playwright";

async function main() {
  const [url, text] = process.argv.slice(2);
  if (!url || !text) {
    throw new Error('usage: node check-page-text.mjs <app-url> "<expected text>"');
  }

  const browser = await chromium.launch();
  try {
    const page = await browser.newPage();
    await page.goto(url, { waitUntil: "domcontentloaded" });
    await page.getByText(text).first().waitFor({ timeout: 30000 });
    console.log(`PASS: page contains the text "${text}"`);
  } finally {
    await browser.close();
  }
}

main().catch((error) => {
  console.error(`FAIL: ${error.message}`);
  process.exit(1);
});
