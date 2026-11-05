# Build stage: compile with the GnuCOBOL pinned in the repo's flake.lock.
# CI fails if NIXPKGS names a different revision.
FROM nixos/nix:2.33.3 AS build
ARG NIXPKGS=github:NixOS/nixpkgs/b6018f87da91d19d0ab4cf979885689b469cdd41
WORKDIR /src
COPY Makefile ./
COPY copy ./copy
COPY src ./src
# The binaries load libcob, and the glibc it was built against, from
# /nix/store. Collect the store paths they name, and everything those
# need, for the runtime stage.
RUN nix --extra-experimental-features "nix-command flakes" \
      shell "$NIXPKGS#gnucobol" "$NIXPKGS#gcc" "$NIXPKGS#gnumake" -c make build \
 && mkdir -p /closure/nix/store \
 && cp -a $(nix-store -qR $(grep -aho '/nix/store/[a-z0-9]\{32\}-[^/]*' build/* | sort -u)) \
      /closure/nix/store/

# Runtime stage: the binaries' Nix closure plus busybox httpd serving
# the CGI program.
# The same image works as a CLI: docker run --rm IMAGE amortise 250000 11.75 240
FROM debian:bookworm-slim
RUN apt-get update \
 && apt-get install -y --no-install-recommends busybox \
 && rm -rf /var/lib/apt/lists/* \
 && useradd --system --no-create-home --shell /usr/sbin/nologin web
COPY --from=build /closure/nix/store /nix/store
COPY --from=build /src/build/amortise /usr/local/bin/amortise
COPY --from=build /src/build/amortweb /www/cgi-bin/amortise
COPY www/ /www/
USER web
EXPOSE 8080
CMD ["busybox", "httpd", "-f", "-v", "-p", "8080", "-h", "/www"]
