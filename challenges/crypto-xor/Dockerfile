FROM python:3.12-alpine
WORKDIR /app
RUN pip install --no-cache-dir flask==3.0.3
COPY app.py .
RUN adduser -D -u 10001 ctf
USER ctf
EXPOSE 80
CMD ["python", "app.py"]
