FROM python:3.9-slim

COPY requirements.txt ./
RUN pip install -r requirements.txt

WORKDIR /app
COPY . ./

ENV PYTHONPATH=/packages

CMD python -m coflux -p project-1 -h server:7070 -m app.repo
