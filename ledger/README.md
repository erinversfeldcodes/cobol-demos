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

## Web

`GET /cgi-bin/ledger` shows both files in editable text areas, filled
with the sample data. Submitting them runs the batch in a private
temporary directory and shows every report. Bodies over 60,000 bytes are
refused.

## Programs

| File | Role |
| --- | --- |
| `src/ledgrun.cbl` | `LEDGRUN`: the four-step batch |
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
