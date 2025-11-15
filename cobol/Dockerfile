FROM debian:bookworm-slim

RUN apt-get update && apt-get install -y --no-install-recommends \
    gnucobol gcc curl ca-certificates \
  && rm -rf /var/lib/apt/lists/*

WORKDIR /app

COPY index.html /app/index.html
COPY server.cob /app/server.cob

# Ensure index.html is readable
RUN chmod 644 /app/index.html

RUN cobc -x -free -fno-ec=all server.cob -o /app/server

EXPOSE 8080

CMD ["/app/server"]