FROM ubuntu:22.04
EXPOSE 5001
WORKDIR /usr/src/app
RUN apt-get update && apt-get install -y curl
RUN curl -sL https://deb.nodesource.com/setup_16.x | bash
RUN apt-get install -y nodejs
COPY . .
RUN npm install
RUN npm run build
RUN npm install -g serve
CMD serve -s -l 5001 build