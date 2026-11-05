       IDENTIFICATION DIVISION.
       PROGRAM-ID. AMORTAPI.
      *> JSON front end. GET /cgi-bin/amortise-api?principal=&rate=&term=
      *> returns the schedule as JSON, or a 400 with a machine-readable
      *> error. www/openapi.json is the contract.
      *>
      *> Objects come from JSON GENERATE, which names keys with NAME OF
      *> and escapes strings. GnuCOBOL 3.2 can't generate OCCURS tables,
      *> so each schedule row is generated on its own and the array is
      *> joined here.
      *>
      *> Amounts are JSON strings ("2709.27"), not numbers: a JSON
      *> number is a binary float to most consumers, and 9(9)V99 is exact.

       DATA DIVISION.
       WORKING-STORAGE SECTION.
       COPY "amortreq.cpy".
       COPY "amortres.cpy".

       01  WS-HAS-INPUT                PIC X.
       01  WS-METHOD                   PIC X(16).
       01  WS-ROW                      PIC 9(3).

       01  WS-ED-AMOUNT                PIC Z(10)9.99.
       01  WS-ED-RATE                  PIC ZZ9.9999.

      *> The shapes of the JSON objects. Every field is named with
      *> NAME OF in the JSON GENERATE that uses it.
       01  JS-SUMMARY.
           05  JS-LOAN.
               10  JS-PRINCIPAL        PIC X(16).
               10  JS-ANNUAL-RATE      PIC X(10).
               10  JS-TERM-MONTHS      PIC 9(3).
           05  JS-PAYMENT              PIC X(16).
           05  JS-TOTAL-INTEREST       PIC X(16).
           05  JS-TOTAL-PAID           PIC X(16).
       01  JS-PERIOD-ROW.
           05  JS-PERIOD               PIC 9(3).
           05  JS-ROW-PAYMENT          PIC X(16).
           05  JS-ROW-INTEREST         PIC X(16).
           05  JS-ROW-PRINCIPAL        PIC X(16).
           05  JS-ROW-BALANCE          PIC X(16).
       01  JS-ERROR-BODY.
           05  JS-ERROR.
               10  JS-ERROR-CODE       PIC X(24).
               10  JS-ERROR-FIELD      PIC X(10).
               10  JS-ERROR-MESSAGE    PIC X(80).

       01  WS-JSON                     PIC X(512).
       01  WS-JSON-LENGTH              PIC 9(4).
      *> The largest schedule, 600 rows of nine-digit amounts, is about
      *> 65,000 bytes.
       01  WS-BODY                     PIC X(80000).
       01  WS-BODY-POINTER             PIC 9(5).

       PROCEDURE DIVISION.
       MAIN-PROCEDURE.
           ACCEPT WS-METHOD FROM ENVIRONMENT "REQUEST_METHOD"
               ON EXCEPTION MOVE "GET" TO WS-METHOD
           END-ACCEPT
           IF WS-METHOD NOT = "GET"
               MOVE "method_not_allowed" TO JS-ERROR-CODE
               MOVE "method" TO JS-ERROR-FIELD
               MOVE "Only GET is supported" TO JS-ERROR-MESSAGE
               PERFORM SEND-ERROR
               STOP RUN
           END-IF

           CALL "AMORTQRY" USING AMORT-REQUEST WS-HAS-INPUT
           CALL "AMORTCALC" USING AMORT-REQUEST AMORT-RESULT
           IF AS-OK
               PERFORM SEND-SCHEDULE
           ELSE
               PERFORM MAP-ERROR
               PERFORM SEND-ERROR
           END-IF
           STOP RUN.

      *> AMORTCALC's status codes become stable, documented error codes.
      *> The message stays human-readable and may change.
       MAP-ERROR.
           EVALUATE TRUE
               WHEN AS-BAD-PRINCIPAL
                   MOVE "invalid_principal" TO JS-ERROR-CODE
                   MOVE "principal" TO JS-ERROR-FIELD
               WHEN AS-BAD-RATE
                   MOVE "invalid_rate" TO JS-ERROR-CODE
                   MOVE "rate" TO JS-ERROR-FIELD
               WHEN AS-BAD-TERM
                   MOVE "invalid_term" TO JS-ERROR-CODE
                   MOVE "term" TO JS-ERROR-FIELD
               WHEN AS-PAYMENT-TOO-SMALL
                   MOVE "payment_too_small" TO JS-ERROR-CODE
                   MOVE "principal" TO JS-ERROR-FIELD
           END-EVALUATE
           MOVE AS-MESSAGE TO JS-ERROR-MESSAGE.

       SEND-SCHEDULE.
           MOVE AS-PRINCIPAL TO WS-ED-AMOUNT
           MOVE FUNCTION TRIM(WS-ED-AMOUNT) TO JS-PRINCIPAL
           MOVE AS-ANNUAL-RATE TO WS-ED-RATE
           MOVE FUNCTION TRIM(WS-ED-RATE) TO JS-ANNUAL-RATE
           MOVE AS-TERM-MONTHS TO JS-TERM-MONTHS
           MOVE AS-PAYMENT TO WS-ED-AMOUNT
           MOVE FUNCTION TRIM(WS-ED-AMOUNT) TO JS-PAYMENT
           MOVE AS-TOTAL-INTEREST TO WS-ED-AMOUNT
           MOVE FUNCTION TRIM(WS-ED-AMOUNT) TO JS-TOTAL-INTEREST
           MOVE AS-TOTAL-PAID TO WS-ED-AMOUNT
           MOVE FUNCTION TRIM(WS-ED-AMOUNT) TO JS-TOTAL-PAID

           JSON GENERATE WS-JSON FROM JS-SUMMARY
               COUNT IN WS-JSON-LENGTH
               NAME OF JS-SUMMARY IS OMITTED
                       JS-LOAN IS "loan"
                       JS-PRINCIPAL IS "principal"
                       JS-ANNUAL-RATE IS "annualRate"
                       JS-TERM-MONTHS IS "termMonths"
                       JS-PAYMENT IS "payment"
                       JS-TOTAL-INTEREST IS "totalInterest"
                       JS-TOTAL-PAID IS "totalPaid"
               ON EXCEPTION PERFORM SEND-INTERNAL-ERROR
           END-JSON
      *>   Reopen the summary object to add the schedule array to it.
           MOVE 1 TO WS-BODY-POINTER
           STRING WS-JSON(1:WS-JSON-LENGTH - 1) ',"schedule":['
               DELIMITED BY SIZE INTO WS-BODY POINTER WS-BODY-POINTER
               ON OVERFLOW PERFORM SEND-INTERNAL-ERROR
           END-STRING

           PERFORM VARYING WS-ROW FROM 1 BY 1 UNTIL WS-ROW > AS-ROW-COUNT
               PERFORM GENERATE-ROW
               IF WS-ROW > 1
                   STRING "," DELIMITED BY SIZE
                       INTO WS-BODY POINTER WS-BODY-POINTER
                       ON OVERFLOW PERFORM SEND-INTERNAL-ERROR
                   END-STRING
               END-IF
               STRING WS-JSON(1:WS-JSON-LENGTH) DELIMITED BY SIZE
                   INTO WS-BODY POINTER WS-BODY-POINTER
                   ON OVERFLOW PERFORM SEND-INTERNAL-ERROR
               END-STRING
           END-PERFORM
           STRING "]}" DELIMITED BY SIZE
               INTO WS-BODY POINTER WS-BODY-POINTER
               ON OVERFLOW PERFORM SEND-INTERNAL-ERROR
           END-STRING

           DISPLAY "Content-Type: application/json" X"0D"
           PERFORM SEND-COMMON-HEADERS
           DISPLAY WS-BODY(1:WS-BODY-POINTER - 1).

       GENERATE-ROW.
           MOVE WS-ROW TO JS-PERIOD
           MOVE AS-ROW-PAYMENT(WS-ROW) TO WS-ED-AMOUNT
           MOVE FUNCTION TRIM(WS-ED-AMOUNT) TO JS-ROW-PAYMENT
           MOVE AS-ROW-INTEREST(WS-ROW) TO WS-ED-AMOUNT
           MOVE FUNCTION TRIM(WS-ED-AMOUNT) TO JS-ROW-INTEREST
           MOVE AS-ROW-PRINCIPAL(WS-ROW) TO WS-ED-AMOUNT
           MOVE FUNCTION TRIM(WS-ED-AMOUNT) TO JS-ROW-PRINCIPAL
           MOVE AS-ROW-BALANCE(WS-ROW) TO WS-ED-AMOUNT
           MOVE FUNCTION TRIM(WS-ED-AMOUNT) TO JS-ROW-BALANCE
           JSON GENERATE WS-JSON FROM JS-PERIOD-ROW
               COUNT IN WS-JSON-LENGTH
               NAME OF JS-PERIOD-ROW IS OMITTED
                       JS-PERIOD IS "period"
                       JS-ROW-PAYMENT IS "payment"
                       JS-ROW-INTEREST IS "interest"
                       JS-ROW-PRINCIPAL IS "principal"
                       JS-ROW-BALANCE IS "balance"
               ON EXCEPTION PERFORM SEND-INTERNAL-ERROR
           END-JSON.

       SEND-ERROR.
           JSON GENERATE WS-JSON FROM JS-ERROR-BODY
               COUNT IN WS-JSON-LENGTH
               NAME OF JS-ERROR-BODY IS OMITTED
                       JS-ERROR IS "error"
                       JS-ERROR-CODE IS "code"
                       JS-ERROR-FIELD IS "field"
                       JS-ERROR-MESSAGE IS "message"
               ON EXCEPTION PERFORM SEND-INTERNAL-ERROR
           END-JSON
           IF JS-ERROR-CODE = "method_not_allowed"
               DISPLAY "Status: 405 Method Not Allowed" X"0D"
               DISPLAY "Allow: GET" X"0D"
           ELSE
               DISPLAY "Status: 400 Bad Request" X"0D"
           END-IF
           DISPLAY "Content-Type: application/json" X"0D"
           PERFORM SEND-COMMON-HEADERS
           DISPLAY WS-JSON(1:WS-JSON-LENGTH).

      *> Only reached if JSON GENERATE fails or the body overflows, so
      *> the body is a fixed literal rather than generated. No headers
      *> have been sent yet when either can happen.
       SEND-INTERNAL-ERROR.
           DISPLAY "Status: 500 Internal Server Error" X"0D"
           DISPLAY "Content-Type: application/json" X"0D"
           PERFORM SEND-COMMON-HEADERS
           DISPLAY '{"error":{"code":"internal_error","field":"",'
                   '"message":"Could not generate the response"}}'
           STOP RUN.

      *> The schedule is a pure function of the query, so any origin may
      *> call it. Header lines end in CR LF: DISPLAY supplies the LF.
      *> The extra CR LF on the last one is the blank line that ends
      *> the CGI headers.
       SEND-COMMON-HEADERS.
           DISPLAY "Access-Control-Allow-Origin: *" X"0D"
           DISPLAY "Cache-Control: no-store" X"0D0A0D".

       END PROGRAM AMORTAPI.
