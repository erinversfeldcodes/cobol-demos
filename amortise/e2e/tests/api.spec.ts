import { test, expect } from "@playwright/test";

const API = "/cgi-bin/amortise-api";

test("a valid loan returns the schedule as typed JSON", async ({ request }) => {
  const response = await request.get(API, { params: { principal: "250000", rate: "11.75", term: "240" } });

  expect(response.status()).toBe(200);
  expect(response.headers()["content-type"]).toBe("application/json");
  expect(response.headers()["access-control-allow-origin"]).toBe("*");
  const body = await response.json();
  expect(body.loan).toEqual({ principal: "250000.00", annualRate: "11.7500", termMonths: 240 });
  expect(body).toMatchObject({ payment: "2709.27", totalInterest: "400222.31", totalPaid: "650222.31" });
  expect(body.schedule).toHaveLength(240);
  expect(body.schedule[0]).toEqual({
    period: 1, payment: "2709.27", interest: "2447.92", principal: "261.35", balance: "249738.65",
  });
  expect(body.schedule.at(-1)).toEqual({
    period: 240, payment: "2706.78", interest: "26.25", principal: "2680.53", balance: "0.00",
  });
});

test("the API and the HTML page agree", async ({ request, page }) => {
  const response = await request.get(API, { params: { principal: "1000", rate: "12", term: "3" } });
  const body = await response.json();

  await page.goto("/cgi-bin/amortise?principal=1000&rate=12&term=3");
  const cells = await page.locator("tbody tr").evaluateAll((rows) =>
    rows.map((row) => [...row.querySelectorAll("td")].map((td) => td.textContent?.replaceAll(",", ""))),
  );
  expect(cells).toEqual(
    body.schedule.map((p: Record<string, unknown>) => [
      String(p.period), p.payment, p.interest, p.principal, p.balance,
    ]),
  );
});

for (const [name, params, code, field] of [
  ["principal", { principal: "abc", rate: "12", term: "3" }, "invalid_principal", "principal"],
  ["rate", { principal: "1000", rate: "101", term: "3" }, "invalid_rate", "rate"],
  ["term", { principal: "1000", rate: "12", term: "601" }, "invalid_term", "term"],
  ["payment", { principal: "1", rate: "0", term: "600" }, "payment_too_small", "principal"],
] as const) {
  test(`an invalid ${name} is a 400 with error code ${code}`, async ({ request }) => {
    const response = await request.get(API, { params });

    expect(response.status()).toBe(400);
    const { error } = await response.json();
    expect(error).toMatchObject({ code, field });
    expect(error.message).not.toBe("");
  });
}

test("methods other than GET are refused", async ({ request }) => {
  const response = await request.post(API);

  expect(response.status()).toBe(405);
  expect(response.headers()["allow"]).toBe("GET");
  expect((await response.json()).error.code).toBe("method_not_allowed");
});

test("the OpenAPI contract is served and describes the endpoint", async ({ request }) => {
  const response = await request.get("/openapi.json");

  expect(response.headers()["content-type"]).toBe("application/json");
  const spec = await response.json();
  expect(spec.paths[API].get.operationId).toBe("amortiseLoan");
  expect(spec.components.schemas.Error.properties.error.properties.code.enum).toContain("invalid_term");
});
