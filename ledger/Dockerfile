# Build stage: compile with GnuCOBOL.
FROM debian:bookworm-slim AS build
RUN apt-get update \
 && apt-get install -y --no-install-recommends gnucobol3 gcc libc6-dev make \
 && rm -rf /var/lib/apt/lists/*
WORKDIR /src
COPY Makefile ./
COPY copy ./copy
COPY src ./src
RUN make build

# Runtime stage: libcob plus busybox httpd serving the CGI program.
# The same image works as a CLI:
#   docker run --rm -v "$PWD:/data" -w /data IMAGE ledger MASTER TXNS OUTDIR
FROM debian:bookworm-slim
RUN apt-get update \
 && apt-get install -y --no-install-recommends libcob4 busybox \
 && rm -rf /var/lib/apt/lists/* \
 && useradd --system --no-create-home --shell /usr/sbin/nologin web
COPY --from=build /src/build/ledger /usr/local/bin/ledger
COPY --from=build /src/build/ledgerweb /www/cgi-bin/ledger
COPY samples/ /usr/local/share/ledger/samples/
COPY www/ /www/
USER web
EXPOSE 8080
CMD ["busybox", "httpd", "-f", "-v", "-p", "8080", "-h", "/www"]
