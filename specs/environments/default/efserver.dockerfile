FROM electricflow/efserver:latest

RUN apt-get update && apt-get -y install subversion language-pack-en
