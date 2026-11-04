      *> Work record, 63 bytes. Holds a validated transaction after the
      *> first sort, and an authorised ledger entry after authorisation,
      *> when each transfer becomes an O leg on the source account and an
      *> I leg on the target account.
       01  ENTRY-RECORD.
           05  EN-ACCT-NO              PIC 9(8).
           05  EN-DATE                 PIC 9(8).
           05  EN-SEQ                  PIC 9(7).
           05  EN-LEG                  PIC X.
               88  EN-DEPOSIT                    VALUE "D".
               88  EN-WITHDRAWAL                 VALUE "W".
               88  EN-TRANSFER                   VALUE "T".
               88  EN-TRANSFER-OUT               VALUE "O".
               88  EN-TRANSFER-IN                VALUE "I".
           05  EN-AMOUNT               PIC 9(9)V99.
           05  EN-OTHER-ACCT           PIC 9(8).
           05  EN-REF                  PIC X(20).
