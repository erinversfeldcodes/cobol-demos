       IDENTIFICATION DIVISION.
       PROGRAM-ID. LEDGEVT.
      *> Event outbox for LEDGRUN. Writes events.jsonl in the output
      *> directory: one CloudEvents 1.0 JSON object per line, telling
      *> other systems what the batch did without them diffing files.
      *>
      *>   BEGIN   open the outbox for a run
      *>   EMIT    record one event in the outbox's work file
      *>   COMMIT  publish: copy every event to events.jsonl, then a
      *>           final run.completed carrying the control totals
      *>   ABORT   publish only run.aborted, discarding everything else,
      *>           so a consumer never acts on half a run
      *>
      *> Events are deterministic: ids number the run date's events in
      *> order, and time is the run date, not the clock. Rerunning a
      *> date reproduces the same ids, which consumers must treat as a
      *> replacement for that date's run.
      *>
      *> COBOL codes become meaningful values here, at the boundary:
      *> leg "O" is "transfer_out", E12 is "insufficient_funds", and
      *> amounts are exact decimal strings rather than implied decimals.

       ENVIRONMENT DIVISION.
       INPUT-OUTPUT SECTION.
       FILE-CONTROL.
           SELECT WORK-EVENTS   ASSIGN TO WS-WORK-PATH
               ORGANIZATION IS LINE SEQUENTIAL
               FILE STATUS IS WS-FS.
           SELECT EVENTS-OUT    ASSIGN TO WS-EVENTS-PATH
               ORGANIZATION IS LINE SEQUENTIAL
               FILE STATUS IS WS-FS.

       DATA DIVISION.
       FILE SECTION.
       FD  WORK-EVENTS
           RECORD IS VARYING IN SIZE FROM 1 TO 2048 CHARACTERS
               DEPENDING ON WS-EVENT-LENGTH.
       01  WORK-EVENT-REC              PIC X(2048).
       FD  EVENTS-OUT
           RECORD IS VARYING IN SIZE FROM 1 TO 2048 CHARACTERS
               DEPENDING ON WS-EVENT-LENGTH.
       01  EVENT-OUT-REC               PIC X(2048).

       WORKING-STORAGE SECTION.
       01  WS-FS                       PIC XX.
       01  WS-WORK-PATH                PIC X(300).
       01  WS-EVENTS-PATH              PIC X(300).
       01  WS-RUN-DATE-TEXT            PIC X(10).
       01  WS-SEQ                      PIC 9(7).
       01  WS-EOF-FLAG                 PIC X.
           88  WS-EOF                            VALUE "Y".

       01  WS-EVENT                    PIC X(2048).
       01  WS-EVENT-LENGTH             PIC 9(4).
       01  WS-JSON                     PIC X(2048).
       01  WS-JSON-LENGTH              PIC 9(4).
       01  WS-DATA                     PIC X(2048).
       01  WS-DATA-LENGTH              PIC 9(4).
       01  WS-TYPE-PREFIX              PIC X(40)
           VALUE "io.github.erinversfeldcodes.cobol-demos.".

       01  WS-ED-AMOUNT                PIC Z(8)9.99.
       01  WS-ED-SIGNED                PIC -(9)9.99.
       01  WS-ED-TOTAL                 PIC -(12)9.99.
       01  WS-ED-ACCT                  PIC 9(8).
       01  WS-ED-LINE                  PIC Z(6)9.

      *> CloudEvents envelope. The data member is joined on afterwards,
      *> because each event type has its own data shape.
       01  JE-ENVELOPE.
           05  JE-SPECVERSION          PIC X(3)  VALUE "1.0".
           05  JE-ID                   PIC X(16).
           05  JE-SOURCE               PIC X(19) VALUE "/cobol-demos/ledger".
           05  JE-TYPE                 PIC X(80).
           05  JE-SUBJECT              PIC X(24).
           05  JE-TIME                 PIC X(20).
           05  JE-CONTENT-TYPE         PIC X(16) VALUE "application/json".

      *> The data of each event type, named in its JSON GENERATE.
       01  JD-POSTED.
           05  JP-ACCOUNT              PIC X(8).
           05  JP-KIND                 PIC X(12).
           05  JP-AMOUNT               PIC X(12).
           05  JP-BALANCE              PIC X(13).
           05  JP-COUNTERPARTY         PIC X(8).
           05  JP-REFERENCE            PIC X(20).
           05  JP-DATE                 PIC X(10).
           05  JP-LINE                 PIC 9(7).
       01  JD-INVALID.
           05  JI-LINE                 PIC 9(7).
           05  JI-CODE                 PIC X(3).
           05  JI-REASON               PIC X(24).
           05  JI-MESSAGE              PIC X(40).
           05  JI-RECORD               PIC X(56).
       01  JD-SUSPENDED.
           05  JS-FROM                 PIC X(8).
           05  JS-TO                   PIC X(8).
           05  JS-AMOUNT               PIC X(12).
           05  JS-REFERENCE            PIC X(20).
           05  JS-DATE                 PIC X(10).
           05  JS-LINE                 PIC 9(7).
           05  JS-CODE                 PIC X(3).
           05  JS-REASON               PIC X(24).
           05  JS-MESSAGE              PIC X(40).
       01  JD-COMPLETED.
           05  JC-RUN-DATE             PIC X(10).
           05  JC-RESULT               PIC X(8)  VALUE "balanced".
           05  JC-COUNTS.
               10  JC-READ             PIC 9(7).
               10  JC-INVALID          PIC 9(7).
               10  JC-DECLINED         PIC 9(7).
               10  JC-ACCEPTED         PIC 9(7).
               10  JC-SUSPENDED        PIC 9(7).
               10  JC-ACCOUNTS         PIC 9(7).
               10  JC-STATEMENTS       PIC 9(7).
               10  JC-EVENTS           PIC 9(7).
           05  JC-TOTALS.
               10  JC-OPENING          PIC X(17).
               10  JC-DEPOSITS         PIC X(17).
               10  JC-WITHDRAWALS      PIC X(17).
               10  JC-TRANSFERS-OUT    PIC X(17).
               10  JC-TRANSFERS-IN     PIC X(17).
               10  JC-SUSPENSE         PIC X(17).
               10  JC-CLOSING          PIC X(17).
       01  JD-ABORTED.
           05  JA-RUN-DATE             PIC X(10).
           05  JA-MESSAGE              PIC X(120).

       LINKAGE SECTION.
       COPY "eventreq.cpy".

       PROCEDURE DIVISION USING EVENT-REQUEST.
       MAIN-PROCEDURE.
           MOVE "00" TO EV-STATUS
           EVALUATE TRUE
               WHEN EV-BEGIN   PERFORM BEGIN-RUN
               WHEN EV-EMIT    PERFORM EMIT-EVENT
               WHEN EV-COMMIT  PERFORM COMMIT-RUN
               WHEN EV-ABORT   PERFORM ABORT-RUN
           END-EVALUATE
           GOBACK.

       BEGIN-RUN.
           MOVE SPACES TO WS-WORK-PATH WS-EVENTS-PATH
           STRING FUNCTION TRIM(EV-OUT-DIR) "/.work-events"
               DELIMITED BY SIZE INTO WS-WORK-PATH
           STRING FUNCTION TRIM(EV-OUT-DIR) "/events.jsonl"
               DELIMITED BY SIZE INTO WS-EVENTS-PATH
           STRING EV-RUN-DATE(1:4) "-" EV-RUN-DATE(5:2) "-" EV-RUN-DATE(7:2)
               DELIMITED BY SIZE INTO WS-RUN-DATE-TEXT
           MOVE SPACES TO JE-TIME
           STRING WS-RUN-DATE-TEXT "T00:00:00Z"
               DELIMITED BY SIZE INTO JE-TIME
           MOVE 0 TO WS-SEQ
           OPEN OUTPUT WORK-EVENTS
           MOVE WS-FS TO EV-STATUS.

       EMIT-EVENT.
           EVALUATE TRUE
               WHEN EV-POSTED     PERFORM BUILD-POSTED
               WHEN EV-INVALID    PERFORM BUILD-INVALID
               WHEN EV-DECLINED   PERFORM BUILD-DECLINED
               WHEN EV-SUSPENDED  PERFORM BUILD-SUSPENDED
           END-EVALUATE
           PERFORM JOIN-EVENT
           WRITE WORK-EVENT-REC FROM WS-EVENT
           MOVE WS-FS TO EV-STATUS.

       COMMIT-RUN.
           CLOSE WORK-EVENTS
           OPEN INPUT WORK-EVENTS
           OPEN OUTPUT EVENTS-OUT
           MOVE "N" TO WS-EOF-FLAG
           PERFORM UNTIL WS-EOF
               READ WORK-EVENTS
                   AT END SET WS-EOF TO TRUE
                   NOT AT END WRITE EVENT-OUT-REC FROM WORK-EVENT-REC
               END-READ
           END-PERFORM
           CLOSE WORK-EVENTS
           PERFORM BUILD-COMPLETED
           PERFORM JOIN-EVENT
           WRITE EVENT-OUT-REC FROM WS-EVENT
           MOVE WS-FS TO EV-STATUS
           CLOSE EVENTS-OUT
           CALL "CBL_DELETE_FILE" USING WS-WORK-PATH.

       ABORT-RUN.
           CLOSE WORK-EVENTS
           CALL "CBL_DELETE_FILE" USING WS-WORK-PATH
           OPEN OUTPUT EVENTS-OUT
           MOVE 0 TO WS-SEQ
           MOVE "run.aborted" TO JE-TYPE
           PERFORM SET-RUN-SUBJECT
           MOVE WS-RUN-DATE-TEXT TO JA-RUN-DATE
           MOVE EV-MESSAGE TO JA-MESSAGE
           JSON GENERATE WS-DATA FROM JD-ABORTED
               COUNT IN WS-DATA-LENGTH
               NAME OF JD-ABORTED IS OMITTED
                       JA-RUN-DATE IS "runDate"
                       JA-MESSAGE IS "message"
               ON EXCEPTION MOVE "JG" TO EV-STATUS
           END-JSON
           PERFORM JOIN-EVENT
           WRITE EVENT-OUT-REC FROM WS-EVENT
           CLOSE EVENTS-OUT.

      *> ---------------------------------------------------------------
      *> One data object per event type.
      *> ---------------------------------------------------------------
       BUILD-POSTED.
           MOVE "entry.posted" TO JE-TYPE
           PERFORM SET-ACCOUNT-SUBJECT
           MOVE EV-ACCT-NO TO JP-ACCOUNT
           PERFORM NAME-LEG
           MOVE EV-AMOUNT TO WS-ED-AMOUNT
           MOVE FUNCTION TRIM(WS-ED-AMOUNT) TO JP-AMOUNT
           MOVE EV-BALANCE TO WS-ED-SIGNED
           MOVE FUNCTION TRIM(WS-ED-SIGNED) TO JP-BALANCE
           MOVE EV-OTHER-ACCT TO JP-COUNTERPARTY
           MOVE EV-REF TO JP-REFERENCE
           PERFORM FORMAT-ENTRY-DATE
           MOVE EV-LINE TO JP-LINE
      *>   Only transfer legs have a counterparty. JSON GENERATE has no
      *>   conditional fields, so each shape is its own statement.
           IF EV-LEG = "O" OR EV-LEG = "I"
               JSON GENERATE WS-DATA FROM JD-POSTED
                   COUNT IN WS-DATA-LENGTH
                   NAME OF JD-POSTED IS OMITTED
                           JP-ACCOUNT IS "account"
                           JP-KIND IS "kind"
                           JP-AMOUNT IS "amount"
                           JP-BALANCE IS "balance"
                           JP-COUNTERPARTY IS "counterparty"
                           JP-REFERENCE IS "reference"
                           JP-DATE IS "date"
                           JP-LINE IS "line"
                   ON EXCEPTION MOVE "JG" TO EV-STATUS
               END-JSON
           ELSE
               JSON GENERATE WS-DATA FROM JD-POSTED
                   COUNT IN WS-DATA-LENGTH
                   NAME OF JD-POSTED IS OMITTED
                           JP-ACCOUNT IS "account"
                           JP-KIND IS "kind"
                           JP-AMOUNT IS "amount"
                           JP-BALANCE IS "balance"
                           JP-REFERENCE IS "reference"
                           JP-DATE IS "date"
                           JP-LINE IS "line"
                   SUPPRESS JP-COUNTERPARTY
                   ON EXCEPTION MOVE "JG" TO EV-STATUS
               END-JSON
           END-IF.

      *> A record that failed validation: its fields can't be trusted, so
      *> it is reported as the text that was read.
       BUILD-INVALID.
           MOVE "transaction.invalid" TO JE-TYPE
           MOVE EV-LINE TO WS-ED-LINE
           MOVE SPACES TO JE-SUBJECT
           STRING "lines/" FUNCTION TRIM(WS-ED-LINE)
               DELIMITED BY SIZE INTO JE-SUBJECT
           MOVE EV-LINE TO JI-LINE
           MOVE EV-CODE TO JI-CODE
           PERFORM NAME-REASON
           MOVE EV-REASON TO JI-MESSAGE
           MOVE EV-RECORD TO JI-RECORD
           JSON GENERATE WS-DATA FROM JD-INVALID
               COUNT IN WS-DATA-LENGTH
               NAME OF JD-INVALID IS OMITTED
                       JI-LINE IS "line"
                       JI-CODE IS "code"
                       JI-REASON IS "reason"
                       JI-MESSAGE IS "message"
                       JI-RECORD IS "record"
               ON EXCEPTION MOVE "JG" TO EV-STATUS
           END-JSON.

      *> Declined transactions share the posted shape, less the balance.
       BUILD-DECLINED.
           MOVE "transaction.declined" TO JE-TYPE
           PERFORM SET-ACCOUNT-SUBJECT
           MOVE EV-ACCT-NO TO JP-ACCOUNT
           PERFORM NAME-LEG
           MOVE EV-AMOUNT TO WS-ED-AMOUNT
           MOVE FUNCTION TRIM(WS-ED-AMOUNT) TO JP-AMOUNT
           MOVE EV-OTHER-ACCT TO JP-COUNTERPARTY
           MOVE EV-REF TO JP-REFERENCE
           PERFORM FORMAT-ENTRY-DATE
           MOVE EV-LINE TO JI-LINE
           MOVE EV-CODE TO JI-CODE
           PERFORM NAME-REASON
           MOVE EV-REASON TO JI-MESSAGE
           JSON GENERATE WS-JSON FROM JD-INVALID
               COUNT IN WS-JSON-LENGTH
               NAME OF JD-INVALID IS OMITTED
                       JI-LINE IS "line"
                       JI-CODE IS "code"
                       JI-REASON IS "reason"
                       JI-MESSAGE IS "message"
               SUPPRESS JI-RECORD
               ON EXCEPTION MOVE "JG" TO EV-STATUS
           END-JSON
           IF EV-LEG = "T"
               JSON GENERATE WS-DATA FROM JD-POSTED
                   COUNT IN WS-DATA-LENGTH
                   NAME OF JD-POSTED IS OMITTED
                           JP-ACCOUNT IS "account"
                           JP-KIND IS "kind"
                           JP-AMOUNT IS "amount"
                           JP-COUNTERPARTY IS "counterparty"
                           JP-REFERENCE IS "reference"
                           JP-DATE IS "date"
                   SUPPRESS JP-BALANCE JP-LINE
                   ON EXCEPTION MOVE "JG" TO EV-STATUS
               END-JSON
           ELSE
               JSON GENERATE WS-DATA FROM JD-POSTED
                   COUNT IN WS-DATA-LENGTH
                   NAME OF JD-POSTED IS OMITTED
                           JP-ACCOUNT IS "account"
                           JP-KIND IS "kind"
                           JP-AMOUNT IS "amount"
                           JP-REFERENCE IS "reference"
                           JP-DATE IS "date"
                   SUPPRESS JP-BALANCE JP-COUNTERPARTY JP-LINE
                   ON EXCEPTION MOVE "JG" TO EV-STATUS
               END-JSON
           END-IF
      *>   Merge the two objects: the entry's fields, then the line and
      *>   reason, by dropping the first's "}" and the second's "{".
           MOVE SPACES TO WS-EVENT
           STRING WS-DATA(1:WS-DATA-LENGTH - 1) ","
                  WS-JSON(2:WS-JSON-LENGTH - 1)
               DELIMITED BY SIZE INTO WS-EVENT
           END-STRING
           COMPUTE WS-DATA-LENGTH = WS-DATA-LENGTH + WS-JSON-LENGTH - 1
           MOVE WS-EVENT TO WS-DATA.

      *> A transfer that left its source account but could not be
      *> credited. The entry is the in leg, so its account is the target.
       BUILD-SUSPENDED.
           MOVE "transfer.suspended" TO JE-TYPE
           MOVE EV-OTHER-ACCT TO WS-ED-ACCT
           MOVE SPACES TO JE-SUBJECT
           STRING "accounts/" WS-ED-ACCT DELIMITED BY SIZE INTO JE-SUBJECT
           MOVE EV-OTHER-ACCT TO JS-FROM
           MOVE EV-ACCT-NO TO JS-TO
           MOVE EV-AMOUNT TO WS-ED-AMOUNT
           MOVE FUNCTION TRIM(WS-ED-AMOUNT) TO JS-AMOUNT
           MOVE EV-REF TO JS-REFERENCE
           PERFORM FORMAT-ENTRY-DATE
           MOVE JP-DATE TO JS-DATE
           MOVE EV-LINE TO JS-LINE
           MOVE EV-CODE TO JS-CODE
           PERFORM NAME-REASON
           MOVE JI-REASON TO JS-REASON
           MOVE EV-REASON TO JS-MESSAGE
           JSON GENERATE WS-DATA FROM JD-SUSPENDED
               COUNT IN WS-DATA-LENGTH
               NAME OF JD-SUSPENDED IS OMITTED
                       JS-FROM IS "from"
                       JS-TO IS "to"
                       JS-AMOUNT IS "amount"
                       JS-REFERENCE IS "reference"
                       JS-DATE IS "date"
                       JS-LINE IS "line"
                       JS-CODE IS "code"
                       JS-REASON IS "reason"
                       JS-MESSAGE IS "message"
               ON EXCEPTION MOVE "JG" TO EV-STATUS
           END-JSON.

       BUILD-COMPLETED.
           MOVE "run.completed" TO JE-TYPE
           PERFORM SET-RUN-SUBJECT
           MOVE WS-RUN-DATE-TEXT TO JC-RUN-DATE
           MOVE EV-CT-READ TO JC-READ
           MOVE EV-CT-INVALID TO JC-INVALID
           MOVE EV-CT-DECLINED TO JC-DECLINED
           MOVE EV-CT-ACCEPTED TO JC-ACCEPTED
           MOVE EV-CT-SUSPENDED TO JC-SUSPENDED
           MOVE EV-CT-ACCOUNTS TO JC-ACCOUNTS
           MOVE EV-CT-STATEMENTS TO JC-STATEMENTS
           MOVE WS-SEQ TO JC-EVENTS
           MOVE EV-TT-OPENING TO WS-ED-TOTAL
           MOVE FUNCTION TRIM(WS-ED-TOTAL) TO JC-OPENING
           MOVE EV-TT-DEPOSITS TO WS-ED-TOTAL
           MOVE FUNCTION TRIM(WS-ED-TOTAL) TO JC-DEPOSITS
           MOVE EV-TT-WITHDRAWALS TO WS-ED-TOTAL
           MOVE FUNCTION TRIM(WS-ED-TOTAL) TO JC-WITHDRAWALS
           MOVE EV-TT-TRANSFERS-OUT TO WS-ED-TOTAL
           MOVE FUNCTION TRIM(WS-ED-TOTAL) TO JC-TRANSFERS-OUT
           MOVE EV-TT-TRANSFERS-IN TO WS-ED-TOTAL
           MOVE FUNCTION TRIM(WS-ED-TOTAL) TO JC-TRANSFERS-IN
           MOVE EV-TT-SUSPENSE TO WS-ED-TOTAL
           MOVE FUNCTION TRIM(WS-ED-TOTAL) TO JC-SUSPENSE
           MOVE EV-TT-CLOSING TO WS-ED-TOTAL
           MOVE FUNCTION TRIM(WS-ED-TOTAL) TO JC-CLOSING
           JSON GENERATE WS-DATA FROM JD-COMPLETED
               COUNT IN WS-DATA-LENGTH
               NAME OF JD-COMPLETED IS OMITTED
                       JC-RUN-DATE IS "runDate"
                       JC-RESULT IS "result"
                       JC-COUNTS IS "counts"
                       JC-READ IS "transactionsRead"
                       JC-INVALID IS "invalid"
                       JC-DECLINED IS "declined"
                       JC-ACCEPTED IS "accepted"
                       JC-SUSPENDED IS "suspended"
                       JC-ACCOUNTS IS "accounts"
                       JC-STATEMENTS IS "statements"
                       JC-EVENTS IS "events"
                       JC-TOTALS IS "totals"
                       JC-OPENING IS "opening"
                       JC-DEPOSITS IS "deposits"
                       JC-WITHDRAWALS IS "withdrawals"
                       JC-TRANSFERS-OUT IS "transfersOut"
                       JC-TRANSFERS-IN IS "transfersIn"
                       JC-SUSPENSE IS "suspense"
                       JC-CLOSING IS "closing"
               ON EXCEPTION MOVE "JG" TO EV-STATUS
           END-JSON.

      *> ---------------------------------------------------------------
      *> Envelope and code translation.
      *> ---------------------------------------------------------------
      *> Numbers the event, generates the envelope and joins WS-DATA on
      *> as its data member, leaving the line in WS-EVENT.
       JOIN-EVENT.
           ADD 1 TO WS-SEQ
           MOVE SPACES TO JE-ID
           STRING EV-RUN-DATE "-" WS-SEQ DELIMITED BY SIZE INTO JE-ID
           MOVE JE-TYPE TO WS-EVENT
           MOVE SPACES TO JE-TYPE
           STRING FUNCTION TRIM(WS-TYPE-PREFIX) "ledger."
                  FUNCTION TRIM(WS-EVENT)
               DELIMITED BY SIZE INTO JE-TYPE
           JSON GENERATE WS-JSON FROM JE-ENVELOPE
               COUNT IN WS-JSON-LENGTH
               NAME OF JE-ENVELOPE IS OMITTED
                       JE-SPECVERSION IS "specversion"
                       JE-ID IS "id"
                       JE-SOURCE IS "source"
                       JE-TYPE IS "type"
                       JE-SUBJECT IS "subject"
                       JE-TIME IS "time"
                       JE-CONTENT-TYPE IS "datacontenttype"
               ON EXCEPTION MOVE "JG" TO EV-STATUS
           END-JSON
           MOVE SPACES TO WS-EVENT
           STRING WS-JSON(1:WS-JSON-LENGTH - 1) ',"data":'
                  WS-DATA(1:WS-DATA-LENGTH) "}"
               DELIMITED BY SIZE INTO WS-EVENT
           END-STRING
           COMPUTE WS-EVENT-LENGTH = WS-JSON-LENGTH + WS-DATA-LENGTH + 8.

       SET-ACCOUNT-SUBJECT.
           MOVE SPACES TO JE-SUBJECT
           STRING "accounts/" EV-ACCT-NO DELIMITED BY SIZE INTO JE-SUBJECT.

       SET-RUN-SUBJECT.
           MOVE SPACES TO JE-SUBJECT
           STRING "runs/" EV-RUN-DATE DELIMITED BY SIZE INTO JE-SUBJECT.

       FORMAT-ENTRY-DATE.
           MOVE SPACES TO JP-DATE
           STRING EV-DATE(1:4) "-" EV-DATE(5:2) "-" EV-DATE(7:2)
               DELIMITED BY SIZE INTO JP-DATE.

       NAME-LEG.
           EVALUATE EV-LEG
               WHEN "D" MOVE "deposit"      TO JP-KIND
               WHEN "W" MOVE "withdrawal"   TO JP-KIND
               WHEN "T" MOVE "transfer"     TO JP-KIND
               WHEN "O" MOVE "transfer_out" TO JP-KIND
               WHEN "I" MOVE "transfer_in"  TO JP-KIND
           END-EVALUATE.

      *> Exception codes become stable reason names; the message keeps
      *> LEDGRUN's wording for people. E05 covers two distinct reasons.
       NAME-REASON.
           EVALUATE EV-CODE
               WHEN "E01" MOVE "account_not_numeric"    TO JI-REASON
               WHEN "E02" MOVE "invalid_date"           TO JI-REASON
               WHEN "E03" MOVE "unknown_type"           TO JI-REASON
               WHEN "E04" MOVE "invalid_amount"         TO JI-REASON
               WHEN "E05"
                   IF EV-REASON = "TRANSFER TO SAME ACCOUNT"
                       MOVE "same_account"              TO JI-REASON
                   ELSE
                       MOVE "invalid_target"            TO JI-REASON
                   END-IF
               WHEN "E10" MOVE "account_not_found"      TO JI-REASON
               WHEN "E11" MOVE "account_closed"         TO JI-REASON
               WHEN "E12" MOVE "insufficient_funds"     TO JI-REASON
               WHEN "E13" MOVE "balance_limit_exceeded" TO JI-REASON
               WHEN "E20" MOVE "target_not_found"       TO JI-REASON
               WHEN "E21" MOVE "target_closed"          TO JI-REASON
               WHEN "E22" MOVE "target_at_limit"        TO JI-REASON
           END-EVALUATE.

       END PROGRAM LEDGEVT.
