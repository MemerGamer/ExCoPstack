IDENTIFICATION DIVISION.
       PROGRAM-ID. EXCOP-WANTED-PURE-COBOL.

       ENVIRONMENT DIVISION.
       CONFIGURATION SECTION.
       INPUT-OUTPUT SECTION.
       FILE-CONTROL.
           SELECT HTML-FILE ASSIGN TO "/app/index.html"
                  ORGANIZATION IS LINE SEQUENTIAL
                  FILE STATUS IS FILE-STATUS.

       DATA DIVISION.
       FILE SECTION.
       FD  HTML-FILE.
       01  HTML-FILE-REC        PIC X(4096).
       WORKING-STORAGE SECTION.
       77  PORT                    PIC S9(9) COMP-5 VALUE 8080.
       77  SRVFD                   PIC S9(9) COMP-5 VALUE -1.
       77  CLIFD                   PIC S9(9) COMP-5 VALUE -1.

       77  AF-INET                 PIC S9(9) COMP-5 VALUE 2.
       77  SOCK-STREAM             PIC S9(9) COMP-5 VALUE 1.
       77  SOL-SOCKET              PIC S9(9) COMP-5 VALUE 1.
       77  SO-REUSEADDR            PIC S9(9) COMP-5 VALUE 2.

       77  REUSE-OPT               PIC S9(9) COMP-5 VALUE 1.
       77  OPTLEN                  PIC S9(9) COMP-5 VALUE 4.
       77  RET                     PIC S9(9) COMP-5 VALUE 0.
       77  TMP32                   PIC S9(9) COMP-5 VALUE 0.

       01  REQ                     PIC X(8192) VALUE SPACES.
       77  REQ-LEN                 PIC S9(9) COMP-5 VALUE 0.
       01  RECV-BUF                PIC X(4096) VALUE SPACES.
       01  HTTP-METHOD             PIC X(8) VALUE SPACES.
       01  PATH                    PIC X(512) VALUE SPACES.
       01  BODY                    PIC X(65535) VALUE SPACES.

       01  HTML                    PIC X(65536) VALUE SPACES.
       01  FIELD                   PIC X(4096) VALUE SPACES.
       01  NAME                    PIC X(1024) VALUE SPACES.
       01  BOUNTY                  PIC X(1024) VALUE SPACES.

       01  API-BASE                PIC X(256) VALUE SPACES.
       01  API-BASE-ENV            PIC X(256) VALUE SPACES.
       01  CMD                     PIC X(8192) VALUE SPACES.

       77  CRLF                    PIC X(2) VALUE X"0D0A".

       77  I                       PIC S9(9) COMP-5 VALUE 0.
       77  J                       PIC S9(9) COMP-5 VALUE 0.
       77  P                       PIC S9(9) COMP-5 VALUE 0.
       77  K                       PIC S9(9) COMP-5 VALUE 0.
       77  OUT-PTR                 PIC S9(9) COMP-5 VALUE 1.
       77  HTML-PTR                PIC S9(9) COMP-5 VALUE 1.

       77  CONTENT-LEN             PIC S9(9) COMP-5 VALUE 0.
       77  SEND-LEN                PIC S9(9) COMP-5 VALUE 0.
       77  HEAD-END                PIC S9(9) COMP-5 VALUE 0.

       01  SERVER-ADDRESS.
           05  SA-FAMILY           PIC 9(4) COMP-5 VALUE 2.
           05  SA-PORT             PIC 9(4) COMP-5.
           05  SA-ADDR             PIC 9(8) COMP-5 VALUE 0.
           05  FILLER              PIC X(8) VALUE SPACES.
       01  CLIENT-ADDR.
           05  CA-FAMILY           PIC 9(4) COMP-5.
           05  CA-PORT             PIC 9(4) COMP-5.
           05  CA-ADDR             PIC 9(8) COMP-5.
           05  CA-FILLER           PIC X(8).
       77  SA-LEN                  PIC 9(9) COMP-5 VALUE 16.
       77  CA-LEN                  PIC 9(9) COMP-5 VALUE 16.
       77  PORT-NETWORK            PIC 9(4) COMP-5 VALUE 0.

       01  HX                      PIC X(2) VALUE SPACES.
       01  H1                      PIC X VALUE SPACE.
       01  H2                      PIC X VALUE SPACE.
       01  HEX-BYTE                PIC X VALUE SPACE.
       77  N1                      PIC S9(9) COMP-5 VALUE 0.
       77  N2                      PIC S9(9) COMP-5 VALUE 0.
       01  CURR-CHAR               PIC X VALUE SPACE.
       01  OUT-FLD                 PIC X(4096) VALUE SPACES.

       01  HTML-FILE-PATH          PIC X(256) VALUE "/app/index.html".
       01  FILE-STATUS              PIC XX VALUE SPACES.
       01  LINE-BUF                PIC X(4096) VALUE SPACES.

       PROCEDURE DIVISION.
       MAIN.
           DISPLAY "MAIN: Starting"
           *> API_BASE is set via environment variable in deployment
           *> Default to service name for Kubernetes (will be overridden by env var)
           MOVE "http://php-api-service:9000" TO API-BASE
           DISPLAY "MAIN: API_BASE set to " API-BASE
           PERFORM INIT
           DISPLAY "MAIN: After INIT, starting ACCEPT-LOOP"
           PERFORM ACCEPT-LOOP
           STOP RUN.

       INIT.
           CALL "socket" USING
                BY VALUE AF-INET
                BY VALUE SOCK-STREAM
                BY VALUE 0
                RETURNING SRVFD
           END-CALL
           IF SRVFD < 0
              DISPLAY "socket() failed"
              STOP RUN
           END-IF

           CALL "setsockopt" USING
                BY VALUE SRVFD
                BY VALUE SOL-SOCKET
                BY VALUE SO-REUSEADDR
                BY REFERENCE REUSE-OPT
                BY VALUE OPTLEN
                RETURNING RET
           END-CALL

           MOVE FUNCTION BYTE-LENGTH(SERVER-ADDRESS) TO SA-LEN
           COMPUTE PORT-NETWORK =
               FUNCTION MOD(PORT, 256) * 256 + PORT / 256
           MOVE PORT-NETWORK TO SA-PORT

           CALL "bind" USING
                BY VALUE SRVFD
                BY REFERENCE SERVER-ADDRESS
                BY VALUE SA-LEN
                RETURNING RET
           END-CALL
           IF RET < 0
              DISPLAY "bind() failed"
              STOP RUN
           END-IF

           CALL "listen" USING
                BY VALUE SRVFD
                BY VALUE 64
                RETURNING RET
           END-CALL
           IF RET < 0
              DISPLAY "listen() failed"
              STOP RUN
           END-IF

           DISPLAY "COBOL server on :8080; API " API-BASE.
           DISPLAY "INIT: Completed successfully".
       
       ACCEPT-LOOP.
           DISPLAY "ACCEPT-LOOP: Entering loop"
           PERFORM FOREVER
              DISPLAY "ACCEPT-LOOP: Before accept() call"
              MOVE 16 TO CA-LEN
              DISPLAY "ACCEPT-LOOP: CA-LEN set to " CA-LEN
              DISPLAY "ACCEPT-LOOP: SRVFD = " SRVFD
              CALL "accept" USING
                   BY VALUE SRVFD
                   BY REFERENCE CLIENT-ADDR
                   BY REFERENCE CA-LEN
                   RETURNING CLIFD
              END-CALL
              DISPLAY "ACCEPT-LOOP: After accept(), CLIFD = " CLIFD
              IF CLIFD < 0
                 DISPLAY "ACCEPT-LOOP: Accept failed, continuing"
                 CONTINUE
              ELSE
                 DISPLAY "ACCEPT-LOOP: Client connected, handling"
                 PERFORM HANDLE-CLIENT
                 DISPLAY "ACCEPT-LOOP: After HANDLE-CLIENT"
                 CALL "close" USING BY VALUE CLIFD
                 END-CALL
                 DISPLAY "ACCEPT-LOOP: Client closed"
              END-IF
           END-PERFORM.

       HANDLE-CLIENT.
           DISPLAY "HANDLE-CLIENT: Starting"
           MOVE SPACES TO REQ
           DISPLAY "HANDLE-CLIENT: Calling RECV-REQUEST"
           PERFORM RECV-REQUEST
           DISPLAY "HANDLE-CLIENT: After RECV-REQUEST, REQ-LEN = " REQ-LEN
           IF REQ-LEN <= 0
              DISPLAY "HANDLE-CLIENT: No data received, exiting"
              EXIT PARAGRAPH
           END-IF
           DISPLAY "HANDLE-CLIENT: Calling PARSE-REQUEST"
           PERFORM PARSE-REQUEST
           DISPLAY "HANDLE-CLIENT: After PARSE-REQUEST"
           DISPLAY "HANDLE-CLIENT: HTTP-METHOD = '" HTTP-METHOD "' PATH = '" PATH(1:20) "'"
           DISPLAY "HANDLE-CLIENT: About to EVALUATE"
           EVALUATE TRUE
             WHEN HTTP-METHOD = "GET     " OR HTTP-METHOD = "GET"
                DISPLAY "HANDLE-CLIENT: Matched GET"
                IF PATH = "/"
                   DISPLAY "HANDLE-CLIENT: Path is /, calling ROUTE-INDEX"
                   PERFORM ROUTE-INDEX
                ELSE
                   DISPLAY "HANDLE-CLIENT: Path not /, calling RESP-404"
                   PERFORM RESP-404
                END-IF
             WHEN HTTP-METHOD = "POST    " OR HTTP-METHOD = "POST"
                DISPLAY "HANDLE-CLIENT: Matched POST"
                IF PATH = "/add"
                   DISPLAY "HANDLE-CLIENT: Path is /add"
                   PERFORM PARSE-FORM
                   PERFORM API-ADD
                   PERFORM RESP-REDIRECT
                ELSE
                   DISPLAY "HANDLE-CLIENT: Path not /add, calling RESP-404"
                   PERFORM RESP-404
                END-IF
             WHEN OTHER
                DISPLAY "HANDLE-CLIENT: Other method, calling RESP-404"
                PERFORM RESP-404
           END-EVALUATE
           DISPLAY "HANDLE-CLIENT: After EVALUATE".

       RECV-REQUEST.
           DISPLAY "RECV-REQUEST: Starting, CLIFD = " CLIFD
           MOVE 0 TO REQ-LEN CONTENT-LEN HEAD-END
           MOVE SPACES TO REQ
           DISPLAY "RECV-REQUEST: Calling recv()"
           CALL "recv" USING
                BY VALUE CLIFD
                BY REFERENCE REQ
                BY VALUE 8192
                BY VALUE 0
                RETURNING RET
           END-CALL
           DISPLAY "RECV-REQUEST: After recv(), RET = " RET
           IF RET <= 0
              DISPLAY "RECV-REQUEST: No data or error, exiting"
              MOVE 0 TO REQ-LEN
              EXIT PARAGRAPH
           END-IF
           MOVE RET TO REQ-LEN
           DISPLAY "RECV-REQUEST: Calling FIND-HEAD-END"
           PERFORM FIND-HEAD-END
           DISPLAY "RECV-REQUEST: Completed".

       FIND-HEAD-END.
           MOVE 1 TO I
           MOVE 0 TO HEAD-END
           IF REQ-LEN < 4
              EXIT PARAGRAPH
           END-IF
           PERFORM UNTIL I > REQ-LEN - 3 OR HEAD-END > 0
              IF I + 3 <= REQ-LEN
                 IF REQ(I:4) = X"0D0A0D0A"
                    COMPUTE HEAD-END = I + 4
                    IF HEAD-END > REQ-LEN
                       MOVE REQ-LEN TO HEAD-END
                    END-IF
                 END-IF
              END-IF
              ADD 1 TO I
           END-PERFORM.

       FIND-CONTENT-LENGTH.
           MOVE 0 TO CONTENT-LEN
           IF HEAD-END <= 0 OR HEAD-END > REQ-LEN
              EXIT PARAGRAPH
           END-IF
           MOVE 1 TO I
           PERFORM UNTIL I > HEAD-END - 4
              IF I + 14 <= REQ-LEN
                 IF FUNCTION UPPER-CASE(REQ(I:15)) = "CONTENT-LENGTH"
                    MOVE I TO J
                    PERFORM UNTIL J > HEAD-END OR J > REQ-LEN OR REQ(J:1) = ":"
                       ADD 1 TO J
                    END-PERFORM
                    IF J <= HEAD-END AND J <= REQ-LEN
                       ADD 1 TO J
                       PERFORM UNTIL J > HEAD-END OR J > REQ-LEN OR
                              (REQ(J:1) NOT = " " AND REQ(J:1) NOT = X"09")
                          ADD 1 TO J
                       END-PERFORM
                       MOVE 0 TO CONTENT-LEN
                       PERFORM UNTIL J > HEAD-END OR J > REQ-LEN OR
                              REQ(J:1) < "0" OR REQ(J:1) > "9"
                          COMPUTE CONTENT-LEN = CONTENT-LEN * 10
                                + FUNCTION ORD(REQ(J:1)) - 48
                          ADD 1 TO J
                       END-PERFORM
                       EXIT PERFORM
                    END-IF
                 END-IF
              END-IF
              ADD 1 TO I
           END-PERFORM.

       PARSE-REQUEST.
           DISPLAY "PARSE-REQUEST: Starting, REQ-LEN = " REQ-LEN " HEAD-END = " HEAD-END
           MOVE SPACES TO HTTP-METHOD PATH BODY
           DISPLAY "PARSE-REQUEST: About to UNSTRING"
           UNSTRING REQ DELIMITED BY ALL SPACES
             INTO HTTP-METHOD PATH
           END-UNSTRING
           DISPLAY "PARSE-REQUEST: After UNSTRING, HTTP-METHOD = '" HTTP-METHOD "'"
           IF HTTP-METHOD(1:3) = "GET"
              MOVE "GET" TO HTTP-METHOD
           END-IF
           IF HTTP-METHOD(1:4) = "POST"
              MOVE "POST" TO HTTP-METHOD
           END-IF
           DISPLAY "PARSE-REQUEST: Before body extraction"
           IF HEAD-END > 0 AND HEAD-END <= REQ-LEN
              DISPLAY "PARSE-REQUEST: Extracting body, HEAD-END = " HEAD-END " REQ-LEN = " REQ-LEN
              IF HEAD-END < REQ-LEN
                 COMPUTE I = REQ-LEN - HEAD-END + 1
                 DISPLAY "PARSE-REQUEST: Computed I = " I
                 IF I > LENGTH OF BODY
                    MOVE LENGTH OF BODY TO I
                 END-IF
                 IF I > 0 AND HEAD-END + I - 1 <= REQ-LEN
                    DISPLAY "PARSE-REQUEST: Moving body, I = " I
                    MOVE REQ(HEAD-END:I) TO BODY(1:I)
                    DISPLAY "PARSE-REQUEST: Body moved"
                 END-IF
              ELSE
                 DISPLAY "PARSE-REQUEST: No body (HEAD-END >= REQ-LEN)"
              END-IF
           END-IF
           DISPLAY "PARSE-REQUEST: Completed".

       ROUTE-INDEX.
           DISPLAY "ROUTE-INDEX: Starting"
           DISPLAY "ROUTE-INDEX: Calling RENDER-INDEX"
           PERFORM RENDER-INDEX
           DISPLAY "ROUTE-INDEX: After RENDER-INDEX"
           DISPLAY "ROUTE-INDEX: Calling SEND-HTML"
           PERFORM SEND-HTML
           DISPLAY "ROUTE-INDEX: After SEND-HTML, completed".

       PARSE-FORM.
           MOVE SPACES TO NAME BOUNTY
           MOVE BODY TO FIELD
           MOVE 1 TO P
           PERFORM UNTIL FIELD = SPACES
              MOVE SPACES TO LINE-BUF
              UNSTRING FIELD DELIMITED BY "&"
                INTO LINE-BUF
                WITH POINTER P
              END-UNSTRING
              IF LINE-BUF(1:5) = "name="
                 MOVE LINE-BUF(6:) TO NAME
              END-IF
              IF LINE-BUF(1:7) = "bounty="
                 MOVE LINE-BUF(8:) TO BOUNTY
              END-IF
              IF P > 0 AND P < FUNCTION LENGTH(FIELD)
                 COMPUTE I = P + 1
                 COMPUTE J = FUNCTION LENGTH(FIELD) - P
                 MOVE FIELD(I:J) TO LINE-BUF
                 MOVE LINE-BUF(1:J) TO FIELD
              ELSE
                 MOVE SPACES TO FIELD
              END-IF
           END-PERFORM
           MOVE NAME TO FIELD
           PERFORM URL-DECODE
           MOVE FIELD TO NAME
           MOVE BOUNTY TO FIELD
           PERFORM URL-DECODE
           MOVE FIELD TO BOUNTY.

       URL-DECODE.
           MOVE SPACES TO OUT-FLD
           MOVE 1 TO K
           MOVE 1 TO OUT-PTR
           PERFORM UNTIL K > FUNCTION LENGTH(FIELD)
              MOVE FIELD(K:1) TO CURR-CHAR
              EVALUATE CURR-CHAR
                WHEN "+"
                   STRING " " DELIMITED BY SIZE
                      INTO OUT-FLD WITH POINTER OUT-PTR
                   END-STRING
                   ADD 1 TO K
                WHEN "%"
                   IF K + 2 <= FUNCTION LENGTH(FIELD)
                      COMPUTE I = K + 1
                      MOVE FIELD(I:2) TO HX
                      PERFORM HEX2BYTE
                      STRING HEX-BYTE DELIMITED BY SIZE
                         INTO OUT-FLD WITH POINTER OUT-PTR
                      END-STRING
                      ADD 3 TO K
                   ELSE
                      ADD 1 TO K
                   END-IF
                WHEN OTHER
                   STRING CURR-CHAR DELIMITED BY SIZE
                      INTO OUT-FLD WITH POINTER OUT-PTR
                   END-STRING
                   ADD 1 TO K
              END-EVALUATE
           END-PERFORM
           MOVE OUT-FLD TO FIELD.

       HEX2BYTE.
           MOVE HX(1:1) TO H1
           MOVE HX(2:1) TO H2
           MOVE H1 TO CURR-CHAR
           PERFORM HEXVAL
           MOVE N1 TO N2
           MOVE H2 TO CURR-CHAR
           PERFORM HEXVAL
           COMPUTE N1 = N2 * 16 + N1
           MOVE FUNCTION CHAR(N1) TO HEX-BYTE.

       HEXVAL.
           EVALUATE TRUE
             WHEN CURR-CHAR >= "0" AND CURR-CHAR <= "9"
               COMPUTE N1 = FUNCTION ORD(CURR-CHAR) - 
                            FUNCTION ORD("0")
             WHEN CURR-CHAR >= "A" AND CURR-CHAR <= "F"
               COMPUTE N1 = 10 + FUNCTION ORD(CURR-CHAR) - 
                            FUNCTION ORD("A")
             WHEN CURR-CHAR >= "a" AND CURR-CHAR <= "f"
               COMPUTE N1 = 10 + FUNCTION ORD(CURR-CHAR) - 
                            FUNCTION ORD("a")
             WHEN OTHER
               MOVE 0 TO N1
           END-EVALUATE.

       API-ADD.
           MOVE SPACES TO CMD
           STRING "curl -fsS -X POST -H " DELIMITED BY SIZE
                  X"22" DELIMITED BY SIZE
                  "Content-Type: application/x-www-form-urlencoded" 
                  DELIMITED BY SIZE
                  X"22" DELIMITED BY SIZE
                  " -d " DELIMITED BY SIZE
                  X"22" DELIMITED BY SIZE
                  "name=" DELIMITED BY SIZE
                  FUNCTION SUBSTITUTE(NAME, "&", "%26") 
                  DELIMITED BY SIZE
                  "&bounty=" DELIMITED BY SIZE
                  FUNCTION SUBSTITUTE(BOUNTY, "&", "%26") 
                  DELIMITED BY SIZE
                  X"22" DELIMITED BY SIZE
                  " " DELIMITED BY SIZE
                  API-BASE DELIMITED BY SIZE
                  "/api/wanted" DELIMITED BY SIZE
             INTO CMD
           END-STRING
           CALL "system" USING BY REFERENCE CMD.

       RENDER-INDEX.
           DISPLAY "RENDER-INDEX: Starting"
           MOVE SPACES TO HTML
           MOVE 1 TO HTML-PTR
           DISPLAY "RENDER-INDEX: Building HTTP headers"
           STRING
            "HTTP/1.1 200 OK", CRLF,
            "Content-Type: text/html; charset=utf-8", CRLF,
            "Cache-Control: no-store", CRLF, CRLF
            DELIMITED BY SIZE INTO HTML WITH POINTER HTML-PTR
           END-STRING
           DISPLAY "RENDER-INDEX: Headers built, HTML-PTR = " HTML-PTR
           DISPLAY "RENDER-INDEX: Opening file"
           OPEN INPUT HTML-FILE
           DISPLAY "RENDER-INDEX: File opened, status = " FILE-STATUS
           IF FILE-STATUS = "00" OR FILE-STATUS = "05"
              DISPLAY "RENDER-INDEX: File opened successfully"
              PERFORM UNTIL FILE-STATUS NOT = "00"
                 READ HTML-FILE INTO HTML-FILE-REC
                    AT END
                       DISPLAY "RENDER-INDEX: End of file"
                       EXIT PERFORM
                    NOT AT END
                       COMPUTE TMP32 = FUNCTION LENGTH(
                          FUNCTION TRIM(HTML-FILE-REC TRAILING))
                       IF HTML-PTR + TMP32 + 1 > LENGTH OF HTML
                          DISPLAY "RENDER-INDEX: Would exceed HTML buffer, closing"
                          EXIT PERFORM
                       END-IF
                       MOVE HTML-FILE-REC(1:TMP32) TO HTML(HTML-PTR:TMP32)
                       ADD TMP32 TO HTML-PTR
                       MOVE X"0A" TO HTML(HTML-PTR:1)
                       ADD 1 TO HTML-PTR
                 END-READ
              END-PERFORM
              DISPLAY "RENDER-INDEX: Closing file"
              CLOSE HTML-FILE
              DISPLAY "RENDER-INDEX: File closed"
           ELSE
              DISPLAY "RENDER-INDEX: File open failed, status = " FILE-STATUS
              STRING
               "<!doctype html><html><head><title>Error</title></head>",
               "<body><h1>Error</h1>",
               "<p>HTML file not found at /app/index.html</p>",
               "</body></html>"
               DELIMITED BY SIZE INTO HTML WITH POINTER HTML-PTR
              END-STRING
           END-IF.

       SEND-HTML.
           IF HTML-PTR > 1
              COMPUTE SEND-LEN = HTML-PTR - 1
           ELSE
              MOVE 0 TO SEND-LEN
           END-IF

           IF SEND-LEN > 0
              CALL "send" USING
                   BY VALUE CLIFD
                   BY REFERENCE HTML
                   BY VALUE SEND-LEN
                   BY VALUE 0
                   RETURNING RET
           END-CALL
           END-IF.

       RESP-REDIRECT.
           MOVE SPACES TO HTML
           MOVE 1 TO HTML-PTR
           STRING "HTTP/1.1 303 See Other", CRLF,
                  "Location: /", CRLF,
                  "Cache-Control: no-store", CRLF, CRLF
             DELIMITED BY SIZE INTO HTML WITH POINTER HTML-PTR
           END-STRING
           COMPUTE I = HTML-PTR - 1
           CALL "send" USING
                BY VALUE CLIFD
                BY REFERENCE HTML
                BY VALUE I
                BY VALUE 0
                RETURNING RET
           END-CALL.

       RESP-404.
           MOVE SPACES TO HTML
           MOVE 1 TO HTML-PTR
           STRING "HTTP/1.1 404 Not Found", CRLF,
                  "Content-Type: text/plain; charset=utf-8", CRLF, CRLF,
                  "Not Found" 
             DELIMITED BY SIZE INTO HTML WITH POINTER HTML-PTR
           END-STRING
           COMPUTE I = HTML-PTR - 1
           CALL "send" USING
                BY VALUE CLIFD
                BY REFERENCE HTML
                BY VALUE I
                BY VALUE 0
                RETURNING RET
           END-CALL.
