#!/bin/bash

# Find unused SGs in the region
## Based on: https://mohitkr27.medium.com/deleting-unused-security-groups-in-aws-7211d032f666

#########################
## Variables
#########################
REGION=""
FORCE=""
DEBUG=""
LOG="/tmp/$(basename "$0").log"
TMP1="/tmp/$(basename "$0").1.tmp"
TMP2="/tmp/$(basename "$0").2.tmp"
TMP3="/tmp/$(basename "$0").3.tmp"
TMP4="/home/cloudshell-user/find-unused-sgs.sh.output"
TMP5="/home/cloudshell-user/find-unused-sgs.sh.delete"
echo -e "\c" > $TMP4

#########################
## Functions
#########################
function Continue {
	if [ "$FORCE" != "Y" ]; then
        	read INPUT
	else
        	INPUT="Y"
	fi

        if [ "$INPUT" == "q" ]; then
                exit
        fi

}

function logit {
	echo -e "$( date +"%b %d %H:%M:%S" ) $1" | tee -a $LOG
} 

function Debug {
	if [ "$DEBUG" == "Y" ]; then
		echo -e "$( date +"%b %d %H:%M:%S" ) $1" | tee -a $LOG
	else
		echo -e "$( date +"%b %d %H:%M:%S" ) $1" >> $LOG
	fi
}

function Help {
	    echo -e "\n\tUsage: $(basename $0) [ -d | --debug ] [ -h | --help ] [ -r | --region <region name, default is local region> ] [ -f | --force ] \n"
	        exit 1
}

#########################
## CLI Options
#########################
if [ -z $1 ]; then
        Midway
fi

while [ "$1" != "" ]; do
        case $1 in
                -d | --debug )
                        DEBUG="Y"
                        echo "Turning on Debug"
                        ;;
                -h | --help )
                        Help
                        ;;
                -f | --force )
			Debug "Enabling Force"
			FORCE="Y"
                        ;;
                -r | --region )
                        shift
                        REGION="--region $1"
                        Debug "Region set to $REGION"
                        ;;
        esac
        shift
done

#########################
## Main Code
#########################
# list all SGs
aws ec2 $REGION describe-security-groups --query "SecurityGroups[*].{Name:GroupName,ID:GroupId}"  --output text | tr '\t' '\n' | sort | uniq | grep "^sg-" > $TMP1
if [ "$DEBUG" == "Y" ]; then
	cat $TMP1
fi
logit "Found $( cat $TMP1 | wc -l ) Total SGs.\n\t Press [enter] to continue or [q] to quit:\n\c"
Continue

# Find EC2 used SGs
aws ec2 $REGION describe-instances --query "Reservations[*].Instances[*].SecurityGroups[*].GroupId" --output text | tr '\t' '\n' | sort | uniq > $TMP2
if [ "$DEBUG" == "Y" ]; then
	cat $TMP2
fi
while read LINE; do
	echo "$LINE active EC2" | tee -a $TMP4
done < $TMP2
logit "Found $( cat $TMP2 | wc -l ) EC2 used SGs.\n\t Press [enter] to continue or [q] to quit:\n\c"
Continue

# Diff all with used
Debug "Diffing $TMP1 $TMP2"
diff -ywb $TMP1 $TMP2 | grep \< | awk '{print $1}' > $TMP3
if [ "$DEBUG" == "Y" ]; then
	cat $TMP3
fi

TOT=`cat $TMP3 | wc -l`
logit "Found $TOT EC2 unused SGs, need to check other service usage\n\t Press [enter] to continue or [q] to quit:\n\c"
Continue
###if [ "$FORCE" != "Y" ]; then
        #read INPUT
#else
        #INPUT="Y"
#fi
#
        #if [ "$INPUT" == "q" ]; then
                #exit
        #fi

for i in `cat $TMP3` ; do
        let "COUNT = $COUNT + 1"
        logit "Checking $COUNT of $TOT - $i" 
        Debug "Lambda"
        aws $REGION lambda list-functions --query "Functions[?VpcConfig.SecurityGroupIds && contains(VpcConfig.SecurityGroupIds, \`$i\`)].FunctionName" | grep -v '\[\]' && echo "$i active Lambda" | tee -a $TMP4
        Debug "RDS"
        aws $REGION rds describe-db-instances --query "DBInstances[?contains(VpcSecurityGroups[].VpcSecurityGroupId, \`$i\`)].DBName" | grep -v '\[\|\]' && echo "$i active RDS" | tee -a $TMP4
        Debug "EC2 Reservations"
        aws $REGION ec2 describe-instances --query "Reservations[].Instances[?SecurityGroups[].GroupId && contains(SecurityGroups[].GroupId, \`$i\`)].{InstanceId: InstanceId, Name: Tags[?Key==\`Name\`].Value | [0]}" | tr '\n' ' ' | grep -v '\[\]' && echo "$i active Reservation" | tee -a $TMP4
        Debug "EC2 Launch Templates"
        aws $REGION ec2 describe-launch-template-versions --versions '$Latest' --query "LaunchTemplateVersions[?LaunchTemplateData.NetworkInterfaces[].Groups[] && contains(LaunchTemplateData.NetworkInterfaces[].Groups[], \`$i\`)].LaunchTemplateName" | grep -v '\[\]' && echo "$i active Launch Template" | tee -a $TMP4
        Debug "ELBs"
        aws $REGION elb describe-load-balancers --query "LoadBalancerDescriptions[?contains(SecurityGroups[],  \`$i\`)]. LoadBalancerName" | grep -v '\[\]' && echo "$i active ELB" | tee -a $TMP4
        Debug "OpenSearch"
        for DOMAIN in $( aws $REGION opensearch list-domain-names | grep '"DomainName"' | cut -d \" -f 4 ); do
                aws $REGION opensearch describe-domain --domain-name $DOMAIN --query 'DomainStatus.VPCOptions.SecurityGroupIds' | grep -v '\[\|\]' | grep "$i" && echo "$i active OpenSearch" | tee -a $TMP4
        done
done

logit "Found $( grep -c "active" $TMP4 ) active SGs in $TMP4 \n\t Press [enter] to continue or [q] to quit:\n\c"
Continue

# Diff used with all
Debug "Diffing $TMP1 $TMP4"
diff -ywb <( cat $TMP1 | sort -u ) <( cat $TMP4 | awk '{print $1}' | sort -u ) | grep \< | awk '{print $1}' > $TMP5
if [ "$DEBUG" == "Y" ]; then
	cat $TMP5
fi

logit "Found $( cat $TMP5 | wc -l ) SGs that can be deleted in $TMP5 \n\t Press [enter] to continue (and delete the SGs) or [q] to quit:"
Continue

while read ID; do
	logit "Removing $ID"
	aws $REGION ec2 delete-security-group --group-id $ID && logit "done" || logit "error"
done < $TMP5
