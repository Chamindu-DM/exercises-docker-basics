FROM ubuntu:24.04

WORKDIR /usr/src/app

RUN apt-get update && apt-get install -y curl && rm -rf /var/lib/apt/lists/*

COPY script.sh .

RUN chmod +x script.sh

ENTRYPOINT ["./script.sh"]
