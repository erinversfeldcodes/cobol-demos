import { test, expect } from "@playwright/test";
import { report, runBatch } from "./batch";

// Records from samples/accounts.dat, in account order.
const THANDI = "10000001THANDI NKOSI                  A000500000+00001245000";
const PIETER = "10000002PIETER VAN DER MERWE          A000000000+00000320050";
const NOMSA = "10000006NOMSA ZULU                    A000000000+00000500000";

test("the site root lands on the form, filled with the sample files", async ({ page }) => {
  await page.goto("/");
  await expect(page).toHaveURL(/\/cgi-bin\/ledger$/);
  const firstRecord = THANDI.replace(/[.*+?^${}()|[\]\\]/g, "\\$&");
  await expect(page.getByLabel("ACCOUNT MASTER")).toHaveValue(new RegExp(`^${firstRecord}\n`));
  await expect(page.getByLabel("TRANSACTIONS")).toHaveValue(/SALARY OCT/);
  await expect(page.getByRole("heading", { name: "CONTROL REPORT" })).toHaveCount(0);
});

test("the sample run balances and reports every output", async ({ page }) => {
  await runBatch(page);

  const control = report(page, "CONTROL REPORT");
  await expect(control).toContainText("LEDGER BALANCED");
  await expect(control).toContainText(/OPENING TOTAL\s+268,400\.50/);
  await expect(control).toContainText(/CLOSING TOTAL\s+272,854\.84/);

  const exceptions = report(page, "EXCEPTIONS");
  await expect(exceptions).toContainText("11 EXCEPTION(S)");
  await expect(exceptions).toContainText("TARGET 10000099 NOT FOUND - IN SUSPENSE");

  const statements = report(page, "STATEMENTS");
  await expect(statements).toContainText(/TRANSFER FROM 10000002\s+LOAN REPAYMENT\s+1,000\.00\s+38,450\.00/);
  await expect(statements).toContainText(/CLOSING BALANCE\s+36,250\.01/);

  await expect(report(page, "NEW MASTER FILE")).toContainText(
    "10000001THANDI NKOSI                  A000500000+00003625001",
  );
});

test("names containing markup are shown as text", async ({ page }) => {
  await runBatch(page);

  await expect(report(page, "STATEMENTS")).toContainText("ACCOUNT 10000007  MOLLY & SONS <TRADING>");
  await expect(page.locator("trading")).toHaveCount(0);
});

test("the submitted files stay in the form after a run", async ({ page }) => {
  const transactions = "1000000620261015D0000001000000000000BONUS";
  await runBatch(page, { accounts: NOMSA, transactions });

  await expect(page.getByLabel("ACCOUNT MASTER")).toHaveValue(`${NOMSA}\n`);
  await expect(page.getByLabel("TRANSACTIONS")).toHaveValue(`${transactions}\n`);
});

test("an edited batch with no problems runs clean", async ({ page }) => {
  await runBatch(page, {
    accounts: NOMSA,
    transactions: "1000000620261015D0000001000000000000BONUS",
  });

  await expect(report(page, "EXCEPTIONS")).toContainText("NO EXCEPTIONS");
  await expect(report(page, "STATEMENTS")).toContainText(/CLOSING BALANCE\s+5,100\.00/);
  await expect(report(page, "NEW MASTER FILE")).toHaveText(
    "10000006NOMSA ZULU                    A000000000+00000510000",
  );
});

test("a master file out of account order aborts the run", async ({ page }) => {
  await runBatch(page, { accounts: `${PIETER}\n${THANDI}` });

  const control = report(page, "CONTROL REPORT");
  await expect(control).toContainText("RUN ABORTED");
  await expect(control).toContainText("MASTER RECORD 2 (ACCOUNT 10000001) IS OUT OF SEQUENCE");
  await expect(page.getByRole("heading", { name: "STATEMENTS" })).toHaveCount(0);
});

test("oversized input is refused before the batch runs", async ({ page }) => {
  await runBatch(page, { transactions: "x".repeat(61_000) });

  await expect(page.locator(".error")).toContainText("Input is too large");
  await expect(page.getByRole("heading", { name: "CONTROL REPORT" })).toHaveCount(0);
});
