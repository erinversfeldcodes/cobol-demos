import { test, expect, Page } from "@playwright/test";
import Ajv2020 from "ajv/dist/2020";
import addFormats from "ajv-formats";
import schema from "../../schema/events.schema.json";
import { report, runBatch } from "./batch";

const TYPE = "io.github.erinversfeldcodes.cobol-demos.ledger.";

const ajv = new Ajv2020({ allErrors: true });
addFormats(ajv);
ajv.addKeyword("x-cobol");
const validate = ajv.compile(schema);

type Event = { id: string; type: string; subject: string; data: Record<string, any> };

// The EVENTS section shows events.jsonl as written, one event per line.
// A run's last event is always run.completed or run.aborted, so waiting
// for it means the whole list has arrived.
async function events(page: Page): Promise<Event[]> {
  const section = report(page, "EVENTS");
  await expect(section).toContainText(/ledger\.run\.(completed|aborted)"/);
  const text = await section.innerText();
  return text.split("\n").filter((line) => line.trim() !== "").map((line) => JSON.parse(line));
}

function ofType(all: Event[], type: string) {
  return all.filter((event) => event.type === TYPE + type);
}

test("every event of the sample run matches the schema", async ({ page }) => {
  await runBatch(page);
  const all = await events(page);

  for (const event of all) {
    expect(validate(event), `${event.id}: ${ajv.errorsText(validate.errors)}`).toBe(true);
  }
  // Ids number the run date's events in order.
  const runDate = all[0].id.slice(0, 8);
  expect(all.map((event) => event.id)).toEqual(
    all.map((_, i) => `${runDate}-${String(i + 1).padStart(7, "0")}`),
  );
});

test("the run ends with run.completed, which accounts for every event", async ({ page }) => {
  await runBatch(page);
  const all = await events(page);

  const last = all.at(-1)!;
  expect(last.type).toBe(TYPE + "run.completed");
  expect(last.data.counts.events).toBe(all.length - 1);
  expect(last.data.totals).toMatchObject({ opening: "268400.50", closing: "272854.84", suspense: "9000.00" });
  expect(ofType(all, "transaction.invalid")).toHaveLength(last.data.counts.invalid);
  expect(ofType(all, "transaction.declined")).toHaveLength(last.data.counts.declined);
  expect(ofType(all, "transfer.suspended")).toHaveLength(last.data.counts.suspended);
});

test("each account's last posting matches its balance in the new master", async ({ page }) => {
  await runBatch(page);
  const all = await events(page);
  await expect(report(page, "NEW MASTER FILE")).toContainText("10000007MOLLY");
  const master = (await report(page, "NEW MASTER FILE").innerText()).split("\n").filter(Boolean);

  const lastBalance = new Map<string, string>();
  for (const event of ofType(all, "entry.posted")) {
    lastBalance.set(event.data.account, event.data.balance);
  }
  expect(lastBalance.size).toBeGreaterThan(0);
  for (const [account, balance] of lastBalance) {
    // AC-BALANCE: S9(9)V99 SIGN LEADING SEPARATE, from column 49.
    const record = master.find((line) => line.startsWith(account))!;
    const field = record.slice(48, 60);
    const expected = `${field[0] === "-" ? "-" : ""}${Number(field.slice(1, 10))}.${field.slice(10)}`;
    expect(balance, account).toBe(expected);
  }
});

test("a transfer posts both legs and codes become named values", async ({ page }) => {
  await runBatch(page);
  const all = await events(page);

  const legs = ofType(all, "entry.posted").filter((event) => event.data.reference === "LOAN REPAYMENT");
  expect(legs.map((event) => event.data)).toEqual([
    expect.objectContaining({ account: "10000001", kind: "transfer_in", counterparty: "10000002", amount: "1000.00" }),
    expect.objectContaining({ account: "10000002", kind: "transfer_out", counterparty: "10000001", amount: "1000.00" }),
  ]);
  expect(ofType(all, "transfer.suspended").map((event) => event.data.reason)).toEqual([
    "target_closed",
    "target_not_found",
  ]);
});

test("an aborted run publishes only run.aborted", async ({ page }) => {
  const PIETER = "10000002PIETER VAN DER MERWE          A000000000+00000320050";
  const THANDI = "10000001THANDI NKOSI                  A000500000+00001245000";
  await runBatch(page, { accounts: `${PIETER}\n${THANDI}` });
  const all = await events(page);

  expect(all).toHaveLength(1);
  expect(validate(all[0])).toBe(true);
  expect(all[0].type).toBe(TYPE + "run.aborted");
  expect(all[0].data.message).toBe("MASTER RECORD 2 (ACCOUNT 10000001) IS OUT OF SEQUENCE");
});

test("text from the input is escaped as JSON, then as HTML", async ({ page }) => {
  await runBatch(page, {
    accounts: "10000006NOMSA ZULU                    A000000000+00000500000",
    transactions: '1000000620261015D0000001000000000000SAY "HI" & <B>\\',
  });
  const all = await events(page);

  expect(ofType(all, "entry.posted")[0].data.reference).toBe('SAY "HI" & <B>\\');
  await expect(page.locator("b")).toHaveCount(0);
});
