import { test, expect } from "@playwright/test";
import path from "node:path";
import { Client } from "@modelcontextprotocol/sdk/client/index.js";
import { StdioClientTransport } from "@modelcontextprotocol/sdk/client/stdio.js";

// Drives the MCP server in ../mcp over stdio, the way Claude Code or
// Claude Desktop would, pointed at the app under test.
let client: Client;

test.beforeEach(async ({ baseURL }) => {
  client = new Client({ name: "e2e", version: "1.0.0" });
  await client.connect(
    new StdioClientTransport({
      command: process.execPath,
      args: [path.join(__dirname, "../../mcp/dist/index.js")],
      env: { ...process.env, AMORTISE_API_URL: baseURL! } as Record<string, string>,
    }),
  );
});

test.afterEach(async () => {
  await client.close();
});

test("the server offers one read-only amortise_loan tool", async () => {
  const { tools } = await client.listTools();

  expect(tools.map((tool) => tool.name)).toEqual(["amortise_loan"]);
  expect(tools[0].annotations?.readOnlyHint).toBe(true);
  expect(tools[0].inputSchema.required).toEqual(["principal", "rate", "term"]);
  expect(tools[0].outputSchema).toBeDefined();
});

test("a tool call returns COBOL's exact figures as structured content", async () => {
  const result = await client.callTool({
    name: "amortise_loan",
    arguments: { principal: "250000", rate: 11.75, term: 240 },
  });

  expect(result.isError).toBeFalsy();
  expect(result.structuredContent).toEqual({
    loan: { principal: "250000.00", annualRate: "11.7500", termMonths: 240 },
    payment: "2709.27",
    totalInterest: "400222.31",
    totalPaid: "650222.31",
  });
});

test("the schedule is included only when asked for", async () => {
  const result = await client.callTool({
    name: "amortise_loan",
    arguments: { principal: "1000", rate: "12", term: "3", includeSchedule: true },
  });

  const { schedule } = result.structuredContent as { schedule: { balance: string }[] };
  expect(schedule.map((period) => period.balance)).toEqual(["669.98", "336.66", "0.00"]);
});

test("COBOL's validation errors come back as tool errors", async () => {
  const result = await client.callTool({
    name: "amortise_loan",
    arguments: { principal: "1000", rate: "12", term: 601 },
  });

  expect(result.isError).toBe(true);
  expect(result.content).toEqual([
    { type: "text", text: "invalid_term (term): Term must be a whole number of months from 1 to 600" },
  ]);
});
