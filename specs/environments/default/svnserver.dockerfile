FROM centos:latest

COPY svn-bootstrap.sh /
RUN /svn-bootstrap.sh

EXPOSE 3690/tcp
ENTRYPOINT /usr/bin/svnserve -r /var/svn -d --foreground
