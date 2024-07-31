#!/bin/bash

#Author: Keagan Peet <kpeet@newrelic.com>
#Purpose: Read, parse, and send SAP PI channel status logs to New Relic

####### CONFIGURATION ##########
INTEGRATION_PATH="/var/db/newrelic-infra/integrations.d" #Path to this script
LOGS_PATH="/usr/newrelic/logging" # Path to comm channel logs
CHANNEL_SUMMARY_FILE="channels.log" # Name of comm channel file
CHECKPOINT_FILE=".last_log_evaluated" # File that stores the last log line evaluated, in order to determine what log lines subsequent executions should start processing at
####### CONFIGURATION ##########

cd $INTEGRATION_PATH

#JSON payload init
payload=()

process_channel_group () {
  local status="$1"
  local channelGroup="$2"

  if [ "$channelGroup" != "None Reported" ]; then
    local channelGroupArray=(${channelGroup//,/ })
    for channel in "${channelGroupArray[@]}"; do
      payload+=("{\"nodeName\": \"$nodeName\", \"collectionTime\": \"$collectionTime\", \"channelName\": \"$channel\", \"status\": \"$status\"},")
    done
  fi
}

#Function to parse a given log line and add formatted data to array following NR spec
add_to_payload () {
  local line="$1"

  local collectionTime=$(echo "$line" | awk -F 'Collection Time: ' '{print $2}' | awk -F ',' '{print $1}')
  local nodeName=$(echo "$line" | awk -F 'Node Name: ' '{print $2}' | awk -F ',' '{print $1}')
  local inactiveChannels=$(echo "$line" | grep -oP '(?<=Inactive Channels: \[)[^]]*' | tr -d '[]' | xargs)
  local errornousChannels=$(echo "$line" | grep -oP '(?<=Errornous Channels: \[)[^]]*' | tr -d '[]' | xargs)
  local withErrorsChannels=$(echo "$line" | grep -oP '(?<=With Errors Channels: \[)[^]]*' | tr -d '[]' | xargs)
  local stoppedChannels=$(echo "$line" | grep -oP '(?<=Stopped Channels: \[)[^]]*' | tr -d '[]' | xargs)
  local activeChannels=$(echo "$line" | grep -oP '(?<=Active Channels: \[)[^]]*' | tr -d '[]' | xargs)

  process_channel_group "inactive" "$inactiveChannels"
  process_channel_group "errornous" "$errornousChannels"
  process_channel_group "with_errors" "$withErrorsChannels"
  process_channel_group "stopped" "$stoppedChannels"
  process_channel_group "active" "$activeChannels"
}

#Validate if first run or not
if [[ -f "$CHECKPOINT_FILE" ]]; then
  last_line=$(tail -n 1 "$CHECKPOINT_FILE") #Grab last line from previous execution
  escaped_last_line=$(echo "$last_line" | sed 's/\[/\\[/g; s/\]/\\]/g')
  last_line_number=$(grep -n "$escaped_last_line" "$LOGS_PATH/$CHANNEL_SUMMARY_FILE" | cut -d ":" -f 1) #Get line number of last line stored from previous execution

  #file was rotated (last log stored no longer exists in file)
  if [ -z $last_line_number ]; then
    last_line_number="0"
  else
    : #do nothing
  fi

  #Only add new lines after lines already processed on previous executions (if there are new lines to process)
  if [ "$last_line_number" -lt "$(wc -l < "$LOGS_PATH/$CHANNEL_SUMMARY_FILE" | awk '{print $1}')" ]; then
    let "starting_line=$last_line_number+1"
    while IFS= read -r line; do
      add_to_payload "$line"
    done < <(tail -n +"$starting_line" "$LOGS_PATH/$CHANNEL_SUMMARY_FILE")
  else
    : #do nothing
    #echo "No new lines to process"
  fi

  new_last_line=$(tail -n 1 "$LOGS_PATH/$CHANNEL_SUMMARY_FILE")
  echo "$new_last_line" > "$CHECKPOINT_FILE" #Write latest log line to file
else
  last_line=$(tail -n 1 "$LOGS_PATH/$CHANNEL_SUMMARY_FILE")
  while IFS= read -r line; do
    add_to_payload "$line"
  done < "$LOGS_PATH/$CHANNEL_SUMMARY_FILE"
  echo "$last_line" > "$CHECKPOINT_FILE" #Write last log line to file
fi

echo "["${payload[@]}"]" | sed 's/\(.*\),/\1/' #remove last comma and print payload
