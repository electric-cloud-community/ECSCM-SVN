#!/bin/bash

egrep -q '(^|:)/foo/bin($|:)' <<< $PATH || export PATH=$PATH:/usr/bin

yum -y install subversion
mkdir /var/svn
mkdir /tmp/test
echo '0' > /tmp/test/test_commit
for i in `seq 1 4`
do
    svnadmin create /var/svn/test_${i}
    svn import -m "initial commit" /tmp/test file:///var/svn/test_${i}
    svn checkout file:///var/svn/test_${i} /tmp/test_${i}
    sed -i -e 's/^\[general\]/[general]\
anon-access = none\
auth-access = write\
password-db = passwd/' /var/svn/test_${i}/conf/svnserve.conf
    sed -i -e 's/^\[users\]/[users]\
user1 = user1/' /var/svn/test_${i}/conf/passwd
done

svn propset "svn:externals" "svn://svnserver/test_2 test_2
svn://svnserver/test_3 test_3" /tmp/test_1
svn propset "svn:externals" "svn://svnserver/test_4 test_4" /tmp/test_2
for i in `seq 1 3`
do
    svn commit -m "externals" /tmp/test_${i}
done

