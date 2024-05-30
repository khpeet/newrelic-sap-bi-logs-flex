#!/bin/bash

#Author: Keagan Peet <kpeet@newrelic.com>
#Purpose: Read, parse, and send SAP PI channel logs to New Relic

####### CONFIGURATION ##########
INTEGRATION_PATH="/var/db/newrelic-infra/integrations.d" #Path to this script
LOGS_PATH="/usr/newrelic/logging" # Path to comm channel logs
CHANNEL_SUMMARY_FILE="channelsummary.log" # Name of comm channel file
CHECKPOINT_FILE=".last_log_evaluated" # File that stores the last log line evaluated, in order to determine what log lines subsequent executions should start processing at
####### CONFIGURATION ##########

cd $INTEGRATION_PATH

#JSON payload init
payload=()

#Function to parse a given log line and add formatted data to array following NR spec
add_to_payload () {
  local line="$1"
  #local channelName=$(echo "$line" | grep -oP '(?<=Name: )[A-Z_0-9]+')
  local channelName=$(echo "$line" | awk -F 'Name: ' '{print $2}' | awk -F ',' '{print $1}')
  local channelId=$(echo "$line" | awk -F 'Channel Id: ' '{print $2}' | awk -F ',' '{print $1}')
  local channelStatus=$(echo "$line" | awk -F 'Channel Status: ' '{print $2}' | awk -F ',' '{print $1}')
  local adapterType=$(echo "$line" | awk -F 'Adapter Type: ' '{print $2}' | awk -F ',' '{print $1}')
  local direction=$(echo "$line" | awk -F 'Direction: ' '{print $2}' | awk -F ',' '{print $1}')
  local num_nodes=$(echo "$line" | awk -F 'Number of Nodes: ' '{print $2}' | awk -F ',' '{print $1}')

  payload+=("{\"channelName\": \"$channelName\", \"channelId\": \"$channelId\", \"channelStatus\": \"$channelStatus\", \"adapterType\": \"$adapterType\", \"direction\": \"$direction\", \"number_of_nodes\": \"$num_nodes\"},")
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
