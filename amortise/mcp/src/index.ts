#!/usr/bin/env node
// MCP server for the COBOL loan amortisation API. It is deliberately
// thin: it describes the tool, calls /cgi-bin/amortise-api and passes
// the result through. Every calculation happens in AMORTCALC, so an
// agent gets the same exact decimal answer as the web page and the CLI.
import { McpServer } from "@modelcontextprotocol/sdk/server/mcp.js";
import { StdioServerTransport } from "@modelcontextprotocol/sdk/server/stdio.js";
import { z } from "zod";

const API_URL = process.env.AMORTISE_API_URL ?? "https://cobol-demos-amortise.fly.dev";

// Mirrors the Amount schema in www/openapi.json. Amounts stay strings
// end to end so no float rounding is introduced on the way through.
const amount = z.string().regex(/^[0-9]+\.[0-9]{2}$/);

const period = z.object({
  period: z.number().int(),
  payment: amount,
  interest: amount,
  principal: amount.describe("The part of this payment that repays principal"),
  balance: amount.describe("Principal still owed after this payment"),
});

const amortisation = z.object({
  loan: z.object({
    principal: amount,
    annualRate: z.string().describe("Annual percentage rate, four decimals"),
    termMonths: z.number().int(),
  }),
  payment: amount.describe("Regular monthly payment"),
  totalInterest: amount,
  totalPaid: amount,
  schedule: z.array(period).optional().describe("Every payment, when includeSchedule is true"),
});

const apiError = z.object({
  error: z.object({ code: z.string(), field: z.string(), message: z.string() }),
});

// Agents often send numbers; strings are preferred because they are
// passed to COBOL exactly as written.
const decimalInput = z.union([z.string(), z.number()]);

const server = new McpServer({ name: "amortise", version: "1.0.0" });

server.registerTool(
  "amortise_loan",
  {
    title: "Amortise a loan",
    description:
      "Calculates the fixed monthly repayment, total interest and total repaid for a loan, " +
      "using exact decimal arithmetic in a COBOL program. Amounts are returned as strings " +
      "with two decimals. Set includeSchedule for the full month-by-month schedule (up to 600 rows).",
    inputSchema: {
      principal: decimalInput.describe("Amount borrowed, 0.01 to 999999999.99, at most 2 decimals, e.g. \"250000\""),
      rate: decimalInput.describe("Annual interest rate as a percentage, 0 to 100, at most 4 decimals, e.g. \"11.75\""),
      term: decimalInput.describe("Term in whole months, 1 to 600, e.g. 240"),
      includeSchedule: z.boolean().default(false).describe("Include every payment in the result"),
    },
    outputSchema: amortisation.shape,
    annotations: { readOnlyHint: true, idempotentHint: true, openWorldHint: false },
  },
  async ({ principal, rate, term, includeSchedule }) => {
    const url = new URL("/cgi-bin/amortise-api", API_URL);
    url.search = new URLSearchParams({
      principal: String(principal),
      rate: String(rate),
      term: String(term),
    }).toString();

    let response: Response;
    try {
      // Generous, because the app's machines stop when idle and the
      // first request after that waits for one to start.
      response = await fetch(url, { signal: AbortSignal.timeout(30_000) });
    } catch (error) {
      return failure(`Could not reach the amortisation service at ${API_URL}: ${String(error)}`);
    }

    const body: unknown = await response.json().catch(() => undefined);
    if (!response.ok) {
      const parsed = apiError.safeParse(body);
      return parsed.success
        ? failure(`${parsed.data.error.code} (${parsed.data.error.field}): ${parsed.data.error.message}`)
        : failure(`The amortisation service returned HTTP ${response.status}`);
    }

    const result = amortisation.parse(body);
    if (!includeSchedule) {
      delete result.schedule;
    }
    return {
      content: [{ type: "text", text: JSON.stringify(result) }],
      structuredContent: result,
    };
  },
);

function failure(text: string) {
  return { content: [{ type: "text" as const, text }], isError: true };
}

await server.connect(new StdioServerTransport());
