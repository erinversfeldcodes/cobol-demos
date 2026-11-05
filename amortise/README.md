# amortise

Monthly repayment schedule for a fixed-rate loan, with every amount
calculated in exact decimal and rounded to the cent. The final payment
absorbs accumulated rounding, so the balance always closes at 0.00.

## CLI

```
amortise [--csv] PRINCIPAL ANNUAL-RATE MONTHS
```

```
$ amortise 250000 11.75 240
LOAN AMORTISATION SCHEDULE

Principal                 250,000.00
Annual rate                  11.7500 %
Term                             240 months
Monthly payment             2,709.27
Total interest            400,222.31
Total repaid              650,222.31

PERIOD           PAYMENT          INTEREST         PRINCIPAL           BALANCE
------  ----------------  ----------------  ----------------  ----------------
     1          2,709.27          2,447.92            261.35        249,738.65
...
```

`--csv` prints the schedule as `period,payment,interest,principal,balance`.

| Input | Range |
| --- | --- |
| Principal | 0.01 to 999,999,999.99, at most 2 decimals |
| Annual rate | 0 to 100 percent, at most 4 decimals |
| Months | 1 to 600 |

Exit status: 0 success, 1 invalid loan details, 2 usage error.

## Web

`GET /cgi-bin/amortise?principal=250000&rate=11.75&term=240` renders the
form and schedule as HTML.

## JSON API

`GET /cgi-bin/amortise-api` takes the same parameters and returns JSON.
The contract is [`www/openapi.json`](www/openapi.json), served at
`/openapi.json`.

```
$ curl 'https://cobol-demos-amortise.fly.dev/cgi-bin/amortise-api?principal=1000&rate=12&term=3'
{"loan":{"principal":"1000.00","annualRate":"12.0000","termMonths":3},
 "payment":"340.02","totalInterest":"20.07","totalPaid":"1020.07",
 "schedule":[{"period":1,"payment":"340.02","interest":"10.00","principal":"330.02","balance":"669.98"},...]}
```

An invalid request is a 400 with a code to branch on and a message for
people:

```json
{"error":{"code":"invalid_term","field":"term","message":"Term must be a whole number of months from 1 to 600"}}
```

| Code | Field | AMORTCALC status |
| --- | --- | --- |
| `invalid_principal` | `principal` | 10 |
| `invalid_rate` | `rate` | 20 |
| `invalid_term` | `term` | 30 |
| `payment_too_small` | `principal` | 40 |
| `method_not_allowed` (405) | `method` | |

### From copybook to contract

A copybook is a layout, not a schema: `AS-PAYMENT PIC 9(9)V99` says
eleven digits with an implied decimal point, but nothing about its name
on the wire, its JSON type or its meaning. The API adds those at the
boundary, and every property in the OpenAPI document records where it
came from:

```json
"payment": {
  "$ref": "#/components/schemas/Amount",
  "x-cobol": { "field": "AS-PAYMENT", "picture": "9(9)V99", "copybook": "amortres.cpy" }
}
```

The mapping decisions:

- **Amounts are strings** (`"2709.27"`). The COBOL fields are exact
  decimals, and most JSON consumers parse numbers as binary floats.
- **Status codes become stable names.** `AS-STATUS` `"30"` is
  `invalid_term`. Clients branch on `code`, never on `message`.
- **Keys are camelCase**, named with `JSON GENERATE ... NAME OF`.
  Without it, keys would be the COBOL names (`AS-TOTAL-INTEREST`).

`AMORTAPI` builds each object with `JSON GENERATE`, which also escapes
strings. GnuCOBOL 3.2 can't generate an `OCCURS` table, so each schedule
row is generated on its own and the array is joined around them.

## MCP server

[`mcp/`](mcp/) exposes the API to AI agents as one tool,
`amortise_loan`, over stdio. It's a thin adapter: it describes the tool
and its input and output schemas, calls the JSON API and passes the
result through, so an agent gets AMORTCALC's exact figures rather than
doing the maths itself. By default it returns the summary; set
`includeSchedule` for every payment.

```sh
cd mcp && npm ci && npm run build
claude mcp add amortise -- node "$PWD/dist/index.js"
```

Or in a Claude Desktop or other MCP client configuration:

```json
{
  "mcpServers": {
    "amortise": {
      "command": "node",
      "args": ["/path/to/cobol-demos/amortise/mcp/dist/index.js"]
    }
  }
}
```

It calls `https://cobol-demos-amortise.fly.dev` unless
`AMORTISE_API_URL` names another deployment, such as a local container
on `http://127.0.0.1:8080`.

## Programs

| File | Role |
| --- | --- |
| `src/amortcalc.cbl` | `AMORTCALC`: parses and validates the inputs, builds the schedule |
| `src/amortise.cbl` | CLI front end |
| `src/amortweb.cbl` | CGI front end: HTML |
| `src/amortapi.cbl` | CGI front end: JSON |
| `src/amortqry.cbl` | `AMORTQRY`: reads the query string for both CGI front ends |
| `copy/amortreq.cpy`, `copy/amortres.cpy` | Request and result layouts shared by all of them |
| `www/openapi.json` | The JSON API's contract |
| `mcp/` | MCP server over the JSON API |

## Build, test, run

```sh
make test
make install PREFIX=$HOME/.local
docker build -t amortise . && docker run --rm -p 8080:8080 amortise
docker run --rm amortise amortise 250000 11.75 240
```
