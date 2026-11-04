import { test, expect, Page } from "@playwright/test";

function summary(page: Page, term: string) {
  return page.locator(`dt:text-is("${term}") + dd`);
}

async function calculate(page: Page, principal: string, rate: string, term: string) {
  await page.goto("/");
  await page.getByLabel("PRINCIPAL").fill(principal);
  await page.getByLabel("ANNUAL RATE %").fill(rate);
  await page.getByLabel("TERM (MONTHS)").fill(term);
  await page.getByRole("button", { name: "CALCULATE" }).click();
}

test("the site root lands on the empty calculator", async ({ page }) => {
  await page.goto("/");
  await expect(page).toHaveURL(/\/cgi-bin\/amortise$/);
  await expect(page.getByRole("heading", { name: "LOAN AMORTISATION" })).toBeVisible();
  await expect(page.getByLabel("PRINCIPAL")).toHaveValue("");
  await expect(page.getByRole("table")).toHaveCount(0);
});

test("a 20-year loan produces the full schedule and closes at zero", async ({ page }) => {
  await calculate(page, "250000", "11.75", "240");

  await expect(summary(page, "Monthly payment")).toHaveText("2,709.27");
  await expect(summary(page, "Total interest")).toHaveText("400,222.31");
  await expect(summary(page, "Total repaid")).toHaveText("650,222.31");

  const rows = page.locator("tbody tr");
  await expect(rows).toHaveCount(240);
  await expect(rows.first().locator("td")).toHaveText(["1", "2,709.27", "2,447.92", "261.35", "249,738.65"]);
  // The final payment absorbs the rounding left over from the other 239.
  await expect(rows.last().locator("td")).toHaveText(["240", "2,706.78", "26.25", "2,680.53", "0.00"]);
});

test("submitted values stay in the form for the next calculation", async ({ page }) => {
  await calculate(page, "1000", "12", "3");

  await expect(page.getByLabel("PRINCIPAL")).toHaveValue("1000");
  await expect(page.getByLabel("ANNUAL RATE %")).toHaveValue("12");
  await expect(page.getByLabel("TERM (MONTHS)")).toHaveValue("3");
  await expect(page.locator("tbody tr")).toHaveCount(3);
});

test("an invalid term shows a validation message and no schedule", async ({ page }) => {
  await calculate(page, "1000", "12", "601");

  await expect(page.locator(".error")).toHaveText("Term must be a whole number of months from 1 to 600");
  await expect(page.getByRole("table")).toHaveCount(0);
});

test("markup typed into a field is neither run nor echoed back", async ({ page }) => {
  page.on("dialog", (dialog) => {
    throw new Error(`unexpected dialog: ${dialog.message()}`);
  });
  await page.goto("/cgi-bin/amortise?principal=%22%3E%3Cscript%3Ealert(1)%3C%2Fscript%3E&rate=12&term=3");

  await expect(page.locator(".error")).toContainText("Principal must be an amount");
  await expect(page.getByLabel("PRINCIPAL")).toHaveValue("");
  await expect(page.locator("script")).toHaveCount(0);
});

test("a long schedule scrolls inside its container, not the page", async ({ page }) => {
  await calculate(page, "999999999.99", "100", "600");

  await expect(page.locator("tbody tr")).toHaveCount(600);
  const overflow = await page.evaluate(
    () => document.documentElement.scrollWidth - document.documentElement.clientWidth,
  );
  expect(overflow).toBeLessThanOrEqual(0);
});
