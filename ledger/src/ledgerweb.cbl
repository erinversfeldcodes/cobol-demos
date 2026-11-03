       IDENTIFICATION DIVISION.
       PROGRAM-ID. LEDGERWEB.
      *> CGI front end. GET shows the input form filled with sample
      *> data; POST runs the batch on the submitted files and shows
      *> every report it produced.
      *>
      *> Environment, beyond the CGI variables:
      *>   LEDGER_SAMPLES   directory holding the sample files
      *>   LEDGER_RUN_DATE  fixed run date (YYYYMMDD), used by tests

       ENVIRONMENT DIVISION.
       INPUT-OUTPUT SECTION.
       FILE-CONTROL.
           SELECT STDIN-FILE ASSIGN TO KEYBOARD
               ORGANIZATION IS LINE SEQUENTIAL
               FILE STATUS IS WS-FS.
           SELECT TEXT-FILE ASSIGN TO WS-FILE-PATH
               ORGANIZATION IS LINE SEQUENTIAL
               FILE STATUS IS WS-FS.

       DATA DIVISION.
       FILE SECTION.
      *> Read as a file because ACCEPT stops at 8191 bytes.
       FD  STDIN-FILE.
       01  STDIN-REC                   PIC X(65536).
       FD  TEXT-FILE.
       01  TEXT-REC                    PIC X(256).

       WORKING-STORAGE SECTION.
       COPY "ledgreq.cpy".
       COPY "ledgres.cpy".

       01  WS-FS                       PIC XX.
       01  WS-EOF-FLAG                 PIC X.
           88  WS-EOF                            VALUE "Y".
       01  WS-METHOD                   PIC X(10).
       01  WS-CONTENT-LENGTH-TEXT      PIC X(10).
       01  WS-CONTENT-LENGTH           PIC 9(9).
       01  WS-MAX-BODY                 PIC 9(9) VALUE 60000.
       01  WS-BODY                     PIC X(65536).
       01  WS-SAMPLES-DIR              PIC X(200).
       01  WS-RUN-DATE-TEXT            PIC X(20).
       01  WS-ERROR                    PIC X(120).
       01  WS-PID                      PIC S9(9) COMP-5.
       01  WS-PID-TEXT                 PIC 9(9).
       01  WS-WORK-DIR                 PIC X(200).
       01  WS-FILE-PATH                PIC X(300).
       01  WS-FILE-NAME                PIC X(40).

       01  WS-FIELDS.
           05  WS-FIELD                PIC X(32000) OCCURS 4 TIMES.
       01  WS-FIELD-INDEX              PIC 9.
       01  WS-KEY                      PIC X(32).
       01  WS-RAW                      PIC X(32000).

      *> Decoded form fields, as text with LF line endings.
       01  WS-ACCOUNTS-TEXT            PIC X(32000).
       01  WS-ACCOUNTS-LEN             PIC 9(5).
       01  WS-TXNS-TEXT                PIC X(32000).
       01  WS-TXNS-LEN                 PIC 9(5).
       01  WS-TEXT                     PIC X(32000).
       01  WS-TEXT-LEN                 PIC 9(5).

       01  WS-I                        PIC 9(5).
       01  WS-RAW-LEN                  PIC 9(5).
       01  WS-CHAR                     PIC X.
       01  WS-HEX-DIGITS               PIC X(16) VALUE "0123456789ABCDEF".
       01  WS-HEX-CHAR                 PIC X.
       01  WS-HI                       PIC 99.
       01  WS-LO                       PIC 99.
       01  WS-LINE                     PIC X(256).
       01  WS-LINE-LEN                 PIC 9(3).
       01  WS-ESCAPED                  PIC X(1600).
       01  WS-ESCAPED-LEN              PIC 9(4).
       01  WS-J                        PIC 9(3).

       PROCEDURE DIVISION.
       MAIN-PROCEDURE.
           ACCEPT WS-METHOD FROM ENVIRONMENT "REQUEST_METHOD"
               ON EXCEPTION MOVE "GET" TO WS-METHOD
           END-ACCEPT
           IF WS-METHOD = "POST"
               PERFORM READ-FORM
           ELSE
               PERFORM LOAD-SAMPLES
           END-IF
           PERFORM PAGE-START
           PERFORM PAGE-FORM
           IF WS-ERROR NOT = SPACES
               DISPLAY '<p class="error">' FUNCTION TRIM(WS-ERROR) "</p>"
           ELSE
               IF WS-METHOD = "POST"
                   PERFORM RUN-BATCH
               END-IF
           END-IF
           DISPLAY "</main></body></html>"
           STOP RUN.

      *> ---------------------------------------------------------------
      *> Input.
      *> ---------------------------------------------------------------
       LOAD-SAMPLES.
           ACCEPT WS-SAMPLES-DIR FROM ENVIRONMENT "LEDGER_SAMPLES"
               ON EXCEPTION
                   MOVE "/usr/local/share/ledger/samples" TO WS-SAMPLES-DIR
           END-ACCEPT
           MOVE SPACES TO WS-FILE-PATH
           STRING FUNCTION TRIM(WS-SAMPLES-DIR) "/accounts.dat"
               DELIMITED BY SIZE INTO WS-FILE-PATH
           PERFORM LOAD-TEXT-FILE
           MOVE WS-TEXT TO WS-ACCOUNTS-TEXT
           MOVE WS-TEXT-LEN TO WS-ACCOUNTS-LEN
           MOVE SPACES TO WS-FILE-PATH
           STRING FUNCTION TRIM(WS-SAMPLES-DIR) "/transactions.dat"
               DELIMITED BY SIZE INTO WS-FILE-PATH
           PERFORM LOAD-TEXT-FILE
           MOVE WS-TEXT TO WS-TXNS-TEXT
           MOVE WS-TEXT-LEN TO WS-TXNS-LEN.

       LOAD-TEXT-FILE.
           MOVE SPACES TO WS-TEXT
           MOVE 0 TO WS-TEXT-LEN
           OPEN INPUT TEXT-FILE
           IF WS-FS NOT = "00"
               EXIT PARAGRAPH
           END-IF
           MOVE "N" TO WS-EOF-FLAG
           PERFORM UNTIL WS-EOF
               READ TEXT-FILE
                   AT END SET WS-EOF TO TRUE
                   NOT AT END
                       MOVE TEXT-REC TO WS-LINE
                       PERFORM APPEND-LINE-TO-TEXT
               END-READ
           END-PERFORM
           CLOSE TEXT-FILE.

       APPEND-LINE-TO-TEXT.
           MOVE FUNCTION LENGTH(FUNCTION TRIM(WS-LINE TRAILING))
             TO WS-LINE-LEN
           IF WS-LINE = SPACES
               MOVE 0 TO WS-LINE-LEN
           END-IF
           IF WS-TEXT-LEN + WS-LINE-LEN + 1 <= 32000
               IF WS-LINE-LEN > 0
                   MOVE WS-LINE(1:WS-LINE-LEN)
                     TO WS-TEXT(WS-TEXT-LEN + 1:WS-LINE-LEN)
                   ADD WS-LINE-LEN TO WS-TEXT-LEN
               END-IF
               ADD 1 TO WS-TEXT-LEN
               MOVE X"0A" TO WS-TEXT(WS-TEXT-LEN:1)
           END-IF.

      *> The body is application/x-www-form-urlencoded with two fields,
      *> accounts and transactions.
       READ-FORM.
           ACCEPT WS-CONTENT-LENGTH-TEXT FROM ENVIRONMENT "CONTENT_LENGTH"
               ON EXCEPTION MOVE "0" TO WS-CONTENT-LENGTH-TEXT
           END-ACCEPT
           IF FUNCTION TEST-NUMVAL(WS-CONTENT-LENGTH-TEXT) NOT = 0
               MOVE "0" TO WS-CONTENT-LENGTH-TEXT
           END-IF
           COMPUTE WS-CONTENT-LENGTH =
               FUNCTION NUMVAL(WS-CONTENT-LENGTH-TEXT)
           IF WS-CONTENT-LENGTH > WS-MAX-BODY
               MOVE "Input is too large: keep both files under 30,000 characters"
                 TO WS-ERROR
               EXIT PARAGRAPH
           END-IF

           MOVE SPACES TO WS-BODY
           IF WS-CONTENT-LENGTH > 0
               OPEN INPUT STDIN-FILE
               READ STDIN-FILE INTO WS-BODY
                   AT END MOVE SPACES TO WS-BODY
               END-READ
               CLOSE STDIN-FILE
               MOVE SPACES TO WS-BODY(WS-CONTENT-LENGTH + 1:)
           END-IF

           UNSTRING WS-BODY DELIMITED BY "&"
               INTO WS-FIELD(1) WS-FIELD(2) WS-FIELD(3) WS-FIELD(4)
           END-UNSTRING
           PERFORM VARYING WS-FIELD-INDEX FROM 1 BY 1
                   UNTIL WS-FIELD-INDEX > 4
               MOVE SPACES TO WS-KEY WS-RAW
               UNSTRING WS-FIELD(WS-FIELD-INDEX) DELIMITED BY "="
                   INTO WS-KEY WS-RAW
               END-UNSTRING
               EVALUATE WS-KEY
                   WHEN "accounts"
                       PERFORM URL-DECODE
                       MOVE WS-TEXT TO WS-ACCOUNTS-TEXT
                       MOVE WS-TEXT-LEN TO WS-ACCOUNTS-LEN
                   WHEN "transactions"
                       PERFORM URL-DECODE
                       MOVE WS-TEXT TO WS-TXNS-TEXT
                       MOVE WS-TEXT-LEN TO WS-TXNS-LEN
               END-EVALUATE
           END-PERFORM.

      *> WS-RAW (percent-encoded) to WS-TEXT. Carriage returns from the
      *> browser's CRLF line endings are dropped.
       URL-DECODE.
           MOVE SPACES TO WS-TEXT
           MOVE 0 TO WS-TEXT-LEN
           MOVE 0 TO WS-RAW-LEN
           IF WS-RAW NOT = SPACES
               MOVE FUNCTION LENGTH(FUNCTION TRIM(WS-RAW TRAILING))
                 TO WS-RAW-LEN
           END-IF
           MOVE 1 TO WS-I
           PERFORM UNTIL WS-I > WS-RAW-LEN
               MOVE WS-RAW(WS-I:1) TO WS-CHAR
               EVALUATE TRUE
                   WHEN WS-CHAR = "+"
                       MOVE SPACE TO WS-CHAR
                   WHEN WS-CHAR = "%" AND WS-I + 2 <= WS-RAW-LEN
      *>               A digit's value is its offset in WS-HEX-DIGITS;
      *>               16 means it was not a hex digit.
                       MOVE 0 TO WS-HI WS-LO
                       MOVE FUNCTION UPPER-CASE(WS-RAW(WS-I + 1:1))
                         TO WS-HEX-CHAR
                       INSPECT WS-HEX-DIGITS TALLYING WS-HI
                           FOR CHARACTERS BEFORE INITIAL WS-HEX-CHAR
                       MOVE FUNCTION UPPER-CASE(WS-RAW(WS-I + 2:1))
                         TO WS-HEX-CHAR
                       INSPECT WS-HEX-DIGITS TALLYING WS-LO
                           FOR CHARACTERS BEFORE INITIAL WS-HEX-CHAR
                       IF WS-HI < 16 AND WS-LO < 16
                           MOVE FUNCTION CHAR(WS-HI * 16 + WS-LO + 1)
                             TO WS-CHAR
                           ADD 2 TO WS-I
                       END-IF
               END-EVALUATE
               IF WS-CHAR NOT = X"0D" AND WS-TEXT-LEN < 32000
                   ADD 1 TO WS-TEXT-LEN
                   MOVE WS-CHAR TO WS-TEXT(WS-TEXT-LEN:1)
               END-IF
               ADD 1 TO WS-I
           END-PERFORM.

      *> ---------------------------------------------------------------
      *> Running the batch in a private working directory.
      *> ---------------------------------------------------------------
       RUN-BATCH.
           CALL "C$GETPID" RETURNING WS-PID
           MOVE WS-PID TO WS-PID-TEXT
           STRING "/tmp/ledger-" WS-PID-TEXT
               DELIMITED BY SIZE INTO WS-WORK-DIR
           CALL "CBL_CREATE_DIR" USING WS-WORK-DIR

           MOVE "accounts.dat" TO WS-FILE-NAME
           PERFORM BUILD-FILE-PATH
           MOVE WS-ACCOUNTS-TEXT TO WS-TEXT
           MOVE WS-ACCOUNTS-LEN TO WS-TEXT-LEN
           PERFORM SAVE-TEXT-FILE
           MOVE WS-FILE-PATH TO LR-MASTER-PATH

           MOVE "transactions.dat" TO WS-FILE-NAME
           PERFORM BUILD-FILE-PATH
           MOVE WS-TXNS-TEXT TO WS-TEXT
           MOVE WS-TXNS-LEN TO WS-TEXT-LEN
           PERFORM SAVE-TEXT-FILE
           MOVE WS-FILE-PATH TO LR-TXN-PATH

           MOVE WS-WORK-DIR TO LR-OUT-DIR
           PERFORM SET-RUN-DATE
           CALL "LEDGRUN" USING LEDGER-REQUEST LEDGER-RESULT

           DISPLAY "<h2>CONTROL REPORT</h2>"
           MOVE "control.txt" TO WS-FILE-NAME
           PERFORM SHOW-FILE
           IF NOT LS-ABORTED
               DISPLAY "<h2>EXCEPTIONS</h2>"
               MOVE "exceptions.txt" TO WS-FILE-NAME
               PERFORM SHOW-FILE
               DISPLAY "<h2>STATEMENTS</h2>"
               MOVE "statements.txt" TO WS-FILE-NAME
               PERFORM SHOW-FILE
               DISPLAY "<h2>NEW MASTER FILE</h2>"
               MOVE "accounts.new.dat" TO WS-FILE-NAME
               PERFORM SHOW-FILE
           END-IF
           PERFORM REMOVE-WORK-DIR.

       SET-RUN-DATE.
           MOVE SPACES TO WS-RUN-DATE-TEXT
           ACCEPT WS-RUN-DATE-TEXT FROM ENVIRONMENT "LEDGER_RUN_DATE"
               ON EXCEPTION MOVE SPACES TO WS-RUN-DATE-TEXT
           END-ACCEPT
           IF WS-RUN-DATE-TEXT(1:8) IS NUMERIC
              AND WS-RUN-DATE-TEXT(9:) = SPACES
               MOVE WS-RUN-DATE-TEXT(1:8) TO LR-RUN-DATE
           ELSE
               MOVE FUNCTION CURRENT-DATE(1:8) TO LR-RUN-DATE
           END-IF.

       BUILD-FILE-PATH.
           MOVE SPACES TO WS-FILE-PATH
           STRING FUNCTION TRIM(WS-WORK-DIR) "/" FUNCTION TRIM(WS-FILE-NAME)
               DELIMITED BY SIZE INTO WS-FILE-PATH.

      *> Writes WS-TEXT to WS-FILE-PATH, one record per line.
       SAVE-TEXT-FILE.
           OPEN OUTPUT TEXT-FILE
           MOVE SPACES TO WS-LINE
           MOVE 0 TO WS-LINE-LEN
           PERFORM VARYING WS-I FROM 1 BY 1 UNTIL WS-I > WS-TEXT-LEN
               IF WS-TEXT(WS-I:1) = X"0A"
                   WRITE TEXT-REC FROM WS-LINE
                   MOVE SPACES TO WS-LINE
                   MOVE 0 TO WS-LINE-LEN
               ELSE
                   IF WS-LINE-LEN < 256
                       ADD 1 TO WS-LINE-LEN
                       MOVE WS-TEXT(WS-I:1) TO WS-LINE(WS-LINE-LEN:1)
                   END-IF
               END-IF
           END-PERFORM
           IF WS-LINE-LEN > 0
               WRITE TEXT-REC FROM WS-LINE
           END-IF
           CLOSE TEXT-FILE.

       REMOVE-WORK-DIR.
           MOVE "accounts.dat" TO WS-FILE-NAME
           PERFORM DELETE-WORK-FILE
           MOVE "transactions.dat" TO WS-FILE-NAME
           PERFORM DELETE-WORK-FILE
           MOVE "accounts.new.dat" TO WS-FILE-NAME
           PERFORM DELETE-WORK-FILE
           MOVE "statements.txt" TO WS-FILE-NAME
           PERFORM DELETE-WORK-FILE
           MOVE "exceptions.txt" TO WS-FILE-NAME
           PERFORM DELETE-WORK-FILE
           MOVE "control.txt" TO WS-FILE-NAME
           PERFORM DELETE-WORK-FILE
           CALL "CBL_DELETE_DIR" USING WS-WORK-DIR.

       DELETE-WORK-FILE.
           PERFORM BUILD-FILE-PATH
           CALL "CBL_DELETE_FILE" USING WS-FILE-PATH.

      *> ---------------------------------------------------------------
      *> Output.
      *> ---------------------------------------------------------------
       SHOW-FILE.
           PERFORM BUILD-FILE-PATH
           DISPLAY "<pre>" WITH NO ADVANCING
           OPEN INPUT TEXT-FILE
           IF WS-FS = "00"
               MOVE "N" TO WS-EOF-FLAG
               PERFORM UNTIL WS-EOF
                   READ TEXT-FILE
                       AT END SET WS-EOF TO TRUE
                       NOT AT END
                           MOVE TEXT-REC TO WS-LINE
                           PERFORM DISPLAY-ESCAPED-LINE
                   END-READ
               END-PERFORM
               CLOSE TEXT-FILE
           END-IF
           DISPLAY "</pre>".

      *> Shows WS-TEXT line by line, escaped, e.g. inside a textarea.
       SHOW-TEXT.
           MOVE SPACES TO WS-LINE
           MOVE 0 TO WS-LINE-LEN
           PERFORM VARYING WS-I FROM 1 BY 1 UNTIL WS-I > WS-TEXT-LEN
               IF WS-TEXT(WS-I:1) = X"0A"
                   PERFORM DISPLAY-ESCAPED-LINE
                   MOVE SPACES TO WS-LINE
                   MOVE 0 TO WS-LINE-LEN
               ELSE
                   IF WS-LINE-LEN < 256
                       ADD 1 TO WS-LINE-LEN
                       MOVE WS-TEXT(WS-I:1) TO WS-LINE(WS-LINE-LEN:1)
                   END-IF
               END-IF
           END-PERFORM
           IF WS-LINE-LEN > 0
               PERFORM DISPLAY-ESCAPED-LINE
           END-IF.

       DISPLAY-ESCAPED-LINE.
           MOVE SPACES TO WS-ESCAPED
           MOVE 0 TO WS-ESCAPED-LEN
           IF WS-LINE = SPACES
               DISPLAY " "
               EXIT PARAGRAPH
           END-IF
           MOVE FUNCTION LENGTH(FUNCTION TRIM(WS-LINE TRAILING))
             TO WS-LINE-LEN
           PERFORM VARYING WS-J FROM 1 BY 1 UNTIL WS-J > WS-LINE-LEN
               EVALUATE WS-LINE(WS-J:1)
                   WHEN "&"
                       MOVE "&amp;" TO WS-ESCAPED(WS-ESCAPED-LEN + 1:5)
                       ADD 5 TO WS-ESCAPED-LEN
                   WHEN "<"
                       MOVE "&lt;" TO WS-ESCAPED(WS-ESCAPED-LEN + 1:4)
                       ADD 4 TO WS-ESCAPED-LEN
                   WHEN ">"
                       MOVE "&gt;" TO WS-ESCAPED(WS-ESCAPED-LEN + 1:4)
                       ADD 4 TO WS-ESCAPED-LEN
                   WHEN '"'
                       MOVE "&quot;" TO WS-ESCAPED(WS-ESCAPED-LEN + 1:6)
                       ADD 6 TO WS-ESCAPED-LEN
                   WHEN OTHER
                       ADD 1 TO WS-ESCAPED-LEN
                       MOVE WS-LINE(WS-J:1)
                         TO WS-ESCAPED(WS-ESCAPED-LEN:1)
               END-EVALUATE
           END-PERFORM
           DISPLAY WS-ESCAPED(1:WS-ESCAPED-LEN).

       PAGE-START.
           DISPLAY "Content-Type: text/html; charset=utf-8"
      *>   The trailing line feed produces the blank line that ends the
      *>   CGI headers; DISPLAY of an empty literal would emit a space.
           DISPLAY "Cache-Control: no-store" X"0A"
           DISPLAY "<!doctype html>"
           DISPLAY '<html lang="en"><head><meta charset="utf-8">'
           DISPLAY '<meta name="viewport" content="width=device-width,initial-scale=1">'
           DISPLAY "<title>Ledger Batch</title>"
           DISPLAY "<style>"
           DISPLAY ":root{--paper:#fbfbf4;--ink:#1d2a1f;--muted:#5d6b5f;--bar:#dcefd9;--rule:#9fb89c;--err:#a12a1f}"
           DISPLAY "@media (prefers-color-scheme:dark){:root{--paper:#0e1410;--ink:#b6f5b0;--muted:#6f9b6b;--bar:#16261a;--rule:#2d4a31;--err:#ff8a7a}}"
           DISPLAY "*{box-sizing:border-box}"
           DISPLAY "body{margin:0;background:var(--paper);color:var(--ink);font:14px/1.5 ui-monospace,SFMono-Regular,Menlo,Consolas,monospace}"
           DISPLAY "main{max-width:1000px;margin:0 auto;padding:32px 16px 64px}"
           DISPLAY "h1{font-size:20px;letter-spacing:.12em;margin:0 0 4px}"
           DISPLAY "h2{font-size:14px;letter-spacing:.12em;color:var(--muted);margin:32px 0 8px;font-weight:normal}"
           DISPLAY ".sub{color:var(--muted);margin:0 0 24px}"
           DISPLAY "label{display:block;font-size:12px;letter-spacing:.08em;color:var(--muted);margin:16px 0 4px}"
           DISPLAY "textarea{display:block;width:100%;min-height:12em;font:inherit;font-size:13px;color:var(--ink);background:transparent;border:1px solid var(--rule);padding:8px;border-radius:2px;white-space:pre;overflow-x:auto}"
           DISPLAY "button{font:inherit;color:var(--ink);background:transparent;border:1px solid var(--rule);padding:8px 14px;border-radius:2px;cursor:pointer;letter-spacing:.08em;margin-top:16px}"
           DISPLAY "button:hover{background:var(--bar)}"
           DISPLAY ".error{color:var(--err)}"
           DISPLAY "pre{margin:0;padding:8px 0;overflow-x:auto;font-size:13px;line-height:1.5em;background:repeating-linear-gradient(var(--bar) 0 4.5em,transparent 4.5em 9em) 0 8px}"
           DISPLAY "</style></head><body><main>"
           DISPLAY "<h1>LEDGER BATCH</h1>"
           DISPLAY '<p class="sub">A GnuCOBOL sequential master-file update, served over CGI. Edit the fixed-width files and run the batch.</p>'.

       PAGE-FORM.
           DISPLAY '<form method="post" action="/cgi-bin/ledger">'
           DISPLAY '<label for="accounts">ACCOUNT MASTER</label>'
           DISPLAY '<textarea id="accounts" name="accounts" spellcheck="false">'
           MOVE WS-ACCOUNTS-TEXT TO WS-TEXT
           MOVE WS-ACCOUNTS-LEN TO WS-TEXT-LEN
           PERFORM SHOW-TEXT
           DISPLAY "</textarea>"
           DISPLAY '<label for="transactions">TRANSACTIONS</label>'
           DISPLAY '<textarea id="transactions" name="transactions" spellcheck="false">'
           MOVE WS-TXNS-TEXT TO WS-TEXT
           MOVE WS-TXNS-LEN TO WS-TEXT-LEN
           PERFORM SHOW-TEXT
           DISPLAY "</textarea>"
           DISPLAY "<button>RUN BATCH</button>"
           DISPLAY "</form>".

       END PROGRAM LEDGERWEB.
