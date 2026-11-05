       IDENTIFICATION DIVISION.
       PROGRAM-ID. AMORTQRY.
      *> Reads principal=&rate=&term= from QUERY_STRING into an
      *> AMORTCALC request. Shared by the HTML page and the JSON API so
      *> both accept exactly the same parameters.

       DATA DIVISION.
       WORKING-STORAGE SECTION.
       01  WS-QUERY                    PIC X(1024).
       01  WS-PAIRS.
           05  WS-PAIR                 PIC X(256) OCCURS 6 TIMES.
       01  WS-PAIR-INDEX               PIC 9.
       01  WS-KEY                      PIC X(32).
       01  WS-VALUE                    PIC X(256).

       LINKAGE SECTION.
       COPY "amortreq.cpy".
      *> "Y" when any of the three parameters was present.
       01  LS-HAS-INPUT                PIC X.

       PROCEDURE DIVISION USING AMORT-REQUEST LS-HAS-INPUT.
       MAIN-PROCEDURE.
           MOVE SPACES TO AMORT-REQUEST
           MOVE "N" TO LS-HAS-INPUT
           PERFORM READ-QUERY
           GOBACK.

      *> Values are numbers, so no URL decoding is attempted: anything
      *> percent-encoded simply fails numeric validation.
       READ-QUERY.
           ACCEPT WS-QUERY FROM ENVIRONMENT "QUERY_STRING"
               ON EXCEPTION MOVE SPACES TO WS-QUERY
           END-ACCEPT
           IF WS-QUERY = SPACES
               EXIT PARAGRAPH
           END-IF
           MOVE SPACES TO WS-PAIRS
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
                       MOVE "Y" TO LS-HAS-INPUT
                   WHEN "rate"
                       MOVE WS-VALUE TO AR-RATE-TEXT
                       MOVE "Y" TO LS-HAS-INPUT
                   WHEN "term"
                       MOVE WS-VALUE TO AR-TERM-TEXT
                       MOVE "Y" TO LS-HAS-INPUT
               END-EVALUATE
           END-PERFORM.

       END PROGRAM AMORTQRY.
