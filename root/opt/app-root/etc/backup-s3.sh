#!/bin/bash
# Script for backing up Postgres data and pushing to S3

# Parameters
HOST=$1
USER=$2
PASSWORD=$3
S3_BUCKET_NAME=$4
GPG_RECIPIENT=$5

DATESTAMP=$(date '+%Y-%m-%d')

# Retrieve a list of all databases
DATABASES=$(psql -h$HOST -u$USER  -p$PASSWORD -e 'SHOW DATABASES' | tail -n+2 | grep -v information_schema)

# Imports gpg keys
gpg --import /opt/rh/secrets/gpg_public_key
gpg --list-keys

# For each database archive data and push directly to S3
for DATABASE in $DATABASES; do
  TIMESTAMP=$(date '+%H:%M:%S')
  echo "==> Dumping database $DATABASE to S3 bucket s3://$S3_BUCKET_NAME/backups/pgsql/$DATESTAMP/"
  pg_dump -h $HOST -U $USER -W $PASSWORD -d $DATABASE | gzip > /tmp/$DATABASE-$TIMESTAMP.dump.gz
  echo "==> Encrypting database archive \"$DATABASE\""
  gpg --no-tty --batch --yes --encrypt --recipient "$GPG_RECIPIENT" --trust-model $GPG_TRUST_MODEL /tmp/$DATABASE-$TIMESTAMP.dump.gz 
  echo "==> Dumping database $DATABASE to S3 bucket s3://$S3_BUCKET_NAME/backups/pgsql/$DATESTAMP/"
  s3cmd put --progress /tmp/$DATABASE-$TIMESTAMP.dump.gz.gpg s3://$S3_BUCKET_NAME/backups/mysql/$DATESTAMP/$DATABASE-$TIMESTAMP.dump.gz.gpg
  STATUS=$?
  if [ $STATUS -eq 0 ]; then
    echo "==> Dump $DATABASE: COMPLETED"
  else
    echo "==> Dump $DATABASE: FAILED"
    exit 1
  fi
  echo "==> Cleaning up"
  rm /tmp/$DATABASE-$TIMESTAMP.dump.gz /tmp/$DATABASE-$TIMESTAMP.dump.gz.gpg
  echo "==> Listing archived artifact under S3 dir: s3://$S3_BUCKET_NAME/backups/pgsql/$DATESTAMP/"
  aws s3 ls s3://$S3_BUCKET_NAME/backups/mysql/$DATESTAMP/ --human-readable --summarize | grep $DATABASE | grep $TIMESTAMP
done