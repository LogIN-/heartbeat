#!/bin/bash
# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~#
# Ivan Tomic - Project .: heartbeat :.                                 #
# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~#
# heartbeat - 03/02/2014 - heartbeat.bash - v1.00                      #
# ---------------------------------------------------------------------#
# This script checks some crucial LAMP server VARIABLES                #
# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~#
# TODO: - send email in case of error and SMS failure                  #
#       - automatic servicies restarting (Web/Database/Mail**)         # 
#       - slow mysql queries check                                     #        
# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~#

#####################################
##### VARIABLES
#####################################
# Lest declare global Array to save key/values in it
declare -A SERVER_STATS

ERROR=""

## Process file URL, ideally on remote server
MAINFRAME_URL="https://example.io/api/process.php?"
# Fallback to SMS in case of ERROR
TWILIO_AC_SID="xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx"
TWILIO_AC_TOKEN="xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx"
TWILIO_SMS_FROM="xxxxxxxxxxx"
TWILIO_SMS_TO="xxxxxxxxxxx"

# Get Curl Path! It's different on some enterprise OS's
CURL_PATH=$(which curl)
NGINX_PATH=$(which nginx)
APACHIE_PATH=$(which apachie)
MYSQL_PATH=$(which mysql)

SERVER_STATS[pl_action]="regular_api_update"

SERVER_STATS[pl_server_system_id]=$(hostname)
SERVER_STATS[pl_server_system_user]=$(whoami)
SERVER_STATS[pl_server_system_ip_adress]=$(hostname  -I | cut -f1 -d' ')


SYS_EMAIL_TO="xxxxxxxxx@example.com"
SYS_EMAIL_FROM="system@${SERVER_STATS[pl_server_system_id]}"
SYS_EMAIL_SUBJECT="Something is wrong check is needed!"

SYS_EMAIL_BODY="Server: ${SERVER_STATS[pl_server_system_id]}\n IP: ${SERVER_STATS[pl_server_system_ip_adress]}\n User: ${SERVER_STATS[pl_server_system_user]}\n\n"

TWILIO_SMS_MSG="Server: ${SERVER_STATS[pl_server_system_id]} IP: ${SERVER_STATS[pl_server_system_ip_adress]} Error: "

# Basic Auth pass to check in remote end
SERVER_STATS[pl_server_system_api_password]="$(date +%d)${SERVER_STATS[pl_server_system_id]}$(date +%m%H)"

# API Credentials (Dumb user) for testing SQL Connectivity
MYSQL_API_USER="db_user_xxx"
MYSQL_API_USER_PASS="db_password_xxx"
MYSQL_API_USER_DB="db_name_xxx"

SERVER_STATS[pl_server_system_ip]=$(/bin/hostname -i)
SERVER_STATS[pl_server_system_timestamp]=$(date)
#$(date +%Y-%m-%d_%H_%M)
SERVER_UPTIME=$(uptime)

# Get System Uptime
ruptime="$(uptime)"
if $(echo $ruptime | grep -E "min|days" >/dev/null); then
    x=$(echo $ruptime | awk '{ print $3 $4}')
