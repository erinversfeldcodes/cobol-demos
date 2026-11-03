      *> Account master record, 60 bytes, sorted ascending by account.
      *> Amounts carry an implied decimal point (V): 000500000 = 5000.00.
       01  ACCOUNT-RECORD.
           05  AC-ACCT-NO              PIC 9(8).
           05  AC-NAME                 PIC X(30).
           05  AC-STATUS               PIC X.
               88  AC-ACTIVE                     VALUE "A".
               88  AC-CLOSED                     VALUE "C".
           05  AC-OD-LIMIT             PIC 9(7)V99.
           05  AC-BALANCE              PIC S9(9)V99 SIGN LEADING SEPARATE.
