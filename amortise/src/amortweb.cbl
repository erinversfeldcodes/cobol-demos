       IDENTIFICATION DIVISION.
       PROGRAM-ID. AMORTWEB.
      *> CGI front end. GET /cgi-bin/amortise?principal=&rate=&term=
      *> renders the form and, when parameters are present, the schedule.

       ENVIRONMENT DIVISION.
       CONFIGURATION SECTION.
       SPECIAL-NAMES.
      *>   Characters that may be echoed back into the form unescaped.
           CLASS FORM-SAFE IS "0" THRU "9" "." "," "+" "-" " ".

       DATA DIVISION.
       WORKING-STORAGE SECTION.
       COPY "amortreq.cpy".
       COPY "amortres.cpy".

       01  WS-QUERY                    PIC X(1024).
       01  WS-PAIRS.
           05  WS-PAIR                 PIC X(256) OCCURS 6 TIMES.
       01  WS-PAIR-INDEX               PIC 9.
       01  WS-KEY                      PIC X(32).
       01  WS-VALUE                    PIC X(256).
       01  WS-HAS-INPUT                PIC X VALUE "N".
           88  WS-INPUT-GIVEN                    VALUE "Y".
       01  WS-ROW                      PIC 9(3).

       01  WS-FORM-PRINCIPAL           PIC X(20).
       01  WS-FORM-RATE                PIC X(20).
       01  WS-FORM-TERM                PIC X(20).

       01  WS-ED-PERIOD                PIC ZZ9.
       01  WS-ED-PAYMENT               PIC Z,ZZZ,ZZZ,ZZ9.99.
       01  WS-ED-INTEREST              PIC Z,ZZZ,ZZZ,ZZ9.99.
       01  WS-ED-PRINCIPAL             PIC Z,ZZZ,ZZZ,ZZ9.99.
       01  WS-ED-BALANCE               PIC Z,ZZZ,ZZZ,ZZ9.99.
       01  WS-ED-TOTAL                 PIC ZZ,ZZZ,ZZZ,ZZ9.99.
       01  WS-ED-RATE                  PIC ZZ9.9999.

       PROCEDURE DIVISION.
       MAIN-PROCEDURE.
           PERFORM READ-QUERY
           IF WS-INPUT-GIVEN
               CALL "AMORTCALC" USING AMORT-REQUEST AMORT-RESULT
           END-IF
           PERFORM PREPARE-FORM-VALUES
           PERFORM PAGE-START
           PERFORM PAGE-FORM
           IF WS-INPUT-GIVEN
               IF AS-OK
                   PERFORM PAGE-SUMMARY
                   PERFORM PAGE-SCHEDULE
               ELSE
                   DISPLAY '<p class="error">' FUNCTION TRIM(AS-MESSAGE)
                           '</p>'
               END-IF
           END-IF
           PERFORM PAGE-END
           STOP RUN.

      *> Values are numbers, so no URL decoding is attempted: anything
      *> percent-encoded simply fails numeric validation.
       READ-QUERY.
           ACCEPT WS-QUERY FROM ENVIRONMENT "QUERY_STRING"
               ON EXCEPTION MOVE SPACES TO WS-QUERY
           END-ACCEPT
           IF WS-QUERY = SPACES
               EXIT PARAGRAPH
           END-IF
           UNSTRING WS-QUERY DELIMITED BY "&"
               INTO WS-PAIR(1) WS-PAIR(2) WS-PAIR(3)
                    WS-PAIR(4) WS-PAIR(5) WS-PAIR(6)
           END-UNSTRING
           PERFORM VARYING WS-PAIR-INDEX FROM 1 BY 1
                   UNTIL WS-PAIR-INDEX > 6
               MOVE SPACES TO WS-KEY WS-VALUE
               UNSTRING WS-PAIR(WS-PAIR-INDEX) DELIMITED BY "="
                   INTO WS-KEY WS-VALUE
               END-UNSTRING
      *>       A value too long for the request field is made invalid
      *>       rather than silently truncated into something valid.
               IF WS-VALUE(21:) NOT = SPACES
                   MOVE "X" TO WS-VALUE
               END-IF
               EVALUATE WS-KEY
                   WHEN "principal"
                       MOVE WS-VALUE TO AR-PRINCIPAL-TEXT
                       SET WS-INPUT-GIVEN TO TRUE
                   WHEN "rate"
                       MOVE WS-VALUE TO AR-RATE-TEXT
                       SET WS-INPUT-GIVEN TO TRUE
                   WHEN "term"
                       MOVE WS-VALUE TO AR-TERM-TEXT
                       SET WS-INPUT-GIVEN TO TRUE
               END-EVALUATE
           END-PERFORM.

      *> Only echo what the user typed if it cannot break out of the
      *> HTML attribute it is placed in.
       PREPARE-FORM-VALUES.
           IF AR-PRINCIPAL-TEXT IS FORM-SAFE
               MOVE AR-PRINCIPAL-TEXT TO WS-FORM-PRINCIPAL
           END-IF
           IF AR-RATE-TEXT IS FORM-SAFE
               MOVE AR-RATE-TEXT TO WS-FORM-RATE
           END-IF
           IF AR-TERM-TEXT IS FORM-SAFE
               MOVE AR-TERM-TEXT TO WS-FORM-TERM
           END-IF.

       PAGE-START.
           DISPLAY "Content-Type: text/html; charset=utf-8"
      *>   The trailing line feed produces the blank line that ends the
      *>   CGI headers; DISPLAY of an empty literal would emit a space.
           DISPLAY "Cache-Control: no-store" X"0A"
           DISPLAY "<!doctype html>"
           DISPLAY '<html lang="en"><head><meta charset="utf-8">'
           DISPLAY '<meta name="viewport" content="width=device-width,initial-scale=1">'
           DISPLAY "<title>Loan Amortisation</title>"
           DISPLAY "<style>"
           DISPLAY ":root{--paper:#fbfbf4;--ink:#1d2a1f;--muted:#5d6b5f;--bar:#dcefd9;--rule:#9fb89c;--err:#a12a1f}"
           DISPLAY "@media (prefers-color-scheme:dark){:root{--paper:#0e1410;--ink:#b6f5b0;--muted:#6f9b6b;--bar:#16261a;--rule:#2d4a31;--err:#ff8a7a}}"
           DISPLAY "*{box-sizing:border-box}"
           DISPLAY "body{margin:0;background:var(--paper);color:var(--ink);font:15px/1.5 ui-monospace,SFMono-Regular,Menlo,Consolas,monospace}"
           DISPLAY "main{max-width:880px;margin:0 auto;padding:32px 16px 64px}"
           DISPLAY "h1{font-size:20px;letter-spacing:.12em;margin:0 0 4px}"
           DISPLAY ".sub{color:var(--muted);margin:0 0 24px}"
           DISPLAY "form{display:flex;flex-wrap:wrap;gap:12px;align-items:end;margin-bottom:24px}"
           DISPLAY "label{display:flex;flex-direction:column;gap:4px;font-size:12px;letter-spacing:.08em;color:var(--muted)}"
           DISPLAY "input,button{font:inherit;color:var(--ink);background:transparent;border:1px solid var(--rule);padding:8px 10px;border-radius:2px}"
           DISPLAY "input{width:11em}button{cursor:pointer;letter-spacing:.08em}button:hover{background:var(--bar)}"
           DISPLAY ".error{color:var(--err)}"
           DISPLAY "dl{display:grid;grid-template-columns:max-content max-content;gap:2px 24px;margin:0 0 24px}"
           DISPLAY "dt{color:var(--muted)}dd{margin:0;text-align:right;font-variant-numeric:tabular-nums}"
           DISPLAY ".scroll{overflow-x:auto}"
           DISPLAY "table{border-collapse:collapse;width:100%;font-variant-numeric:tabular-nums}"
           DISPLAY "th,td{padding:2px 10px;text-align:right;white-space:nowrap}"
           DISPLAY "th{border-bottom:1px solid var(--rule);font-weight:normal;color:var(--muted);letter-spacing:.08em}"
           DISPLAY "tbody tr:nth-child(6n+1),tbody tr:nth-child(6n+2),tbody tr:nth-child(6n+3){background:var(--bar)}"
           DISPLAY "</style></head><body><main>"
           DISPLAY "<h1>LOAN AMORTISATION</h1>"
           DISPLAY '<p class="sub">Calculated by a GnuCOBOL program over CGI.</p>'.

       PAGE-FORM.
           DISPLAY '<form method="get" action="/cgi-bin/amortise">'
           DISPLAY '<label>PRINCIPAL<input name="principal" inputmode="decimal" required value="'
                   FUNCTION TRIM(WS-FORM-PRINCIPAL) '"></label>'
           DISPLAY '<label>ANNUAL RATE %<input name="rate" inputmode="decimal" required value="'
                   FUNCTION TRIM(WS-FORM-RATE) '"></label>'
           DISPLAY '<label>TERM (MONTHS)<input name="term" inputmode="numeric" required value="'
                   FUNCTION TRIM(WS-FORM-TERM) '"></label>'
           DISPLAY "<button>CALCULATE</button>"
           DISPLAY "</form>".

       PAGE-SUMMARY.
           DISPLAY "<dl>"
           MOVE AS-PRINCIPAL TO WS-ED-TOTAL
           DISPLAY "<dt>Principal</dt><dd>" FUNCTION TRIM(WS-ED-TOTAL) "</dd>"
           MOVE AS-ANNUAL-RATE TO WS-ED-RATE
           DISPLAY "<dt>Annual rate</dt><dd>" FUNCTION TRIM(WS-ED-RATE) " %</dd>"
           MOVE AS-TERM-MONTHS TO WS-ED-PERIOD
           DISPLAY "<dt>Term</dt><dd>" FUNCTION TRIM(WS-ED-PERIOD) " months</dd>"
           MOVE AS-PAYMENT TO WS-ED-TOTAL
           DISPLAY "<dt>Monthly payment</dt><dd>" FUNCTION TRIM(WS-ED-TOTAL) "</dd>"
           MOVE AS-TOTAL-INTEREST TO WS-ED-TOTAL
           DISPLAY "<dt>Total interest</dt><dd>" FUNCTION TRIM(WS-ED-TOTAL) "</dd>"
           MOVE AS-TOTAL-PAID TO WS-ED-TOTAL
           DISPLAY "<dt>Total repaid</dt><dd>" FUNCTION TRIM(WS-ED-TOTAL) "</dd>"
           DISPLAY "</dl>".

       PAGE-SCHEDULE.
           DISPLAY '<div class="scroll"><table>'
           DISPLAY "<thead><tr><th>PERIOD</th><th>PAYMENT</th><th>INTEREST</th>"
                   "<th>PRINCIPAL</th><th>BALANCE</th></tr></thead><tbody>"
           PERFORM VARYING WS-ROW FROM 1 BY 1 UNTIL WS-ROW > AS-ROW-COUNT
               MOVE WS-ROW                   TO WS-ED-PERIOD
               MOVE AS-ROW-PAYMENT(WS-ROW)   TO WS-ED-PAYMENT
               MOVE AS-ROW-INTEREST(WS-ROW)  TO WS-ED-INTEREST
               MOVE AS-ROW-PRINCIPAL(WS-ROW) TO WS-ED-PRINCIPAL
               MOVE AS-ROW-BALANCE(WS-ROW)   TO WS-ED-BALANCE
               DISPLAY "<tr><td>" FUNCTION TRIM(WS-ED-PERIOD)
                       "</td><td>" FUNCTION TRIM(WS-ED-PAYMENT)
                       "</td><td>" FUNCTION TRIM(WS-ED-INTEREST)
                       "</td><td>" FUNCTION TRIM(WS-ED-PRINCIPAL)
                       "</td><td>" FUNCTION TRIM(WS-ED-BALANCE)
                       "</td></tr>"
           END-PERFORM
           DISPLAY "</tbody></table></div>".

       PAGE-END.
           DISPLAY "</main></body></html>".

       END PROGRAM AMORTWEB.