else
    x=$(echo $ruptime | sed s/,//g| awk '{ print $3 " (hh:mm)"}')
fi
SERVER_STATS[pl_server_system_uptime]="$x"

#Get Server Current Load
SERVER_STATS[pl_server_system_load]="$(uptime |awk -F'average: ' '{ print $2}')"

# Get number of running process
SERVER_STATS[pl_server_system_process]="$(ps axue | grep -vE "^USER|grep|ps" | wc -l)"

# Get All Disk Usage Stats
SERVER_STATS[pl_server_disk_status]="$(df -hT | grep -vE "^Filesystem|shm" \
| awk '{w=sprintf("%d",$6);print $7 " " $6 " (" $2 "-" $4"/"$3")" }')"

# Get System RAM information
SERVER_STATS[pl_server_ram_used]="$(free -mto | grep Mem: | awk '{ print $3 " MB" }')"
SERVER_STATS[pl_server_ram_free]="$(free -mto | grep Mem: | awk '{ print $4 " MB" }')"
SERVER_STATS[pl_server_ram_total]="$(free -mto | grep Mem: | awk '{ print $2 " MB" }')"

# Query SQL Server to test availability
SERVER_STATS[pl_server_mysql_status]="NOT_OK"
SERVER_STATS[pl_server_mysql_response]="$(mysqlshow --user=$MYSQL_API_USER --password=$MYSQL_API_USER_PASS $MYSQL_API_USER_DB| grep -v Wildcard | grep -o $MYSQL_API_USER_DB)"
if [ "$SERVER_STATS[pl_server_mysql_response]"=="$MYSQL_API_USER_DB" ]; then
    SERVER_STATS[pl_server_mysql_status]="OK"
else
    ERROR="1"
fi


# Check if Return HTTP Code from local webserver
SERVER_STATS[pl_server_www_status]="000"
SERVER_STATS[pl_server_www_response]="$(curl --output /dev/null --silent --head --write-out '%{http_code}' "${SERVER_STATS[pl_server_system_id]}")"
if [ "$SERVER_STATS[pl_server_www_response]" != "$SERVER_STATS[pl_server_www_status]" ]; then
    SERVER_STATS[pl_server_www_status]="${SERVER_STATS[pl_server_www_response]}"
else
    ERROR="2"
fi


constructCurlPOST (){

    POST_DATA="${MAINFRAME_URL}"

    for i in "${!SERVER_STATS[@]}"
    do
        urlEncode "${SERVER_STATS[$i]}"

        echo "ACTION: $i"
        echo "VALUE : ${SERVER_STATS[$i]}"
        POST_DATA+="$i=$STRING_ENCODED&"

    done
}

urlEncode() {
    local hexchars="0123456789ABCDEF"
    local string="${1}"
    local strlen=${#string}
    local encoded=""

    for (( pos=0 ; pos<strlen ; pos++ )); do
        c=${string:$pos:1}
        if [ "$c" == ' ' ];then
            encoded+='+'
        elif ( [[ "$c" != '!' ]] && [ "$c" \< "0" ] && [[ "$c" != "-" ]] && [[ "$c" != "." ]] ) || ( [ "$c" \< 'A' ] && [ "$c" \> '9' ]  ) || ( [ "$c" \> 'Z' ] && [ "$c" \< 'a' ] && [[ "$c" != '_' ]]  ) || ( [ "$c" \> 'z' ] );then
            hc=`printf '%X' "'$c"`
            dc=`printf '%d' "'$c"`
            encoded+='%'
            f=$(( $dc >> 4 ))
            s=$(( $dc & 15 ))
            encoded+=${hexchars:$f:1}
            encoded+=${hexchars:$s:1}
        else
            encoded+=$c
        fi
    done
    STRING_ENCODED="${encoded}"
}

# lets construct request url for CURL
constructCurlPOST $SERVER_STATS

# Finally EXEC our curl
SERVER_REQUEST=$(${CURL_PATH} --output /dev/null --insecure --silent --head --write-out '%{http_code}' ''${POST_DATA%?}'')

if [ "$SERVER_REQUEST" != "200" ]; then
    ERROR="3"
fi


## Simple Error Handaling (SMS/EMAIL)
## Construct SMS Message
if [ "$ERROR" != "" ]; then

    if [ "$ERROR" -eq "1" ]; then
        TWILIO_SMS_MSG+="Local MySQL Server didnt manage to check itsself status Return: ${SERVER_STATS[pl_server_mysql_response]}"

    elif [ "$ERROR" -eq "2" ]; then
        TWILIO_SMS_MSG+="Local Web Server returned ${SERVER_STATS[pl_server_www_response]} http_code"

    elif [ "$ERROR" -eq "3" ]; then
        TWILIO_SMS_MSG+="Remote (API) Web Server returned $SERVER_REQUEST http_code"
    elif [ "$ERROR" -eq "4" ]; then
        TWILIO_SMS_MSG+="NGINX Restart Failed"

    else
        TWILIO_SMS_MSG+="unknown error, thats really strange!"
    fi
fi

if [ "$ERROR" != "" ]; then
    TWILIO_RESPONSE=$(curl --write-out %{http_code} --silent --output /dev/null -XPOST https://api.twilio.com/2010-04-01/Accounts/${TWILIO_AC_SID}/Messages.json \
                    -d "Body=${TWILIO_SMS_MSG}" \
                    -d "To=%2B${TWILIO_SMS_TO}" \
                    -d "From=%2B${TWILIO_SMS_FROM}" \
                    -u ''${TWILIO_AC_SID}':'${TWILIO_AC_TOKEN}'')
    # Check IF SMS is sended
    # The request has been fulfilled and resulted in a new resource being created. ("201")
    if [ "$TWILIO_RESPONSE" != "201" ]; then
        SYS_EMAIL_BODY+="Twilio Response: $TWILIO_RESPONSE\n Remote (API) Web Server Response: $SERVER_REQUEST\n Local Web Server Response: ${SERVER_STATS[pl_server_www_response]}\n Local MySQL Server response: ${SERVER_STATS[pl_server_mysql_response]}\n Post Variable Dump: $POST_DATA\n"
    fi
fi

unset SERVER_STATS
