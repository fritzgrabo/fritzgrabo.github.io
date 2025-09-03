FROM debian:trixie-slim

ENV TERM=xterm-256color

RUN apt-get update && apt-get install -y --no-install-recommends \
    make \
    git \
    emacs \
    && apt-get clean \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /workspace

CMD ["make"]
