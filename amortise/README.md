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

## Programs

| File | Role |
| --- | --- |
| `src/amortcalc.cbl` | `AMORTCALC`: parses and validates the inputs, builds the schedule |
| `src/amortise.cbl` | CLI front end |
| `src/amortweb.cbl` | CGI front end |
| `copy/amortreq.cpy`, `copy/amortres.cpy` | Request and result layouts shared by all three |

## Build, test, run

```sh
make test
make install PREFIX=$HOME/.local
docker build -t amortise . && docker run --rm -p 8080:8080 amortise
docker run --rm amortise amortise 250000 11.75 240
```
