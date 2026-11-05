       IDENTIFICATION DIVISION.
       PROGRAM-ID. LEDGER.
      *> Command-line front end.
      *>   ledger [--date YYYYMMDD] MASTER TRANSACTIONS OUTDIR
      *> Exit codes: 0 clean, 4 exceptions reported, 16 run aborted,
      *> 2 usage error.

       ENVIRONMENT DIVISION.
       INPUT-OUTPUT SECTION.
       FILE-CONTROL.
           SELECT CONTROL-RPT ASSIGN TO WS-CONTROL-PATH
               ORGANIZATION IS LINE SEQUENTIAL
               FILE STATUS IS WS-FS-CONTROL.

       DATA DIVISION.
       FILE SECTION.
       FD  CONTROL-RPT.
       01  CONTROL-REC                 PIC X(80).

       WORKING-STORAGE SECTION.
       COPY "ledgreq.cpy".
       COPY "ledgres.cpy".

       01  WS-ARG-COUNT                PIC 9(2).
       01  WS-ARG-INDEX                PIC 9(2).
       01  WS-ARG                      PIC X(256).
       01  WS-POSITIONAL               PIC 9(2) VALUE 0.
       01  WS-DATE-ARG                 PIC X(256) VALUE SPACES.
       01  WS-CONTROL-PATH             PIC X(300).
       01  WS-FS-CONTROL               PIC XX.
       01  WS-EOF-FLAG                 PIC X VALUE "N".
           88  WS-EOF                            VALUE "Y".
       01  WS-ED-COUNT                 PIC Z,ZZZ,ZZ9.

       PROCEDURE DIVISION.
       MAIN-PROCEDURE.
           PERFORM PARSE-ARGUMENTS
           CALL "CBL_CREATE_DIR" USING LR-OUT-DIR
           CALL "LEDGRUN" USING LEDGER-REQUEST LEDGER-RESULT
           PERFORM PRINT-CONTROL-REPORT
           EVALUATE TRUE
               WHEN LS-ABORTED
                   DISPLAY "ledger: run aborted: " FUNCTION TRIM(LS-MESSAGE)
                       UPON SYSERR
               WHEN LS-EXCEPTIONS
                   MOVE LS-EXCEPTION-COUNT TO WS-ED-COUNT
                   DISPLAY "ledger: " FUNCTION TRIM(WS-ED-COUNT)
                           " exception(s), see "
                           FUNCTION TRIM(LR-OUT-DIR) "/exceptions.txt"
                       UPON SYSERR
           END-EVALUATE
           MOVE LS-RETURN-CODE TO RETURN-CODE
           STOP RUN.

       PARSE-ARGUMENTS.
           ACCEPT WS-ARG-COUNT FROM ARGUMENT-NUMBER
           MOVE 1 TO WS-ARG-INDEX
           PERFORM UNTIL WS-ARG-INDEX > WS-ARG-COUNT
               DISPLAY WS-ARG-INDEX UPON ARGUMENT-NUMBER
               ACCEPT WS-ARG FROM ARGUMENT-VALUE
               EVALUATE TRUE
                   WHEN WS-ARG = "-h" OR WS-ARG = "--help"
                       PERFORM PRINT-USAGE
                       MOVE 0 TO RETURN-CODE
                       STOP RUN
                   WHEN WS-ARG = "--date"
                       ADD 1 TO WS-ARG-INDEX
                       IF WS-ARG-INDEX > WS-ARG-COUNT
                           PERFORM PRINT-USAGE-ERROR
                       END-IF
                       DISPLAY WS-ARG-INDEX UPON ARGUMENT-NUMBER
                       ACCEPT WS-DATE-ARG FROM ARGUMENT-VALUE
                   WHEN OTHER
                       ADD 1 TO WS-POSITIONAL
                       EVALUATE WS-POSITIONAL
                           WHEN 1 MOVE WS-ARG TO LR-MASTER-PATH
                           WHEN 2 MOVE WS-ARG TO LR-TXN-PATH
                           WHEN 3 MOVE WS-ARG TO LR-OUT-DIR
                       END-EVALUATE
               END-EVALUATE
               ADD 1 TO WS-ARG-INDEX
           END-PERFORM
           IF WS-POSITIONAL NOT = 3
               PERFORM PRINT-USAGE-ERROR
           END-IF

           IF WS-DATE-ARG = SPACES
               MOVE FUNCTION CURRENT-DATE(1:8) TO LR-RUN-DATE
           ELSE
               IF WS-DATE-ARG(9:) NOT = SPACES
                  OR WS-DATE-ARG(1:8) IS NOT NUMERIC
                   DISPLAY "ledger: --date must be YYYYMMDD" UPON SYSERR
                   MOVE 2 TO RETURN-CODE
                   STOP RUN
               END-IF
               MOVE WS-DATE-ARG(1:8) TO LR-RUN-DATE
               IF FUNCTION TEST-DATE-YYYYMMDD(LR-RUN-DATE) NOT = 0
                   DISPLAY "ledger: --date must be YYYYMMDD" UPON SYSERR
                   MOVE 2 TO RETURN-CODE
                   STOP RUN
               END-IF
           END-IF.

       PRINT-USAGE.
           DISPLAY "Usage: ledger [--date YYYYMMDD] MASTER TRANSACTIONS OUTDIR"
           DISPLAY " "
           DISPLAY "Applies a day's transactions to an account master file."
           DISPLAY " "
           DISPLAY "  MASTER        account master file, sorted by account"
           DISPLAY "  TRANSACTIONS  deposits, withdrawals and transfers"
           DISPLAY "  OUTDIR        receives accounts.new.dat, statements.txt,"
           DISPLAY "                exceptions.txt, control.txt and events.jsonl"
           DISPLAY "  --date        run date printed on reports (default today)"
           DISPLAY " "
           DISPLAY "Exit status: 0 clean, 4 exceptions reported, 16 run aborted.".

       PRINT-USAGE-ERROR.
           DISPLAY "Usage: ledger [--date YYYYMMDD] MASTER TRANSACTIONS OUTDIR"
               UPON SYSERR
           DISPLAY "Try 'ledger --help' for more information." UPON SYSERR
           MOVE 2 TO RETURN-CODE
           STOP RUN.

       PRINT-CONTROL-REPORT.
           STRING FUNCTION TRIM(LR-OUT-DIR) "/control.txt"
               DELIMITED BY SIZE INTO WS-CONTROL-PATH
           OPEN INPUT CONTROL-RPT
           IF WS-FS-CONTROL NOT = "00"
               EXIT PARAGRAPH
           END-IF
           PERFORM UNTIL WS-EOF
               READ CONTROL-RPT
                   AT END SET WS-EOF TO TRUE
                   NOT AT END
                       DISPLAY FUNCTION TRIM(CONTROL-REC TRAILING)
               END-READ
           END-PERFORM
           CLOSE CONTROL-RPT.

       END PROGRAM LEDGER.
