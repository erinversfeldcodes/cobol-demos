      *> LEDGRUN result. Return codes follow batch convention:
      *> 0 clean, 4 completed with exceptions, 16 run aborted.
       01  LEDGER-RESULT.
           05  LS-RETURN-CODE          PIC 9(2).
               88  LS-CLEAN                      VALUE 0.
               88  LS-EXCEPTIONS                 VALUE 4.
               88  LS-ABORTED                    VALUE 16.
           05  LS-EXCEPTION-COUNT      PIC 9(7).
           05  LS-MESSAGE              PIC X(120).
