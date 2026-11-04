       IDENTIFICATION DIVISION.
       PROGRAM-ID. AMORTCALC.
      *> Validates a loan request and builds its monthly amortisation
      *> schedule. Payments are rounded to the cent and the final
      *> payment absorbs the rounding difference, so the balance always
      *> closes at exactly zero.

       DATA DIVISION.
       WORKING-STORAGE SECTION.
       01  WS-NUMBER                   PIC S9(12)V9(6).
       01  WS-MONTHLY-RATE             PIC 9V9(15).
       01  WS-PERIOD                   PIC 9(3).
       01  WS-BALANCE                  PIC S9(9)V99.
       01  WS-INTEREST                 PIC S9(9)V99.
       01  WS-PRINCIPAL-PART           PIC S9(9)V99.
       01  WS-PAYMENT                  PIC S9(10)V99.

       LINKAGE SECTION.
       COPY "amortreq.cpy".
       COPY "amortres.cpy".

       PROCEDURE DIVISION USING AMORT-REQUEST AMORT-RESULT.
       MAIN-PROCEDURE.
           INITIALIZE AMORT-RESULT
           SET AS-OK TO TRUE
           PERFORM PARSE-PRINCIPAL
           IF AS-OK
               PERFORM PARSE-RATE
           END-IF
           IF AS-OK
               PERFORM PARSE-TERM
           END-IF
           IF AS-OK
               PERFORM CALCULATE-PAYMENT
           END-IF
           IF AS-OK
               PERFORM BUILD-SCHEDULE
           END-IF
           GOBACK.

      *> Each PARSE paragraph rejects blanks, non-numbers, values out of
      *> range and values with more decimal places than the field holds.
       PARSE-PRINCIPAL.
           IF AR-PRINCIPAL-TEXT = SPACES
              OR FUNCTION TEST-NUMVAL(AR-PRINCIPAL-TEXT) NOT = 0
               SET AS-BAD-PRINCIPAL TO TRUE
           ELSE
               COMPUTE WS-NUMBER = FUNCTION NUMVAL(AR-PRINCIPAL-TEXT)
                   ON SIZE ERROR SET AS-BAD-PRINCIPAL TO TRUE
               END-COMPUTE
           END-IF
           IF AS-OK
               IF WS-NUMBER < 0.01 OR WS-NUMBER > 999999999.99
                  OR WS-NUMBER * 100
                     NOT = FUNCTION INTEGER-PART(WS-NUMBER * 100)
                   SET AS-BAD-PRINCIPAL TO TRUE
               ELSE
                   MOVE WS-NUMBER TO AS-PRINCIPAL
               END-IF
           END-IF
           IF AS-BAD-PRINCIPAL
               MOVE "Principal must be an amount from 0.01 to 999999999.99"
                 TO AS-MESSAGE
           END-IF.

       PARSE-RATE.
           IF AR-RATE-TEXT = SPACES
              OR FUNCTION TEST-NUMVAL(AR-RATE-TEXT) NOT = 0
               SET AS-BAD-RATE TO TRUE
           ELSE
               COMPUTE WS-NUMBER = FUNCTION NUMVAL(AR-RATE-TEXT)
                   ON SIZE ERROR SET AS-BAD-RATE TO TRUE
               END-COMPUTE
           END-IF
           IF AS-OK
               IF WS-NUMBER < 0 OR WS-NUMBER > 100
                  OR WS-NUMBER * 10000
                     NOT = FUNCTION INTEGER-PART(WS-NUMBER * 10000)
                   SET AS-BAD-RATE TO TRUE
               ELSE
                   MOVE WS-NUMBER TO AS-ANNUAL-RATE
               END-IF
           END-IF
           IF AS-BAD-RATE
               MOVE "Annual rate must be a percentage from 0 to 100, at most 4 decimals"
                 TO AS-MESSAGE
           END-IF.

       PARSE-TERM.
           IF AR-TERM-TEXT = SPACES
              OR FUNCTION TEST-NUMVAL(AR-TERM-TEXT) NOT = 0
               SET AS-BAD-TERM TO TRUE
           ELSE
               COMPUTE WS-NUMBER = FUNCTION NUMVAL(AR-TERM-TEXT)
                   ON SIZE ERROR SET AS-BAD-TERM TO TRUE
               END-COMPUTE
           END-IF
           IF AS-OK
               IF WS-NUMBER < 1 OR WS-NUMBER > 600
                  OR WS-NUMBER NOT = FUNCTION INTEGER-PART(WS-NUMBER)
                   SET AS-BAD-TERM TO TRUE
               ELSE
                   MOVE WS-NUMBER TO AS-TERM-MONTHS
               END-IF
           END-IF
           IF AS-BAD-TERM
               MOVE "Term must be a whole number of months from 1 to 600"
                 TO AS-MESSAGE
           END-IF.

      *> Standard annuity formula: P * r / (1 - (1 + r) ** -n).
       CALCULATE-PAYMENT.
           COMPUTE WS-MONTHLY-RATE ROUNDED = AS-ANNUAL-RATE / 1200
           IF WS-MONTHLY-RATE = 0
               COMPUTE AS-PAYMENT ROUNDED = AS-PRINCIPAL / AS-TERM-MONTHS
           ELSE
               COMPUTE AS-PAYMENT ROUNDED =
                   AS-PRINCIPAL * WS-MONTHLY-RATE
                   / (1 - (1 + WS-MONTHLY-RATE) ** (0 - AS-TERM-MONTHS))
           END-IF
           IF AS-PAYMENT < 0.01
               SET AS-PAYMENT-TOO-SMALL TO TRUE
               MOVE "Principal is too small to repay over this term"
                 TO AS-MESSAGE
           END-IF.

       BUILD-SCHEDULE.
           MOVE AS-PRINCIPAL TO WS-BALANCE
           PERFORM VARYING WS-PERIOD FROM 1 BY 1
                   UNTIL WS-PERIOD > AS-TERM-MONTHS OR WS-BALANCE = 0
               COMPUTE WS-INTEREST ROUNDED = WS-BALANCE * WS-MONTHLY-RATE
               COMPUTE WS-PRINCIPAL-PART = AS-PAYMENT - WS-INTEREST
      *>       The last period settles whatever is left; rounding can
      *>       also let the balance run out a period early.
               IF WS-PERIOD = AS-TERM-MONTHS
                  OR WS-PRINCIPAL-PART > WS-BALANCE
                   MOVE WS-BALANCE TO WS-PRINCIPAL-PART
               END-IF
               COMPUTE WS-PAYMENT = WS-PRINCIPAL-PART + WS-INTEREST
               SUBTRACT WS-PRINCIPAL-PART FROM WS-BALANCE

               MOVE WS-PERIOD         TO AS-ROW-COUNT
               MOVE WS-PAYMENT        TO AS-ROW-PAYMENT(WS-PERIOD)
               MOVE WS-INTEREST       TO AS-ROW-INTEREST(WS-PERIOD)
               MOVE WS-PRINCIPAL-PART TO AS-ROW-PRINCIPAL(WS-PERIOD)
               MOVE WS-BALANCE        TO AS-ROW-BALANCE(WS-PERIOD)
               ADD WS-INTEREST TO AS-TOTAL-INTEREST
               ADD WS-PAYMENT  TO AS-TOTAL-PAID
           END-PERFORM.

       END PROGRAM AMORTCALC.
