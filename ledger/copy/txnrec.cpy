      *> Transaction input record, 56 bytes, in any order.
      *> TX-TARGET is only used by transfers.
       01  TXN-RECORD.
           05  TX-ACCT-NO              PIC 9(8).
           05  TX-DATE                 PIC 9(8).
           05  TX-TYPE                 PIC X.
               88  TX-VALID-TYPE                 VALUES "D" "W" "T".
               88  TX-TRANSFER                   VALUE "T".
           05  TX-AMOUNT               PIC 9(9)V99.
           05  TX-TARGET               PIC 9(8).
           05  TX-REF                  PIC X(20).
