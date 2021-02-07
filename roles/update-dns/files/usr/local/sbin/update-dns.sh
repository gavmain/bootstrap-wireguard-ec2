#!/bin/bash

CONFIG_FILE=/usr/local/etc/update-dns.cfg
if [[ -f $CONFIG_FILE ]]; then
  . $CONFIG_FILE
else
  echo "Error - Config file unset. Exit code - ($rc)"
  exit 1
fi

AWS_REGION=$(curl -s http://169.254.169.254/latest/meta-data/placement/availability-zone | sed 's/.$//')
PUBLIC_IP=$(curl -s http://169.254.169.254/latest/meta-data/public-ipv4)

ENDPOINT_FQDN=$(aws --region $AWS_REGION ssm get-parameter --name $ENDPOINT_FQDN_PS_PATH --query Parameter.Value --output text)
rc=$?
if [[ $rc -ne 0 ]]; then
  echo "Failed to find ${ENDPOINT_FQDN_PS_PATH}. Create this record in the SSM Parameter Store to allow this service to update DNS at boot time. Exit code - ($rc)"
  exit $rc
fi

# Get the hosted zone ID for the zone we are going to update. e.g. example.com
HOSTED_ZONE=$(echo $ENDPOINT_FQDN | cut -d '.' -f 2-)
HOSTED_ZONE_ID=$(aws --region $AWS_REGION ssm get-parameter --name $HOSTED_ZONE_PS_PATH --query Parameter.Value --output text)
rc=$?
if [[ $rc -ne 0 ]]; then
  echo "Failed to find ${HOSTED_ZONE_PS_PATH}. Create this record in the SSM Parameter Store to allow this service to update DNS at boot time. Exit code - ($rc)"
  exit $rc
fi

# Query Route53 for the current record. A policy attached to the EC2 instance's role is required for this.
CURRENT_RECORD_VALUE=$(aws route53 list-resource-record-sets --hosted-zone-id $HOSTED_ZONE_ID --query "ResourceRecordSets[?Name == '${ENDPOINT_FQDN}.']" |jq --raw-output '.[].ResourceRecords[] | .Value')
rc=$?
if [[ $rc -ne 0 ]]; then
  echo "Failed to list-resource-record-sets. Check there is an associated policy which allows you to perform list-resource-record-sets. Exit code - ($rc)"
  exit $rc
fi

# If the current record for the endpoint matches our current public IP address, there is nothing more to do.
if [[ $CURRENT_RECORD_VALUE == $PUBLIC_IP ]]; then
  echo "$ENDPOINT_FQDN is correct. Nothing to do. Bye bye."
  exit 0
fi

# If the record needs modification, or doesn't exist, then create a json file to send up to Route53
COMMENT="Updating ${ENDPOINT_FQDN} on `hostname` at `date`"
TTL=300
TMPFILE=$(mktemp /tmp/${ENDPOINT_FQDN}.XXXXXXXX)

cat > ${TMPFILE} << EOF
{
  "Comment":"$COMMENT",
  "Changes":[
    {
      "Action":"UPSERT",
      "ResourceRecordSet":{
        "ResourceRecords":[
          {
            "Value":"$PUBLIC_IP"
          }
        ],
        "Name":"$ENDPOINT_FQDN",
        "Type":"A",
        "TTL":$TTL
      }
    }
  ]
}
EOF

# Change the A record and capture the change ID to interrogate the status of the modification
CHANGE_ID=$(aws route53 --output json change-resource-record-sets --hosted-zone-id $HOSTED_ZONE_ID --change-batch file:///$TMPFILE | jq --raw-output '.ChangeInfo.Id' | cut -d'/' -f 3-)

# Give Route53 some time to affect the change and log if the change was successful or not within the timeout threshold set below
TIMEOUT_SECS=180s
start_clock=$SECONDS
CHECK_CMD="aws route53 --output json get-change --id $CHANGE_ID | jq --raw-output '.ChangeInfo.Status' | grep INSYNC"

UPDATE_TIME_OUTPUT=$( { timeout $TIMEOUT_SECS bash -c "until $CHECK_CMD; do sleep 10; done"; } 2>&1 )
rc=$?
if [[ $rc -ne 0 ]]; then
  echo "Failed to verify if $ENDPOINT_FQDN updated. get-change timed out in $TIMEOUT_SECS"
  exit 1
else
  echo "Successfully updated $ENDPOINT_FQDN within $((SECONDS - start_clock)) seconds. Exiting!"
fi

exit 0
