      *> AMORTCALC request. Inputs stay as text so that the CLI and the
      *> web front end share one set of parsing and validation rules.
       01  AMORT-REQUEST.
           05  AR-PRINCIPAL-TEXT       PIC X(20).
           05  AR-RATE-TEXT            PIC X(20).
           05  AR-TERM-TEXT            PIC X(20).
