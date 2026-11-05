# ledger

A nightly batch run on a bank ledger: it applies a day's deposits,
withdrawals and transfers to a sequential account master file. It
writes a new master, a statement for every account with activity, an
exceptions report and a control report that proves the ledger
balances.

## CLI

```
ledger [--date YYYYMMDD] MASTER TRANSACTIONS OUTDIR
```

```sh
ledger --date 20261031 samples/accounts.dat samples/transactions.dat out
```

| Output | Contents |
| --- | --- |
| `OUTDIR/accounts.new.dat` | Updated master, same layout as the input |
| `OUTDIR/statements.txt` | Opening balance, entries in date order, closing balance |
| `OUTDIR/exceptions.txt` | Every rejected or suspended transaction, with a reason code |
| `OUTDIR/control.txt` | Record counts, amount totals and the reconciliation (also printed to stdout) |
| `OUTDIR/events.jsonl` | What the run did, as CloudEvents for other systems (see [Events](#events)) |

Exit status follows batch convention: 0 clean, 4 completed with
exceptions, 16 run aborted, 2 usage error.

## How a run works

1. **Sort.** Validate each transaction record and sort the good ones by
   account, date and input line.
2. **Authorise.** Match the transactions against the master (a
   balanced-line update) and reject any that fail the account checks.
   Each transfer becomes an *out* leg on the source account and an *in*
   leg on the target account.
3. **Sort.** Sort the authorised entries so each in leg meets its target
   account.
4. **Post.** Match against the master again, write the new master and
   the statements, and check that the control totals balance.

Overdraft checks in step 2 ignore incoming transfers, so they never
approve more than the final balance allows. A transfer whose target is
missing or closed is only discovered in step 4, after the money has left
the source account, so it is held in suspense and reported.

## Record layouts

Fixed width. Amounts have an implied decimal point, so `00000250000` is
2,500.00.

Account master (60 bytes, ascending account number, `copy/acctrec.cpy`):

| Columns | Field | Picture |
| --- | --- | --- |
| 1-8 | Account number | `9(8)` |
| 9-38 | Name | `X(30)` |
| 39 | Status: `A` active, `C` closed | `X` |
| 40-48 | Overdraft limit | `9(7)V99` |
| 49-60 | Balance, leading sign | `S9(9)V99 SIGN LEADING SEPARATE` |

Transactions (56 bytes, any order, `copy/txnrec.cpy`):

| Columns | Field | Picture |
| --- | --- | --- |
| 1-8 | Account number | `9(8)` |
| 9-16 | Date, YYYYMMDD | `9(8)` |
| 17 | Type: `D` deposit, `W` withdrawal, `T` transfer | `X` |
| 18-28 | Amount | `9(9)V99` |
| 29-36 | Transfer target account | `9(8)` |
| 37-56 | Reference | `X(20)` |

## Exception codes

| Code | Meaning | Stage |
| --- | --- | --- |
| E01 | Account number not numeric | Validation |
| E02 | Invalid date | Validation |
| E03 | Unknown transaction type | Validation |
| E04 | Amount not numeric or zero | Validation |
| E05 | Transfer target invalid or same as source | Validation |
| E10 | Account not found | Authorisation |
| E11 | Account closed | Authorisation |
| E12 | Insufficient funds (beyond overdraft limit) | Authorisation |
| E13 | Deposit would exceed the 999,999,999.99 balance limit | Authorisation |
| E20 | Transfer target not found, held in suspense | Posting |
| E21 | Transfer target closed, held in suspense | Posting |
| E22 | Transfer target at balance limit, held in suspense | Posting |

A malformed master record or a master out of account order aborts the
run (exit 16).

## Events

A batch system's usual way of telling the rest of the world what
happened is a set of files and a downstream job that diffs them.
`events.jsonl` publishes it as events instead: one
[CloudEvents 1.0](https://cloudevents.io) JSON object per line, ready
for a relay to put on Kafka, a queue or a webhook. The contract is
[`schema/events.schema.json`](schema/events.schema.json).

```json
{"specversion":"1.0","id":"20261031-0000011","source":"/cobol-demos/ledger",
 "type":"io.github.erinversfeldcodes.cobol-demos.ledger.entry.posted",
 "subject":"accounts/10000001","time":"2026-10-31T00:00:00Z","datacontenttype":"application/json",
 "data":{"account":"10000001","kind":"transfer_in","amount":"1000.00","balance":"38450.00",
         "counterparty":"10000002","reference":"LOAN REPAYMENT","date":"2026-10-02","line":14}}
```

| Type (after `io.github.erinversfeldcodes.cobol-demos.ledger.`) | When |
| --- | --- |
| `entry.posted` | An entry posted to an account, with the balance after it. A transfer posts `transfer_out` and `transfer_in`. |
| `transaction.invalid` | A record failed validation (E01-E05). Carries the raw record, since its fields can't be trusted. |
| `transaction.declined` | A valid transaction refused against the master (E10-E13). |
| `transfer.suspended` | A transfer left its source but couldn't be credited (E20-E22). |
| `run.completed` | Last event of a balanced run, with the control counts and totals. |
| `run.aborted` | The only event of a run that stopped. |

### The outbox pattern

Events are written by the same run that writes the new master, and
published only when that run is known to be good. `LEDGEVT` collects
them in a work file as the run goes. If the run balances, they are
copied to `events.jsonl` followed by `run.completed`. If it aborts,
`events.jsonl` holds `run.aborted` alone. So a consumer never sees
events for a master file that wasn't written, or half a run.
`run.completed` counts the events before it, so a consumer can check it
received all of them.

Because the batch writes the events itself, there's no separate step
that could crash after the master was written but before the events
went out. That's the failure that dual writes to a database and a broker
are prone to. A relay can ship the file at its own pace and retry
safely.

Events are deterministic. `id` is the run date and the event's position,
and `time` is the run date (the business date of the batch, not the
clock). Rerunning a date reproduces its ids, so a rerun replaces that
date's events rather than adding to them.

### From codes to meaning

The master and transaction files are full of codes. They only mean
something to programs that share the copybooks. The events translate
them at the boundary, and the schema records where each field came from
(`x-cobol`):

| COBOL | Event |
| --- | --- |
| `EN-LEG` `"O"` | `"kind": "transfer_out"` |
| `WS-EX-CODE` `"E12"` | `"code": "E12", "reason": "insufficient_funds"` |
| `AC-BALANCE` `-00000025000` (`S9(9)V99 SIGN LEADING SEPARATE`) | `"balance": "-250.00"` |
| `EN-DATE` `20261002` | `"date": "2026-10-02"` |
| `AC-ACCT-NO` `10000001` (`9(8)`) | `"account": "10000001"`, a string, because it's an identifier |

Amounts are exact decimal strings, not JSON numbers, which most
consumers would read as binary floats. Each object is built with `JSON
GENERATE`, which names keys and escapes text. It can't make a field
optional, so event shapes that differ, such as a posting with or
without a counterparty, are separate `JSON GENERATE` statements.

## Web

`GET /cgi-bin/ledger` shows both files in editable text areas, filled
with the sample data. Submitting them runs the batch in a private
temporary directory and shows every report, including the events.
Bodies over 60,000 bytes are refused.

## Programs

| File | Role |
| --- | --- |
| `src/ledgrun.cbl` | `LEDGRUN`: the four-step batch |
| `src/ledgevt.cbl` | `LEDGEVT`: the event outbox, and the events' JSON |
| `schema/events.schema.json` | The events' contract |
| `src/ledger.cbl` | CLI front end |
| `src/ledgerweb.cbl` | CGI front end |

## Build, test, run

```sh
make test
make install PREFIX=$HOME/.local
docker build -t ledger . && docker run --rm -p 8080:8080 ledger
docker run --rm -v "$PWD:/data" -w /data ledger \
  ledger samples/accounts.dat samples/transactions.dat out
```
