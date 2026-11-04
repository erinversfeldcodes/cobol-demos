      *> AMORTCALC result: validated inputs, totals and the schedule.
      *> A row payment is one digit wider than the principal because the
      *> final payment can be the whole principal plus a month's interest.
       01  AMORT-RESULT.
           05  AS-STATUS               PIC X(2).
               88  AS-OK                         VALUE "00".
               88  AS-BAD-PRINCIPAL              VALUE "10".
               88  AS-BAD-RATE                   VALUE "20".
               88  AS-BAD-TERM                   VALUE "30".
               88  AS-PAYMENT-TOO-SMALL          VALUE "40".
           05  AS-MESSAGE              PIC X(80).
           05  AS-PRINCIPAL            PIC 9(9)V99.
           05  AS-ANNUAL-RATE          PIC 9(3)V9(4).
           05  AS-TERM-MONTHS          PIC 9(3).
           05  AS-PAYMENT              PIC 9(9)V99.
           05  AS-TOTAL-INTEREST       PIC 9(11)V99.
           05  AS-TOTAL-PAID           PIC 9(11)V99.
           05  AS-ROW-COUNT            PIC 9(3).
           05  AS-ROW                  OCCURS 600 TIMES.
               10  AS-ROW-PAYMENT      PIC 9(10)V99.
               10  AS-ROW-INTEREST     PIC 9(9)V99.
               10  AS-ROW-PRINCIPAL    PIC 9(9)V99.
               10  AS-ROW-BALANCE      PIC 9(9)V99.
