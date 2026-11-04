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
# The same image works as a CLI: docker run --rm IMAGE amortise 250000 11.75 240
FROM debian:bookworm-slim
RUN apt-get update \
 && apt-get install -y --no-install-recommends libcob4 busybox \
 && rm -rf /var/lib/apt/lists/* \
 && useradd --system --no-create-home --shell /usr/sbin/nologin web
COPY --from=build /src/build/amortise /usr/local/bin/amortise
COPY --from=build /src/build/amortweb /www/cgi-bin/amortise
COPY www/ /www/
USER web
EXPOSE 8080
CMD ["busybox", "httpd", "-f", "-v", "-p", "8080", "-h", "/www"]
