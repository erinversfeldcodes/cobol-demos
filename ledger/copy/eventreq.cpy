      *> LEDGEVT request. LEDGRUN describes each event in COBOL terms
      *> (account numbers, leg codes, implied decimals); LEDGEVT owns
      *> their JSON shape. Fields not used by an event kind are ignored.
       01  EVENT-REQUEST.
           05  EV-OPERATION            PIC X(6).
               88  EV-BEGIN                      VALUE "BEGIN".
               88  EV-EMIT                       VALUE "EMIT".
               88  EV-COMMIT                     VALUE "COMMIT".
               88  EV-ABORT                      VALUE "ABORT".
           05  EV-OUT-DIR              PIC X(256).
           05  EV-RUN-DATE             PIC 9(8).
           05  EV-KIND                 PIC X(9).
               88  EV-POSTED                     VALUE "POSTED".
               88  EV-INVALID                    VALUE "INVALID".
               88  EV-DECLINED                   VALUE "DECLINED".
               88  EV-SUSPENDED                  VALUE "SUSPENDED".
      *>   Transaction line, exception code and its reason text.
           05  EV-LINE                 PIC 9(7).
           05  EV-CODE                 PIC X(3).
           05  EV-REASON               PIC X(40).
      *>   INVALID: the input record as written.
           05  EV-RECORD               PIC X(56).
      *>   POSTED, DECLINED, SUSPENDED: the entry, laid out as
      *>   entryrec.cpy, and for POSTED the balance after it.
           05  EV-ACCT-NO              PIC 9(8).
           05  EV-DATE                 PIC 9(8).
           05  EV-LEG                  PIC X.
           05  EV-AMOUNT               PIC 9(9)V99.
           05  EV-OTHER-ACCT           PIC 9(8).
           05  EV-REF                  PIC X(20).
           05  EV-BALANCE              PIC S9(9)V99.
      *>   ABORT: why the run stopped.
           05  EV-MESSAGE              PIC X(120).
      *>   COMMIT: the run's control counts and totals.
           05  EV-COUNTS.
               10  EV-CT-READ          PIC 9(7).
               10  EV-CT-INVALID       PIC 9(7).
               10  EV-CT-DECLINED      PIC 9(7).
               10  EV-CT-ACCEPTED      PIC 9(7).
               10  EV-CT-SUSPENDED     PIC 9(7).
               10  EV-CT-ACCOUNTS      PIC 9(7).
               10  EV-CT-STATEMENTS    PIC 9(7).
           05  EV-TOTALS.
               10  EV-TT-OPENING       PIC S9(12)V99.
               10  EV-TT-DEPOSITS      PIC S9(12)V99.
               10  EV-TT-WITHDRAWALS   PIC S9(12)V99.
               10  EV-TT-TRANSFERS-OUT PIC S9(12)V99.
               10  EV-TT-TRANSFERS-IN  PIC S9(12)V99.
               10  EV-TT-SUSPENSE      PIC S9(12)V99.
               10  EV-TT-CLOSING       PIC S9(12)V99.
      *>   Set by LEDGEVT: "00" or the failing file status.
           05  EV-STATUS               PIC XX.
