FROM python:3.12-alpine
WORKDIR /app
RUN pip install --no-cache-dir flask==3.0.3
COPY app.py .
# Flag injected at build time from a build-arg (sourced from .env), so the real
# flag never lives in a tracked file. Same pattern as the pwn challenge.
ARG FLAG="CTF{placeholder_set_WEB_FLAG_in_dotenv}"
RUN mkdir -p /secret && echo "$FLAG" > /secret/flag.txt && chmod 0444 /secret/flag.txt
RUN adduser -D -u 10001 ctf
USER ctf
EXPOSE 80
CMD ["python", "app.py"]
