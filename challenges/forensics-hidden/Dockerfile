FROM python:3.12-alpine
WORKDIR /app
RUN pip install --no-cache-dir flask==3.0.3
COPY app.py .
COPY gen.py .
# Generate the artifact at build time so the flag isn't sitting in plain layers.
RUN python gen.py && rm gen.py
RUN adduser -D -u 10001 ctf && chown -R ctf /app
USER ctf
EXPOSE 80
CMD ["python", "app.py"]
