FROM python:3.9-slim

COPY requirements.txt ./
RUN pip install -r requirements.txt

WORKDIR /app
COPY . ./

ENV PYTHONPATH=/packages

CMD python -u -m coflux -p $PROJECT -h $HOST -m $MODULE -v $VERSION
