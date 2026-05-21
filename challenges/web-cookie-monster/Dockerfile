FROM python:3.12-alpine
WORKDIR /app
RUN pip install --no-cache-dir flask==3.0.3
COPY app.py .
EXPOSE 80
# Runs as non-root; flask binds 80 inside the isolated network namespace.
RUN adduser -D -u 10001 ctf
USER ctf
CMD ["python", "app.py"]
