      *> LEDGRUN request: input files, output directory and run date.
      *> Outputs written to LR-OUT-DIR: accounts.new.dat, statements.txt,
      *> exceptions.txt and control.txt.
       01  LEDGER-REQUEST.
           05  LR-MASTER-PATH          PIC X(256).
           05  LR-TXN-PATH             PIC X(256).
           05  LR-OUT-DIR              PIC X(256).
           05  LR-RUN-DATE             PIC 9(8).
