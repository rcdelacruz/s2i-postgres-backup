#!/bin/bash
# Script for backing up Postgres data and pushing to S3

# Parameters
HOST=$1
USER=$2
PASSWORD=$3
S3_BUCKET_NAME=$4
#GPG_RECIPIENT=$5

DATESTAMP=$(date '+%Y-%m-%d')

# Retrieve a list of all databases
DATABASE=$5
NAMESPACE=$6
# Imports gpg keys
# gpg --import /opt/rh/secrets/gpg_public_key
# gpg --list-keys

# For each database archive data and push directly to S3

TIMESTAMP=$(date '+%H:%M:%S')
echo "==> Dumping database $DATABASE"
PGPASSWORD="$PASSWORD" pg_dump -h $HOST -U $USER -F t -d $DATABASE > /tmp/$DATABASE-$TIMESTAMP.dump.tar
#echo "==> Encrypting database archive \"$DATABASE\""
#gpg --no-tty --batch --yes --encrypt --recipient "$GPG_RECIPIENT" --trust-model $GPG_TRUST_MODEL /tmp/$DATABASE-$TIMESTAMP.dump.gz 
echo "==> Copying $DATABASE to S3 bucket s3://$S3_BUCKET_NAME/backups/pgsql/$NAMESPACE/"
s3cmd put --progress /tmp/$DATABASE-$TIMESTAMP.dump.tar s3://$S3_BUCKET_NAME/backups/pgsql/$NAMESPACE/$DATABASE-$TIMESTAMP.dump.tar
STATUS=$?
if [ $STATUS -eq 0 ]; then
  echo "==> Dump $DATABASE: COMPLETED"
else
  echo "==> Dump $DATABASE: FAILED"
  exit 1
fi
echo "==> Cleaning up"
rm /tmp/$DATABASE-$TIMESTAMP.dump.tar
echo "==> Listing archived artifact under S3 dir: s3://$S3_BUCKET_NAME/backups/pgsql/$NAMESPACE/"
aws s3 ls s3://$S3_BUCKET_NAME/backups/pgsql/$NAMESPACE/ --human-readable --summarize | grep $DATABASE | grep $TIMESTAMP

## delete older than 3 days s3 files
s3cmd ls s3://$S3_BUCKET_NAME/backups/pgsql/$NAMESPACE/  | grep " DIR " -v | while read -r line;
  do
    createDate=`echo $line|awk {'print $1" "$2'}`
    createDate=`date -d"$createDate" +%s`
    olderThan=`date -d"-3 days" +%s`
    if [[ $createDate -lt $olderThan ]]
      then
        fileName=`echo $line|awk {'print $4'}`
        if [[ $fileName != "" ]]
          then
            printf '==> Deleting "%s"\n' $fileName
            s3cmd del "$fileName"
        fi
    fi
  done;