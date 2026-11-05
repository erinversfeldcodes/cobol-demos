import { Page } from "@playwright/test";

export function report(page: Page, heading: string) {
  return page.locator(`h2:text-is("${heading}") + pre`);
}

export async function runBatch(page: Page, inputs: { accounts?: string; transactions?: string } = {}) {
  await page.goto("/");
  if (inputs.accounts !== undefined) {
    await page.getByLabel("ACCOUNT MASTER").fill(inputs.accounts);
  }
  if (inputs.transactions !== undefined) {
    await page.getByLabel("TRANSACTIONS").fill(inputs.transactions);
  }
  await page.getByRole("button", { name: "RUN BATCH" }).click();
}
