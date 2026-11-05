       IDENTIFICATION DIVISION.
       PROGRAM-ID. LEDGRUN.
      *> Nightly ledger batch, run as four steps in the classic style:
      *>
      *>   1. SORT-TRANSACTIONS  validate the transaction file and sort it
      *>                         by account, date and input line
      *>   2. AUTHORISE          match against the old master; approve or
      *>                         reject each transaction and split
      *>                         transfers into an out leg and an in leg
      *>   3. SORT-ENTRIES       sort the authorised entries into account
      *>                         order, so in legs meet their target account
      *>   4. POST               match against the old master again to write
      *>                         the new master and the statements
      *>
      *> A transfer whose target turns out to be missing or closed in step
      *> 4 has already left the source account, so it is held in suspense
      *> and reported rather than silently dropped.

       ENVIRONMENT DIVISION.
       INPUT-OUTPUT SECTION.
       FILE-CONTROL.
           SELECT MASTER-IN     ASSIGN TO WS-MASTER-PATH
               ORGANIZATION IS LINE SEQUENTIAL
               FILE STATUS IS WS-FS-MASTER.
           SELECT TXN-IN        ASSIGN TO WS-TXN-PATH
               ORGANIZATION IS LINE SEQUENTIAL
               FILE STATUS IS WS-FS-TXN.
           SELECT MASTER-OUT    ASSIGN TO WS-NEW-MASTER-PATH
               ORGANIZATION IS LINE SEQUENTIAL
               FILE STATUS IS WS-FS-NEW-MASTER.
           SELECT STATEMENTS    ASSIGN TO WS-STATEMENTS-PATH
               ORGANIZATION IS LINE SEQUENTIAL
               FILE STATUS IS WS-FS-STATEMENTS.
           SELECT EXCEPTIONS    ASSIGN TO WS-EXCEPTIONS-PATH
               ORGANIZATION IS LINE SEQUENTIAL
               FILE STATUS IS WS-FS-EXCEPTIONS.
           SELECT CONTROL-RPT   ASSIGN TO WS-CONTROL-PATH
               ORGANIZATION IS LINE SEQUENTIAL
               FILE STATUS IS WS-FS-CONTROL.
           SELECT WORK-TXNS     ASSIGN TO WS-WORK-TXNS-PATH
               ORGANIZATION IS SEQUENTIAL
               FILE STATUS IS WS-FS-WORK.
           SELECT WORK-ENTRIES  ASSIGN TO WS-WORK-ENTRIES-PATH
               ORGANIZATION IS SEQUENTIAL
               FILE STATUS IS WS-FS-WORK.
           SELECT WORK-POSTINGS ASSIGN TO WS-WORK-POSTINGS-PATH
               ORGANIZATION IS SEQUENTIAL
               FILE STATUS IS WS-FS-WORK.
           SELECT TXN-SORT      ASSIGN TO "txnsort".
           SELECT ENTRY-SORT    ASSIGN TO "entrysort".

       DATA DIVISION.
       FILE SECTION.
       FD  MASTER-IN.
       01  MASTER-IN-REC               PIC X(60).
       FD  TXN-IN.
       01  TXN-IN-REC                  PIC X(56).
       FD  MASTER-OUT.
       01  MASTER-OUT-REC              PIC X(60).
       FD  STATEMENTS.
       01  STATEMENT-REC               PIC X(92).
       FD  EXCEPTIONS.
       01  EXCEPTION-REC               PIC X(110).
       FD  CONTROL-RPT.
       01  CONTROL-REC                 PIC X(80).
       FD  WORK-TXNS.
       01  WORK-TXN-REC                PIC X(63).
       FD  WORK-ENTRIES.
       01  WORK-ENTRY-REC              PIC X(63).
       FD  WORK-POSTINGS.
       01  WORK-POSTING-REC            PIC X(63).
       SD  TXN-SORT.
       01  TS-RECORD.
           05  TS-ACCT-NO              PIC 9(8).
           05  TS-DATE                 PIC 9(8).
           05  TS-SEQ                  PIC 9(7).
           05  FILLER                  PIC X(40).
       SD  ENTRY-SORT.
       01  ES-RECORD.
           05  ES-ACCT-NO              PIC 9(8).
           05  ES-DATE                 PIC 9(8).
           05  ES-SEQ                  PIC 9(7).
           05  FILLER                  PIC X(40).

       WORKING-STORAGE SECTION.
       COPY "acctrec.cpy".
       COPY "txnrec.cpy".
       COPY "entryrec.cpy".
       COPY "eventreq.cpy".

       01  WS-PATHS.
           05  WS-MASTER-PATH          PIC X(300).
           05  WS-TXN-PATH             PIC X(300).
           05  WS-NEW-MASTER-PATH      PIC X(300).
           05  WS-STATEMENTS-PATH      PIC X(300).
           05  WS-EXCEPTIONS-PATH      PIC X(300).
           05  WS-CONTROL-PATH         PIC X(300).
           05  WS-WORK-TXNS-PATH       PIC X(300).
           05  WS-WORK-ENTRIES-PATH    PIC X(300).
           05  WS-WORK-POSTINGS-PATH   PIC X(300).

       01  WS-FILE-STATUSES.
           05  WS-FS-MASTER            PIC XX.
           05  WS-FS-TXN               PIC XX.
           05  WS-FS-NEW-MASTER        PIC XX.
           05  WS-FS-STATEMENTS        PIC XX.
           05  WS-FS-EXCEPTIONS        PIC XX.
           05  WS-FS-CONTROL           PIC XX.
           05  WS-FS-WORK              PIC XX.

       01  WS-FLAGS.
           05  WS-ABORT-FLAG           PIC X.
               88  WS-ABORTED                    VALUE "Y".
           05  WS-TXN-EOF-FLAG         PIC X.
               88  WS-TXN-EOF                    VALUE "Y".
           05  WS-STATEMENT-FLAG       PIC X.
               88  WS-STATEMENT-OPEN             VALUE "Y".
               88  WS-STATEMENT-CLOSED           VALUE "N".

      *> Balanced-line keys. HIGH-VALUES marks end of file, which sorts
      *> above every real account number.
       01  WS-MASTER-KEY               PIC X(8).
       01  WS-PREV-MASTER-KEY          PIC X(8).
       01  WS-ENTRY-KEY                PIC X(8).
       01  WS-MASTER-COUNT             PIC 9(7).
       01  WS-SWAP-ACCT                PIC 9(8).

       01  WS-LINE-NO                  PIC 9(7).
       01  WS-CUR-BALANCE              PIC S9(9)V99.
       01  WS-NEW-BALANCE              PIC S9(11)V99.
       01  WS-MAX-BALANCE              PIC S9(11)V99 VALUE 999999999.99.
       01  WS-RUN-DATE-TEXT            PIC X(10).
       01  WS-DATE-TEXT                PIC X(10).
       01  WS-DATE-IN                  PIC X(8).

       01  WS-COUNTS.
           05  CT-TXN-READ             PIC 9(7).
           05  CT-REJECTED-FORMAT      PIC 9(7).
           05  CT-REJECTED-AUTH        PIC 9(7).
           05  CT-ACCEPTED             PIC 9(7).
           05  CT-ENTRIES-WRITTEN      PIC 9(7).
           05  CT-ENTRIES-READ         PIC 9(7).
           05  CT-SUSPENSE             PIC 9(7).
           05  CT-MASTER-RECORDS       PIC 9(7).
           05  CT-STATEMENTS           PIC 9(7).
           05  CT-EXCEPTIONS           PIC 9(7).
       01  WS-TOTALS.
           05  TT-DEPOSITS             PIC S9(12)V99.
           05  TT-WITHDRAWALS          PIC S9(12)V99.
           05  TT-TRANSFERS-OUT        PIC S9(12)V99.
           05  TT-TRANSFERS-IN         PIC S9(12)V99.
           05  TT-SUSPENSE             PIC S9(12)V99.
           05  TT-OPENING              PIC S9(12)V99.
           05  TT-CLOSING              PIC S9(12)V99.
           05  TT-EXPECTED             PIC S9(12)V99.
       01  WS-BALANCED-FLAG            PIC X.
           88  WS-BALANCED                       VALUE "Y".

      *> Fields describing one exception, filled before WRITE-EXCEPTION.
       01  WS-EX.
           05  WS-EX-LINE              PIC 9(7).
           05  WS-EX-ACCT              PIC X(8).
           05  WS-EX-DATE              PIC X(8).
           05  WS-EX-TYPE              PIC X.
           05  WS-EX-AMOUNT            PIC X(11).
           05  WS-EX-AMOUNT-N          REDEFINES WS-EX-AMOUNT
                                       PIC 9(9)V99.
           05  WS-EX-CODE              PIC X(3).
           05  WS-EX-REASON            PIC X(40).

       01  WS-RULE-EQ                  PIC X(92) VALUE ALL "=".
       01  WS-RULE-DASH                PIC X(92) VALUE ALL "-".
       01  WS-TITLE-LINE               PIC X(92).

       01  EXC-HEADING.
           05  FILLER                  PIC X(9)  VALUE "     LINE".
           05  FILLER                  PIC X(10) VALUE "  ACCOUNT".
           05  FILLER                  PIC X(12) VALUE "  DATE".
           05  FILLER                  PIC X(6)  VALUE "  TYPE".
           05  FILLER                  PIC X(16) VALUE "          AMOUNT".
           05  FILLER                  PIC X(6)  VALUE "  CODE".
           05  FILLER                  PIC X(8)  VALUE "  REASON".
       01  EXC-RULE.
           05  FILLER                  PIC X(9)  VALUE "  -------".
           05  FILLER                  PIC X(10) VALUE "  --------".
           05  FILLER                  PIC X(12) VALUE "  ----------".
           05  FILLER                  PIC X(6)  VALUE "  ----".
           05  FILLER                  PIC X(16) VALUE "  --------------".
           05  FILLER                  PIC X(6)  VALUE "  ----".
           05  FILLER                  PIC X(42) VALUE "  ----------------------------------------".
       01  EXC-DETAIL.
           05  ED-LINE                 PIC Z(8)9.
           05  FILLER                  PIC X(2)  VALUE SPACES.
           05  ED-ACCT                 PIC X(8).
           05  FILLER                  PIC X(2)  VALUE SPACES.
           05  ED-DATE                 PIC X(10).
           05  FILLER                  PIC X(2)  VALUE SPACES.
           05  ED-TYPE                 PIC X(4).
           05  FILLER                  PIC X(2)  VALUE SPACES.
           05  ED-AMOUNT               PIC X(14) JUSTIFIED RIGHT.
           05  FILLER                  PIC X(2)  VALUE SPACES.
           05  ED-CODE                 PIC X(4).
           05  FILLER                  PIC X(2)  VALUE SPACES.
           05  ED-REASON               PIC X(40).
       01  WS-ED-AMOUNT                PIC ZZZ,ZZZ,ZZ9.99.
       01  WS-ED-COUNT                 PIC Z,ZZZ,ZZ9.

       01  STMT-COLUMNS.
           05  FILLER                  PIC X(12) VALUE "DATE".
           05  FILLER                  PIC X(24) VALUE "DETAILS".
           05  FILLER                  PIC X(22) VALUE "REFERENCE".
           05  FILLER                  PIC X(16) VALUE "          AMOUNT".
           05  FILLER                  PIC X(18) VALUE "           BALANCE".
       01  STMT-DETAIL.
           05  SL-DATE                 PIC X(10).
           05  FILLER                  PIC X(2)  VALUE SPACES.
           05  SL-DETAILS              PIC X(22).
           05  FILLER                  PIC X(2)  VALUE SPACES.
           05  SL-REF                  PIC X(20).
           05  FILLER                  PIC X(2)  VALUE SPACES.
           05  SL-AMOUNT               PIC X(16).
           05  FILLER                  PIC X(2)  VALUE SPACES.
           05  SL-BALANCE              PIC -,---,---,--9.99.
       01  WS-ED-SIGNED                PIC -,---,---,--9.99.
       01  WS-SIGNED-AMOUNT            PIC S9(9)V99.

       01  CTL-LINE.
           05  CL-LABEL                PIC X(40).
           05  CL-VALUE                PIC X(20) JUSTIFIED RIGHT.
       01  WS-ED-TOTAL                 PIC -,---,---,---,--9.99.

       LINKAGE SECTION.
       COPY "ledgreq.cpy".
       COPY "ledgres.cpy".

       PROCEDURE DIVISION USING LEDGER-REQUEST LEDGER-RESULT.
       MAIN-PROCEDURE.
           INITIALIZE LEDGER-RESULT WS-COUNTS WS-TOTALS WS-FLAGS
           PERFORM BUILD-PATHS
           OPEN OUTPUT EXCEPTIONS
           IF WS-FS-EXCEPTIONS NOT = "00"
               STRING "CANNOT WRITE TO OUTPUT DIRECTORY "
                      FUNCTION TRIM(LR-OUT-DIR)
                      DELIMITED BY SIZE INTO LS-MESSAGE
               SET LS-ABORTED TO TRUE
               GOBACK
           END-IF
           PERFORM WRITE-EXCEPTION-HEADING
           PERFORM BEGIN-EVENTS

           PERFORM SORT-TRANSACTIONS
           IF NOT WS-ABORTED
               PERFORM AUTHORISE
           END-IF
           IF NOT WS-ABORTED
               SORT ENTRY-SORT
                   ON ASCENDING KEY ES-ACCT-NO ES-DATE ES-SEQ
                   USING WORK-ENTRIES
                   GIVING WORK-POSTINGS
           END-IF
           IF NOT WS-ABORTED
               PERFORM POST
           END-IF
           IF NOT WS-ABORTED
               PERFORM RECONCILE
           END-IF
      *>   Publish the events only once the run is known to be good.
           IF NOT WS-ABORTED
               PERFORM COMMIT-EVENTS
           END-IF
           IF WS-ABORTED
               PERFORM ABORT-EVENTS
           END-IF

           PERFORM WRITE-EXCEPTION-TRAILER
           CLOSE EXCEPTIONS
           PERFORM WRITE-CONTROL-REPORT
           PERFORM DELETE-WORK-FILES

           MOVE CT-EXCEPTIONS TO LS-EXCEPTION-COUNT
           EVALUATE TRUE
               WHEN WS-ABORTED
                   SET LS-ABORTED TO TRUE
               WHEN CT-EXCEPTIONS > 0
                   SET LS-EXCEPTIONS TO TRUE
               WHEN OTHER
                   SET LS-CLEAN TO TRUE
           END-EVALUATE
           GOBACK.

       BUILD-PATHS.
           MOVE LR-MASTER-PATH TO WS-MASTER-PATH
           MOVE LR-TXN-PATH    TO WS-TXN-PATH
           STRING FUNCTION TRIM(LR-OUT-DIR) "/accounts.new.dat"
               DELIMITED BY SIZE INTO WS-NEW-MASTER-PATH
           STRING FUNCTION TRIM(LR-OUT-DIR) "/statements.txt"
               DELIMITED BY SIZE INTO WS-STATEMENTS-PATH
           STRING FUNCTION TRIM(LR-OUT-DIR) "/exceptions.txt"
               DELIMITED BY SIZE INTO WS-EXCEPTIONS-PATH
           STRING FUNCTION TRIM(LR-OUT-DIR) "/control.txt"
               DELIMITED BY SIZE INTO WS-CONTROL-PATH
           STRING FUNCTION TRIM(LR-OUT-DIR) "/.work-transactions"
               DELIMITED BY SIZE INTO WS-WORK-TXNS-PATH
           STRING FUNCTION TRIM(LR-OUT-DIR) "/.work-entries"
               DELIMITED BY SIZE INTO WS-WORK-ENTRIES-PATH
           STRING FUNCTION TRIM(LR-OUT-DIR) "/.work-postings"
               DELIMITED BY SIZE INTO WS-WORK-POSTINGS-PATH
           MOVE LR-RUN-DATE TO WS-DATE-IN
           PERFORM FORMAT-DATE
           MOVE WS-DATE-TEXT TO WS-RUN-DATE-TEXT.

       ABORT-RUN.
           SET WS-ABORTED TO TRUE.

      *> ---------------------------------------------------------------
      *> Step 1: validate and sort the transactions.
      *> ---------------------------------------------------------------
       SORT-TRANSACTIONS.
           SORT TXN-SORT
               ON ASCENDING KEY TS-ACCT-NO TS-DATE TS-SEQ
               INPUT PROCEDURE IS VALIDATE-TRANSACTIONS
               GIVING WORK-TXNS.

       VALIDATE-TRANSACTIONS.
           OPEN INPUT TXN-IN
           IF WS-FS-TXN NOT = "00"
               STRING "CANNOT OPEN TRANSACTION FILE "
                      FUNCTION TRIM(LR-TXN-PATH)
                      DELIMITED BY SIZE INTO LS-MESSAGE
               PERFORM ABORT-RUN
               EXIT PARAGRAPH
           END-IF
           MOVE 0 TO WS-LINE-NO
           MOVE "N" TO WS-TXN-EOF-FLAG
           PERFORM UNTIL WS-TXN-EOF
               READ TXN-IN INTO TXN-RECORD
                   AT END
                       SET WS-TXN-EOF TO TRUE
                   NOT AT END
                       ADD 1 TO WS-LINE-NO
                       IF TXN-RECORD NOT = SPACES
                           ADD 1 TO CT-TXN-READ
                           PERFORM VALIDATE-TRANSACTION
                       END-IF
               END-READ
           END-PERFORM
           CLOSE TXN-IN.

       VALIDATE-TRANSACTION.
           MOVE SPACES TO WS-EX-CODE
           EVALUATE TRUE
               WHEN TX-ACCT-NO NOT NUMERIC
                   MOVE "E01" TO WS-EX-CODE
                   MOVE "ACCOUNT NUMBER NOT NUMERIC" TO WS-EX-REASON
               WHEN TX-DATE NOT NUMERIC
                   MOVE "E02" TO WS-EX-CODE
                   MOVE "INVALID DATE" TO WS-EX-REASON
               WHEN FUNCTION TEST-DATE-YYYYMMDD(TX-DATE) NOT = 0
                   MOVE "E02" TO WS-EX-CODE
                   MOVE "INVALID DATE" TO WS-EX-REASON
               WHEN NOT TX-VALID-TYPE
                   MOVE "E03" TO WS-EX-CODE
                   MOVE "UNKNOWN TRANSACTION TYPE" TO WS-EX-REASON
               WHEN TX-AMOUNT NOT NUMERIC
                   MOVE "E04" TO WS-EX-CODE
                   MOVE "INVALID AMOUNT" TO WS-EX-REASON
               WHEN TX-AMOUNT = 0
                   MOVE "E04" TO WS-EX-CODE
                   MOVE "INVALID AMOUNT" TO WS-EX-REASON
               WHEN TX-TRANSFER AND TX-TARGET NOT NUMERIC
                   MOVE "E05" TO WS-EX-CODE
                   MOVE "INVALID TRANSFER TARGET" TO WS-EX-REASON
               WHEN TX-TRANSFER AND TX-TARGET = TX-ACCT-NO
                   MOVE "E05" TO WS-EX-CODE
                   MOVE "TRANSFER TO SAME ACCOUNT" TO WS-EX-REASON
           END-EVALUATE

           IF WS-EX-CODE NOT = SPACES
               ADD 1 TO CT-REJECTED-FORMAT
      *>       The record failed validation, so report its raw text.
               MOVE WS-LINE-NO         TO WS-EX-LINE
               MOVE TXN-IN-REC(1:8)    TO WS-EX-ACCT
               MOVE TXN-IN-REC(9:8)    TO WS-EX-DATE
               MOVE TXN-IN-REC(17:1)   TO WS-EX-TYPE
               MOVE TXN-IN-REC(18:11)  TO WS-EX-AMOUNT
               PERFORM WRITE-EXCEPTION
               SET EV-INVALID TO TRUE
               MOVE TXN-IN-REC TO EV-RECORD
               PERFORM EMIT-EVENT
           ELSE
               MOVE TX-ACCT-NO TO EN-ACCT-NO
               MOVE TX-DATE    TO EN-DATE
               MOVE WS-LINE-NO TO EN-SEQ
               MOVE TX-TYPE    TO EN-LEG
               MOVE TX-AMOUNT  TO EN-AMOUNT
               MOVE TX-REF     TO EN-REF
               IF TX-TRANSFER
                   MOVE TX-TARGET TO EN-OTHER-ACCT
               ELSE
                   MOVE 0 TO EN-OTHER-ACCT
               END-IF
               RELEASE TS-RECORD FROM ENTRY-RECORD
           END-IF.

      *> ---------------------------------------------------------------
      *> Step 2: authorise transactions against the old master.
      *> ---------------------------------------------------------------
       AUTHORISE.
           OPEN INPUT MASTER-IN
           IF WS-FS-MASTER NOT = "00"
               STRING "CANNOT OPEN MASTER FILE "
                      FUNCTION TRIM(LR-MASTER-PATH)
                      DELIMITED BY SIZE INTO LS-MESSAGE
               PERFORM ABORT-RUN
               EXIT PARAGRAPH
           END-IF
           OPEN INPUT WORK-TXNS
           OPEN OUTPUT WORK-ENTRIES
           MOVE LOW-VALUES TO WS-PREV-MASTER-KEY
           MOVE 0 TO WS-MASTER-COUNT
           PERFORM READ-MASTER
           PERFORM READ-WORK-TXN
           PERFORM UNTIL WS-ABORTED
                   OR (WS-MASTER-KEY = HIGH-VALUES
                       AND WS-ENTRY-KEY = HIGH-VALUES)
               EVALUATE TRUE
                   WHEN WS-ENTRY-KEY < WS-MASTER-KEY
                       MOVE "E10" TO WS-EX-CODE
                       MOVE "ACCOUNT NOT FOUND" TO WS-EX-REASON
                       PERFORM REJECT-ENTRY
                       PERFORM READ-WORK-TXN
                   WHEN WS-ENTRY-KEY = WS-MASTER-KEY
                       PERFORM AUTHORISE-TRANSACTION
                       PERFORM READ-WORK-TXN
                   WHEN OTHER
                       PERFORM READ-MASTER
               END-EVALUATE
           END-PERFORM
           CLOSE MASTER-IN WORK-TXNS WORK-ENTRIES.

       AUTHORISE-TRANSACTION.
           EVALUATE TRUE
               WHEN AC-CLOSED
                   MOVE "E11" TO WS-EX-CODE
                   MOVE "ACCOUNT CLOSED" TO WS-EX-REASON
                   PERFORM REJECT-ENTRY
               WHEN EN-DEPOSIT
                   COMPUTE WS-NEW-BALANCE = WS-CUR-BALANCE + EN-AMOUNT
                   IF WS-NEW-BALANCE > WS-MAX-BALANCE
                       MOVE "E13" TO WS-EX-CODE
                       MOVE "BALANCE LIMIT EXCEEDED" TO WS-EX-REASON
                       PERFORM REJECT-ENTRY
                   ELSE
                       MOVE WS-NEW-BALANCE TO WS-CUR-BALANCE
                       PERFORM WRITE-ENTRY
                       ADD 1 TO CT-ACCEPTED
                   END-IF
               WHEN OTHER
                   COMPUTE WS-NEW-BALANCE = WS-CUR-BALANCE - EN-AMOUNT
                   IF WS-NEW-BALANCE < 0 - AC-OD-LIMIT
                       MOVE "E12" TO WS-EX-CODE
                       MOVE "INSUFFICIENT FUNDS" TO WS-EX-REASON
                       PERFORM REJECT-ENTRY
                   ELSE
                       MOVE WS-NEW-BALANCE TO WS-CUR-BALANCE
                       IF EN-TRANSFER
                           PERFORM WRITE-TRANSFER-LEGS
                       ELSE
                           PERFORM WRITE-ENTRY
                       END-IF
                       ADD 1 TO CT-ACCEPTED
                   END-IF
           END-EVALUATE.

       WRITE-TRANSFER-LEGS.
           SET EN-TRANSFER-OUT TO TRUE
           PERFORM WRITE-ENTRY
      *>   Swap the accounts round for the leg that lands on the target.
           MOVE EN-OTHER-ACCT TO WS-SWAP-ACCT
           MOVE EN-ACCT-NO    TO EN-OTHER-ACCT
           MOVE WS-SWAP-ACCT  TO EN-ACCT-NO
           SET EN-TRANSFER-IN TO TRUE
           PERFORM WRITE-ENTRY.

       WRITE-ENTRY.
           WRITE WORK-ENTRY-REC FROM ENTRY-RECORD
           ADD 1 TO CT-ENTRIES-WRITTEN.

       REJECT-ENTRY.
           ADD 1 TO CT-REJECTED-AUTH
           MOVE EN-SEQ     TO WS-EX-LINE
           MOVE EN-ACCT-NO TO WS-EX-ACCT
           MOVE EN-DATE    TO WS-EX-DATE
           MOVE EN-LEG     TO WS-EX-TYPE
           MOVE EN-AMOUNT  TO WS-EX-AMOUNT-N
           PERFORM WRITE-EXCEPTION
           SET EV-DECLINED TO TRUE
           PERFORM EMIT-EVENT.

       READ-WORK-TXN.
           READ WORK-TXNS INTO ENTRY-RECORD
               AT END MOVE HIGH-VALUES TO WS-ENTRY-KEY
               NOT AT END MOVE EN-ACCT-NO TO WS-ENTRY-KEY
           END-READ.

      *> Shared by both passes: read the next master record, checking
      *> that it is well formed and in ascending account order.
       READ-MASTER.
           READ MASTER-IN INTO ACCOUNT-RECORD
               AT END
                   MOVE HIGH-VALUES TO WS-MASTER-KEY
                   EXIT PARAGRAPH
           END-READ
           ADD 1 TO WS-MASTER-COUNT
           IF AC-ACCT-NO NOT NUMERIC
              OR NOT (AC-ACTIVE OR AC-CLOSED)
              OR AC-OD-LIMIT NOT NUMERIC
              OR AC-BALANCE NOT NUMERIC
               MOVE WS-MASTER-COUNT TO WS-ED-COUNT
               STRING "MASTER RECORD " FUNCTION TRIM(WS-ED-COUNT)
                      " IS INVALID"
                      DELIMITED BY SIZE INTO LS-MESSAGE
               PERFORM ABORT-RUN
               MOVE HIGH-VALUES TO WS-MASTER-KEY
               EXIT PARAGRAPH
           END-IF
           MOVE AC-ACCT-NO TO WS-MASTER-KEY
           IF WS-MASTER-KEY NOT > WS-PREV-MASTER-KEY
               MOVE WS-MASTER-COUNT TO WS-ED-COUNT
               STRING "MASTER RECORD " FUNCTION TRIM(WS-ED-COUNT)
                      " (ACCOUNT " AC-ACCT-NO ") IS OUT OF SEQUENCE"
                      DELIMITED BY SIZE INTO LS-MESSAGE
               PERFORM ABORT-RUN
               MOVE HIGH-VALUES TO WS-MASTER-KEY
               EXIT PARAGRAPH
           END-IF
           MOVE WS-MASTER-KEY TO WS-PREV-MASTER-KEY
           MOVE AC-BALANCE TO WS-CUR-BALANCE.

      *> ---------------------------------------------------------------
      *> Step 4: post authorised entries, write the new master and the
      *> statements.
      *> ---------------------------------------------------------------
       POST.
           OPEN INPUT MASTER-IN
           OPEN INPUT WORK-POSTINGS
           OPEN OUTPUT MASTER-OUT
           OPEN OUTPUT STATEMENTS
           IF WS-FS-MASTER NOT = "00" OR WS-FS-NEW-MASTER NOT = "00"
              OR WS-FS-STATEMENTS NOT = "00"
               MOVE "CANNOT OPEN FILES FOR POSTING" TO LS-MESSAGE
               PERFORM ABORT-RUN
               EXIT PARAGRAPH
           END-IF
           MOVE LOW-VALUES TO WS-PREV-MASTER-KEY
           MOVE 0 TO WS-MASTER-COUNT
           SET WS-STATEMENT-CLOSED TO TRUE
           PERFORM READ-MASTER-FOR-POSTING
           PERFORM READ-POSTING
           PERFORM UNTIL WS-ABORTED
                   OR (WS-MASTER-KEY = HIGH-VALUES
                       AND WS-ENTRY-KEY = HIGH-VALUES)
               EVALUATE TRUE
                   WHEN WS-ENTRY-KEY < WS-MASTER-KEY
      *>               Only an in leg can reach an unknown account:
      *>               everything else was checked in AUTHORISE.
                       MOVE "E20" TO WS-EX-CODE
                       PERFORM HOLD-IN-SUSPENSE
                       PERFORM READ-POSTING
                   WHEN WS-ENTRY-KEY = WS-MASTER-KEY
                       PERFORM POST-ENTRY
                       PERFORM READ-POSTING
                   WHEN OTHER
                       PERFORM FINISH-ACCOUNT
                       PERFORM READ-MASTER-FOR-POSTING
               END-EVALUATE
           END-PERFORM
           CLOSE MASTER-IN WORK-POSTINGS MASTER-OUT STATEMENTS.

       READ-MASTER-FOR-POSTING.
           PERFORM READ-MASTER
           IF WS-MASTER-KEY NOT = HIGH-VALUES
               ADD 1 TO CT-MASTER-RECORDS
               ADD AC-BALANCE TO TT-OPENING
           END-IF.

       READ-POSTING.
           READ WORK-POSTINGS INTO ENTRY-RECORD
               AT END MOVE HIGH-VALUES TO WS-ENTRY-KEY
               NOT AT END
                   MOVE EN-ACCT-NO TO WS-ENTRY-KEY
                   ADD 1 TO CT-ENTRIES-READ
           END-READ.

       POST-ENTRY.
           IF AC-CLOSED
               MOVE "E21" TO WS-EX-CODE
               PERFORM HOLD-IN-SUSPENSE
               EXIT PARAGRAPH
           END-IF
           IF EN-DEPOSIT OR EN-TRANSFER-IN
               COMPUTE WS-NEW-BALANCE = WS-CUR-BALANCE + EN-AMOUNT
               MOVE EN-AMOUNT TO WS-SIGNED-AMOUNT
           ELSE
               COMPUTE WS-NEW-BALANCE = WS-CUR-BALANCE - EN-AMOUNT
               COMPUTE WS-SIGNED-AMOUNT = 0 - EN-AMOUNT
           END-IF
           IF WS-NEW-BALANCE > WS-MAX-BALANCE
               IF EN-TRANSFER-IN
                   MOVE "E22" TO WS-EX-CODE
                   PERFORM HOLD-IN-SUSPENSE
               ELSE
      *>           Authorisation checked deposits against this limit
      *>           before any in legs were merged in.
                   STRING "BALANCE LIMIT EXCEEDED POSTING ACCOUNT "
                          EN-ACCT-NO
                          DELIMITED BY SIZE INTO LS-MESSAGE
                   PERFORM ABORT-RUN
               END-IF
               EXIT PARAGRAPH
           END-IF

           IF WS-STATEMENT-CLOSED
               PERFORM START-STATEMENT
           END-IF
           MOVE WS-NEW-BALANCE TO WS-CUR-BALANCE
           EVALUATE TRUE
               WHEN EN-DEPOSIT      ADD EN-AMOUNT TO TT-DEPOSITS
               WHEN EN-WITHDRAWAL   ADD EN-AMOUNT TO TT-WITHDRAWALS
               WHEN EN-TRANSFER-OUT ADD EN-AMOUNT TO TT-TRANSFERS-OUT
               WHEN EN-TRANSFER-IN  ADD EN-AMOUNT TO TT-TRANSFERS-IN
           END-EVALUATE
           PERFORM WRITE-STATEMENT-LINE
           SET EV-POSTED TO TRUE
           MOVE WS-CUR-BALANCE TO EV-BALANCE
           PERFORM EMIT-EVENT.

      *> The money has left the source account but cannot be credited.
       HOLD-IN-SUSPENSE.
           ADD 1 TO CT-SUSPENSE
           ADD EN-AMOUNT TO TT-SUSPENSE
           MOVE EN-SEQ        TO WS-EX-LINE
           MOVE EN-OTHER-ACCT TO WS-EX-ACCT
           MOVE EN-DATE       TO WS-EX-DATE
           MOVE "T"           TO WS-EX-TYPE
           MOVE EN-AMOUNT     TO WS-EX-AMOUNT-N
           MOVE SPACES        TO WS-EX-REASON
           EVALUATE WS-EX-CODE
               WHEN "E20"
                   STRING "TARGET " EN-ACCT-NO " NOT FOUND - IN SUSPENSE"
                       DELIMITED BY SIZE INTO WS-EX-REASON
               WHEN "E21"
                   STRING "TARGET " EN-ACCT-NO " CLOSED - IN SUSPENSE"
                       DELIMITED BY SIZE INTO WS-EX-REASON
               WHEN "E22"
                   STRING "TARGET " EN-ACCT-NO " AT LIMIT - IN SUSPENSE"
                       DELIMITED BY SIZE INTO WS-EX-REASON
           END-EVALUATE
           PERFORM WRITE-EXCEPTION
           SET EV-SUSPENDED TO TRUE
           PERFORM EMIT-EVENT.

       FINISH-ACCOUNT.
           IF WS-STATEMENT-OPEN
               MOVE SPACES TO STMT-DETAIL
               MOVE "CLOSING BALANCE" TO SL-DETAILS
               MOVE WS-CUR-BALANCE TO SL-BALANCE
               WRITE STATEMENT-REC FROM STMT-DETAIL
               SET WS-STATEMENT-CLOSED TO TRUE
           END-IF
           MOVE WS-CUR-BALANCE TO AC-BALANCE
           WRITE MASTER-OUT-REC FROM ACCOUNT-RECORD
           ADD WS-CUR-BALANCE TO TT-CLOSING.

       START-STATEMENT.
           IF CT-STATEMENTS > 0
               MOVE SPACES TO STATEMENT-REC
               WRITE STATEMENT-REC
           END-IF
           ADD 1 TO CT-STATEMENTS
           WRITE STATEMENT-REC FROM WS-RULE-EQ
           MOVE "STATEMENT OF ACCOUNT" TO WS-TITLE-LINE
           STRING "RUN DATE " WS-RUN-DATE-TEXT
               DELIMITED BY SIZE INTO WS-TITLE-LINE(74:19)
           WRITE STATEMENT-REC FROM WS-TITLE-LINE
           MOVE SPACES TO WS-TITLE-LINE
           STRING "ACCOUNT " AC-ACCT-NO "  " AC-NAME
               DELIMITED BY SIZE INTO WS-TITLE-LINE
           WRITE STATEMENT-REC FROM WS-TITLE-LINE
           WRITE STATEMENT-REC FROM WS-RULE-DASH
           WRITE STATEMENT-REC FROM STMT-COLUMNS
           MOVE SPACES TO STMT-DETAIL
           MOVE "OPENING BALANCE" TO SL-DETAILS
           MOVE AC-BALANCE TO SL-BALANCE
           WRITE STATEMENT-REC FROM STMT-DETAIL
           SET WS-STATEMENT-OPEN TO TRUE.

       WRITE-STATEMENT-LINE.
           MOVE SPACES TO STMT-DETAIL
           MOVE EN-DATE TO WS-DATE-IN
           PERFORM FORMAT-DATE
           MOVE WS-DATE-TEXT TO SL-DATE
           EVALUATE TRUE
               WHEN EN-DEPOSIT
                   MOVE "DEPOSIT" TO SL-DETAILS
               WHEN EN-WITHDRAWAL
                   MOVE "WITHDRAWAL" TO SL-DETAILS
               WHEN EN-TRANSFER-OUT
                   STRING "TRANSFER TO " EN-OTHER-ACCT
                       DELIMITED BY SIZE INTO SL-DETAILS
               WHEN EN-TRANSFER-IN
                   STRING "TRANSFER FROM " EN-OTHER-ACCT
                       DELIMITED BY SIZE INTO SL-DETAILS
           END-EVALUATE
           MOVE EN-REF TO SL-REF
           MOVE WS-SIGNED-AMOUNT TO WS-ED-SIGNED
           MOVE WS-ED-SIGNED TO SL-AMOUNT
           MOVE WS-CUR-BALANCE TO SL-BALANCE
           WRITE STATEMENT-REC FROM STMT-DETAIL.

      *> ---------------------------------------------------------------
      *> Control totals. Transfers must net to zero once suspense is
      *> counted, and the closing ledger must equal the opening ledger
      *> moved by every posted amount.
      *> ---------------------------------------------------------------
       RECONCILE.
           COMPUTE TT-EXPECTED = TT-OPENING + TT-DEPOSITS - TT-WITHDRAWALS
                               - TT-TRANSFERS-OUT + TT-TRANSFERS-IN
           IF TT-CLOSING = TT-EXPECTED
              AND TT-TRANSFERS-OUT = TT-TRANSFERS-IN + TT-SUSPENSE
              AND CT-ENTRIES-READ = CT-ENTRIES-WRITTEN
               SET WS-BALANCED TO TRUE
           ELSE
               MOVE "CONTROL TOTALS OUT OF BALANCE" TO LS-MESSAGE
               PERFORM ABORT-RUN
           END-IF.

       WRITE-CONTROL-REPORT.
           OPEN OUTPUT CONTROL-RPT
           IF WS-FS-CONTROL NOT = "00"
               EXIT PARAGRAPH
           END-IF
           MOVE SPACES TO CONTROL-REC
           STRING "LEDGER BATCH RUN - CONTROL REPORT"
               DELIMITED BY SIZE INTO CONTROL-REC
           STRING "RUN DATE " WS-RUN-DATE-TEXT
               DELIMITED BY SIZE INTO CONTROL-REC(62:19)
           WRITE CONTROL-REC
           MOVE ALL "=" TO CONTROL-REC
           WRITE CONTROL-REC

           IF WS-ABORTED
               MOVE "RUN ABORTED" TO CONTROL-REC
               WRITE CONTROL-REC
               MOVE LS-MESSAGE TO CONTROL-REC
               WRITE CONTROL-REC
               CLOSE CONTROL-RPT
               EXIT PARAGRAPH
           END-IF

           MOVE "TRANSACTIONS" TO CONTROL-REC
           WRITE CONTROL-REC
           MOVE "  RECORDS READ" TO CL-LABEL
           MOVE CT-TXN-READ TO WS-ED-COUNT
           PERFORM WRITE-CONTROL-COUNT
           MOVE "  REJECTED - INVALID RECORD" TO CL-LABEL
           MOVE CT-REJECTED-FORMAT TO WS-ED-COUNT
           PERFORM WRITE-CONTROL-COUNT
           MOVE "  REJECTED - NOT AUTHORISED" TO CL-LABEL
           MOVE CT-REJECTED-AUTH TO WS-ED-COUNT
           PERFORM WRITE-CONTROL-COUNT
           MOVE "  ACCEPTED" TO CL-LABEL
           MOVE CT-ACCEPTED TO WS-ED-COUNT
           PERFORM WRITE-CONTROL-COUNT
           MOVE "  TRANSFERS HELD IN SUSPENSE" TO CL-LABEL
           MOVE CT-SUSPENSE TO WS-ED-COUNT
           PERFORM WRITE-CONTROL-COUNT

           MOVE "ACCOUNTS" TO CONTROL-REC
           WRITE CONTROL-REC
           MOVE "  MASTER RECORDS" TO CL-LABEL
           MOVE CT-MASTER-RECORDS TO WS-ED-COUNT
           PERFORM WRITE-CONTROL-COUNT
           MOVE "  STATEMENTS PRODUCED" TO CL-LABEL
           MOVE CT-STATEMENTS TO WS-ED-COUNT
           PERFORM WRITE-CONTROL-COUNT

           MOVE "AMOUNTS" TO CONTROL-REC
           WRITE CONTROL-REC
           MOVE "  DEPOSITS" TO CL-LABEL
           MOVE TT-DEPOSITS TO WS-ED-TOTAL
           PERFORM WRITE-CONTROL-TOTAL
           MOVE "  WITHDRAWALS" TO CL-LABEL
           MOVE TT-WITHDRAWALS TO WS-ED-TOTAL
           PERFORM WRITE-CONTROL-TOTAL
           MOVE "  TRANSFERS OUT" TO CL-LABEL
           MOVE TT-TRANSFERS-OUT TO WS-ED-TOTAL
           PERFORM WRITE-CONTROL-TOTAL
           MOVE "  TRANSFERS IN" TO CL-LABEL
           MOVE TT-TRANSFERS-IN TO WS-ED-TOTAL
           PERFORM WRITE-CONTROL-TOTAL
           MOVE "  HELD IN SUSPENSE" TO CL-LABEL
           MOVE TT-SUSPENSE TO WS-ED-TOTAL
           PERFORM WRITE-CONTROL-TOTAL

           MOVE "LEDGER" TO CONTROL-REC
           WRITE CONTROL-REC
           MOVE "  OPENING TOTAL" TO CL-LABEL
           MOVE TT-OPENING TO WS-ED-TOTAL
           PERFORM WRITE-CONTROL-TOTAL
           MOVE "  EXPECTED CLOSING TOTAL" TO CL-LABEL
           MOVE TT-EXPECTED TO WS-ED-TOTAL
           PERFORM WRITE-CONTROL-TOTAL
           MOVE "  CLOSING TOTAL" TO CL-LABEL
           MOVE TT-CLOSING TO WS-ED-TOTAL
           PERFORM WRITE-CONTROL-TOTAL

           MOVE ALL "=" TO CONTROL-REC
           WRITE CONTROL-REC
           MOVE "LEDGER BALANCED" TO CONTROL-REC
           WRITE CONTROL-REC
           CLOSE CONTROL-RPT.

       WRITE-CONTROL-COUNT.
           MOVE WS-ED-COUNT TO CL-VALUE
           WRITE CONTROL-REC FROM CTL-LINE.

       WRITE-CONTROL-TOTAL.
           MOVE WS-ED-TOTAL TO CL-VALUE
           WRITE CONTROL-REC FROM CTL-LINE.

      *> ---------------------------------------------------------------
      *> Exceptions report.
      *> ---------------------------------------------------------------
       WRITE-EXCEPTION-HEADING.
           MOVE SPACES TO EXCEPTION-REC
           STRING "LEDGER EXCEPTIONS REPORT"
               DELIMITED BY SIZE INTO EXCEPTION-REC
           STRING "RUN DATE " WS-RUN-DATE-TEXT
               DELIMITED BY SIZE INTO EXCEPTION-REC(92:19)
           WRITE EXCEPTION-REC
           MOVE SPACES TO EXCEPTION-REC
           WRITE EXCEPTION-REC
           WRITE EXCEPTION-REC FROM EXC-HEADING
           WRITE EXCEPTION-REC FROM EXC-RULE.

       WRITE-EXCEPTION.
           ADD 1 TO CT-EXCEPTIONS
           MOVE WS-EX-LINE TO ED-LINE
           MOVE WS-EX-ACCT TO ED-ACCT
           IF WS-EX-DATE IS NUMERIC
               MOVE WS-EX-DATE TO WS-DATE-IN
               PERFORM FORMAT-DATE
               MOVE WS-DATE-TEXT TO ED-DATE
           ELSE
               MOVE WS-EX-DATE TO ED-DATE
           END-IF
           EVALUATE WS-EX-TYPE
               WHEN "D"   MOVE "DEP"  TO ED-TYPE
               WHEN "W"   MOVE "WDL"  TO ED-TYPE
               WHEN "T"   MOVE "XFER" TO ED-TYPE
               WHEN OTHER MOVE WS-EX-TYPE TO ED-TYPE
           END-EVALUATE
           IF WS-EX-AMOUNT IS NUMERIC
               MOVE WS-EX-AMOUNT-N TO WS-ED-AMOUNT
               MOVE WS-ED-AMOUNT TO ED-AMOUNT
           ELSE
               MOVE WS-EX-AMOUNT TO ED-AMOUNT
           END-IF
           MOVE WS-EX-CODE TO ED-CODE
           MOVE WS-EX-REASON TO ED-REASON
           WRITE EXCEPTION-REC FROM EXC-DETAIL.

       WRITE-EXCEPTION-TRAILER.
           MOVE SPACES TO EXCEPTION-REC
           WRITE EXCEPTION-REC
           MOVE CT-EXCEPTIONS TO WS-ED-COUNT
           IF CT-EXCEPTIONS = 0
               MOVE "NO EXCEPTIONS" TO EXCEPTION-REC
           ELSE
               STRING FUNCTION TRIM(WS-ED-COUNT) " EXCEPTION(S)"
                   DELIMITED BY SIZE INTO EXCEPTION-REC
           END-IF
           WRITE EXCEPTION-REC
           IF WS-ABORTED
               MOVE "RUN ABORTED - REPORT IS INCOMPLETE" TO EXCEPTION-REC
               WRITE EXCEPTION-REC
           END-IF.

      *> ---------------------------------------------------------------
      *> Events: LEDGEVT holds them until the run is committed or aborted.
      *> ---------------------------------------------------------------
       BEGIN-EVENTS.
           SET EV-BEGIN TO TRUE
           MOVE LR-OUT-DIR TO EV-OUT-DIR
           MOVE LR-RUN-DATE TO EV-RUN-DATE
           CALL "LEDGEVT" USING EVENT-REQUEST
           IF EV-STATUS NOT = "00"
               MOVE "CANNOT WRITE EVENTS" TO LS-MESSAGE
               PERFORM ABORT-RUN
           END-IF.

      *> Describes the current entry, or for INVALID the raw record, with
      *> the exception fields WRITE-EXCEPTION just reported.
       EMIT-EVENT.
           SET EV-EMIT TO TRUE
           MOVE WS-EX-LINE    TO EV-LINE
           MOVE WS-EX-CODE    TO EV-CODE
           MOVE WS-EX-REASON  TO EV-REASON
           IF EV-POSTED
               MOVE EN-SEQ    TO EV-LINE
           END-IF
           MOVE EN-ACCT-NO    TO EV-ACCT-NO
           MOVE EN-DATE       TO EV-DATE
           MOVE EN-LEG        TO EV-LEG
           MOVE EN-AMOUNT     TO EV-AMOUNT
           MOVE EN-OTHER-ACCT TO EV-OTHER-ACCT
           MOVE EN-REF        TO EV-REF
           CALL "LEDGEVT" USING EVENT-REQUEST.

       COMMIT-EVENTS.
           SET EV-COMMIT TO TRUE
           MOVE CT-TXN-READ        TO EV-CT-READ
           MOVE CT-REJECTED-FORMAT TO EV-CT-INVALID
           MOVE CT-REJECTED-AUTH   TO EV-CT-DECLINED
           MOVE CT-ACCEPTED        TO EV-CT-ACCEPTED
           MOVE CT-SUSPENSE        TO EV-CT-SUSPENDED
           MOVE CT-MASTER-RECORDS  TO EV-CT-ACCOUNTS
           MOVE CT-STATEMENTS      TO EV-CT-STATEMENTS
           MOVE TT-OPENING         TO EV-TT-OPENING
           MOVE TT-DEPOSITS        TO EV-TT-DEPOSITS
           MOVE TT-WITHDRAWALS     TO EV-TT-WITHDRAWALS
           MOVE TT-TRANSFERS-OUT   TO EV-TT-TRANSFERS-OUT
           MOVE TT-TRANSFERS-IN    TO EV-TT-TRANSFERS-IN
           MOVE TT-SUSPENSE        TO EV-TT-SUSPENSE
           MOVE TT-CLOSING         TO EV-TT-CLOSING
           CALL "LEDGEVT" USING EVENT-REQUEST
           IF EV-STATUS NOT = "00"
               MOVE "CANNOT WRITE EVENTS" TO LS-MESSAGE
               PERFORM ABORT-RUN
           END-IF.

       ABORT-EVENTS.
           SET EV-ABORT TO TRUE
           MOVE LS-MESSAGE TO EV-MESSAGE
           CALL "LEDGEVT" USING EVENT-REQUEST.

      *> YYYYMMDD in WS-DATE-IN to YYYY-MM-DD in WS-DATE-TEXT.
       FORMAT-DATE.
           MOVE SPACES TO WS-DATE-TEXT
           STRING WS-DATE-IN(1:4) "-" WS-DATE-IN(5:2) "-" WS-DATE-IN(7:2)
               DELIMITED BY SIZE INTO WS-DATE-TEXT.

       DELETE-WORK-FILES.
           CALL "CBL_DELETE_FILE" USING WS-WORK-TXNS-PATH
           CALL "CBL_DELETE_FILE" USING WS-WORK-ENTRIES-PATH
           CALL "CBL_DELETE_FILE" USING WS-WORK-POSTINGS-PATH.

       END PROGRAM LEDGRUN.
