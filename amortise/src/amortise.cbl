       IDENTIFICATION DIVISION.
       PROGRAM-ID. AMORTISE.
      *> Command-line front end.
      *>   amortise [--csv] PRINCIPAL ANNUAL-RATE MONTHS
      *> Exit codes: 0 ok, 1 invalid loan details, 2 usage error.

       DATA DIVISION.
       WORKING-STORAGE SECTION.
       COPY "amortreq.cpy".
       COPY "amortres.cpy".

       01  WS-ARG-COUNT                PIC 9(2).
       01  WS-ARG-INDEX                PIC 9(2).
       01  WS-ARG                      PIC X(40).
       01  WS-POSITIONAL               PIC 9(2) VALUE 0.
       01  WS-OUTPUT-FORMAT            PIC X VALUE "R".
           88  WS-REPORT                         VALUE "R".
           88  WS-CSV                            VALUE "C".
       01  WS-ROW                      PIC 9(3).

       01  WS-ED-MONEY                 PIC ZZ,ZZZ,ZZZ,ZZ9.99.
       01  WS-ED-RATE                  PIC ZZ9.9999.
       01  WS-ED-TERM                  PIC ZZ9.

       01  WS-HEADING-1.
           05  FILLER                  PIC X(6)  VALUE "PERIOD".
           05  FILLER                  PIC X(18) VALUE "           PAYMENT".
           05  FILLER                  PIC X(18) VALUE "          INTEREST".
           05  FILLER                  PIC X(18) VALUE "         PRINCIPAL".
           05  FILLER                  PIC X(18) VALUE "           BALANCE".
       01  WS-HEADING-2.
           05  FILLER                  PIC X(6)  VALUE ALL "-".
           05  FILLER                  OCCURS 4 TIMES.
               10  FILLER              PIC X(2)  VALUE SPACES.
               10  FILLER              PIC X(16) VALUE ALL "-".
       01  WS-DETAIL-LINE.
           05  DL-PERIOD               PIC ZZZZZ9.
           05  FILLER                  PIC X(2)  VALUE SPACES.
           05  DL-PAYMENT              PIC Z,ZZZ,ZZZ,ZZ9.99.
           05  FILLER                  PIC X(2)  VALUE SPACES.
           05  DL-INTEREST             PIC Z,ZZZ,ZZZ,ZZ9.99.
           05  FILLER                  PIC X(2)  VALUE SPACES.
           05  DL-PRINCIPAL            PIC Z,ZZZ,ZZZ,ZZ9.99.
           05  FILLER                  PIC X(2)  VALUE SPACES.
           05  DL-BALANCE              PIC Z,ZZZ,ZZZ,ZZ9.99.

       01  WS-CSV-PERIOD               PIC ZZ9.
       01  WS-CSV-PAYMENT              PIC Z(9)9.99.
       01  WS-CSV-INTEREST             PIC Z(8)9.99.
       01  WS-CSV-PRINCIPAL            PIC Z(8)9.99.
       01  WS-CSV-BALANCE              PIC Z(8)9.99.

       PROCEDURE DIVISION.
       MAIN-PROCEDURE.
           PERFORM PARSE-ARGUMENTS
           CALL "AMORTCALC" USING AMORT-REQUEST AMORT-RESULT
           IF NOT AS-OK
               DISPLAY "amortise: " FUNCTION TRIM(AS-MESSAGE) UPON SYSERR
               MOVE 1 TO RETURN-CODE
               STOP RUN
           END-IF
           IF WS-CSV
               PERFORM PRINT-CSV
           ELSE
               PERFORM PRINT-REPORT
           END-IF
           MOVE 0 TO RETURN-CODE
           STOP RUN.

       PARSE-ARGUMENTS.
           ACCEPT WS-ARG-COUNT FROM ARGUMENT-NUMBER
           PERFORM VARYING WS-ARG-INDEX FROM 1 BY 1
                   UNTIL WS-ARG-INDEX > WS-ARG-COUNT
               DISPLAY WS-ARG-INDEX UPON ARGUMENT-NUMBER
               ACCEPT WS-ARG FROM ARGUMENT-VALUE
               EVALUATE TRUE
                   WHEN WS-ARG = "-h" OR WS-ARG = "--help"
                       PERFORM PRINT-USAGE
                       MOVE 0 TO RETURN-CODE
                       STOP RUN
                   WHEN WS-ARG = "--csv"
                       SET WS-CSV TO TRUE
                   WHEN OTHER
                       ADD 1 TO WS-POSITIONAL
                       EVALUATE WS-POSITIONAL
                           WHEN 1 MOVE WS-ARG TO AR-PRINCIPAL-TEXT
                           WHEN 2 MOVE WS-ARG TO AR-RATE-TEXT
                           WHEN 3 MOVE WS-ARG TO AR-TERM-TEXT
                       END-EVALUATE
               END-EVALUATE
           END-PERFORM
           IF WS-POSITIONAL NOT = 3
               PERFORM PRINT-USAGE-ERROR
           END-IF.

       PRINT-USAGE.
           DISPLAY "Usage: amortise [--csv] PRINCIPAL ANNUAL-RATE MONTHS"
           DISPLAY " "
           DISPLAY "Prints the monthly repayment schedule for a loan."
           DISPLAY " "
           DISPLAY "  PRINCIPAL    amount borrowed, e.g. 250000 or 250000.00"
           DISPLAY "  ANNUAL-RATE  nominal yearly interest rate in percent, e.g. 11.75"
           DISPLAY "  MONTHS       term in months, 1 to 600"
           DISPLAY "  --csv        print the schedule as CSV instead of a report".

       PRINT-USAGE-ERROR.
           DISPLAY "Usage: amortise [--csv] PRINCIPAL ANNUAL-RATE MONTHS"
               UPON SYSERR
           DISPLAY "Try 'amortise --help' for more information." UPON SYSERR
           MOVE 2 TO RETURN-CODE
           STOP RUN.

       PRINT-REPORT.
           DISPLAY "LOAN AMORTISATION SCHEDULE"
           DISPLAY " "
           MOVE AS-PRINCIPAL TO WS-ED-MONEY
           DISPLAY "Principal          " WS-ED-MONEY
           MOVE AS-ANNUAL-RATE TO WS-ED-RATE
           DISPLAY "Annual rate                 " WS-ED-RATE " %"
           MOVE AS-TERM-MONTHS TO WS-ED-TERM
           DISPLAY "Term                             " WS-ED-TERM " months"
           MOVE AS-PAYMENT TO WS-ED-MONEY
           DISPLAY "Monthly payment    " WS-ED-MONEY
           MOVE AS-TOTAL-INTEREST TO WS-ED-MONEY
           DISPLAY "Total interest     " WS-ED-MONEY
           MOVE AS-TOTAL-PAID TO WS-ED-MONEY
           DISPLAY "Total repaid       " WS-ED-MONEY
           DISPLAY " "
           DISPLAY WS-HEADING-1
           DISPLAY WS-HEADING-2
           PERFORM VARYING WS-ROW FROM 1 BY 1 UNTIL WS-ROW > AS-ROW-COUNT
               MOVE WS-ROW                 TO DL-PERIOD
               MOVE AS-ROW-PAYMENT(WS-ROW)   TO DL-PAYMENT
               MOVE AS-ROW-INTEREST(WS-ROW)  TO DL-INTEREST
               MOVE AS-ROW-PRINCIPAL(WS-ROW) TO DL-PRINCIPAL
               MOVE AS-ROW-BALANCE(WS-ROW)   TO DL-BALANCE
               DISPLAY WS-DETAIL-LINE
           END-PERFORM.

       PRINT-CSV.
           DISPLAY "period,payment,interest,principal,balance"
           PERFORM VARYING WS-ROW FROM 1 BY 1 UNTIL WS-ROW > AS-ROW-COUNT
               MOVE WS-ROW                   TO WS-CSV-PERIOD
               MOVE AS-ROW-PAYMENT(WS-ROW)   TO WS-CSV-PAYMENT
               MOVE AS-ROW-INTEREST(WS-ROW)  TO WS-CSV-INTEREST
               MOVE AS-ROW-PRINCIPAL(WS-ROW) TO WS-CSV-PRINCIPAL
               MOVE AS-ROW-BALANCE(WS-ROW)   TO WS-CSV-BALANCE
               DISPLAY FUNCTION TRIM(WS-CSV-PERIOD) ","
                       FUNCTION TRIM(WS-CSV-PAYMENT) ","
                       FUNCTION TRIM(WS-CSV-INTEREST) ","
                       FUNCTION TRIM(WS-CSV-PRINCIPAL) ","
                       FUNCTION TRIM(WS-CSV-BALANCE)
           END-PERFORM.

       END PROGRAM AMORTISE.
