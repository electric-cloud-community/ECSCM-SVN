FROM electricflow/efagent:latest

RUN apt-get update && apt-get -y install subversion language-pack-en
