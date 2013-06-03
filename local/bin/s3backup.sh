#!/bin/sh

PATH=/bin:/usr/bin
HCHOME=/home/hebcal
S3SYNCDIR=$HCHOME/local/s3sync
LOCKFILE=/tmp/mradwin.s3backup.lock
BACKUPDIR=$HCHOME/local/lib/svn

dotlockfile -r 0 -p $LOCKFILE
if [ $? != 0 ]; then
   echo "s3backup is still running; exiting"
   exit 1
fi

AWS_ACCESS_KEY_ID=xxxxxxxxxxxxxxxxxxxx
AWS_SECRET_ACCESS_KEY=xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx
AWS_CALLING_FORMAT=SUBDOMAIN

export AWS_ACCESS_KEY_ID
export AWS_SECRET_ACCESS_KEY
export AWS_CALLING_FORMAT

cd $S3SYNCDIR
ruby s3sync.rb -v -r ${BACKUPDIR} hebcal2:

dotlockfile -u $LOCKFILE
