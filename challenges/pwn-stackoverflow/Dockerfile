FROM debian:bookworm-slim AS build
RUN apt-get update && apt-get install -y gcc && rm -rf /var/lib/apt/lists/*
WORKDIR /src
COPY vuln.c .
# Intentionally insecure build: no stack protector, executable stack, no PIE.
# This is what makes it a *teachable* beginner pwn, not a 0-day farm.
RUN gcc -fno-stack-protector -z execstack -no-pie -o vuln vuln.c

FROM debian:bookworm-slim
RUN apt-get update && apt-get install -y socat && rm -rf /var/lib/apt/lists/*
RUN useradd -m -u 10001 ctf
COPY --from=build /src/vuln /home/ctf/vuln
# Flag is injected at build time from a build-arg (sourced from .env via
# docker-compose), NOT copied from a tracked file. This avoids the classic
# "COPY flag.txt: not found" break when .gitignore strips flag files in transit,
# and keeps the real flag out of version control entirely.
ARG FLAG="CTF{placeholder_set_PWN_FLAG_in_dotenv}"
RUN echo "$FLAG" > /home/ctf/flag.txt
RUN chmod 0444 /home/ctf/flag.txt && chmod 0555 /home/ctf/vuln
USER ctf
WORKDIR /home/ctf
EXPOSE 9999
# socat hands each TCP connection its OWN short-lived process. One player's
# crash or shell cannot affect another's session, and there's nothing
# persistent to corrupt. This is the standard safe way to expose pwn binaries.
CMD ["socat", "-T60", "TCP-LISTEN:9999,reuseaddr,fork", "EXEC:/home/ctf/vuln,stderr"]
