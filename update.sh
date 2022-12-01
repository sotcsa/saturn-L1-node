#!/bin/bash

set -ex

: "${SATURN_NETWORK:=test}"
: "${SATURN_HOME:=$HOME}"

if pidof -o %PPID -x "update.sh" > /dev/null; then
  exit
fi

#export SLACK_WEBHOOK_URL (SLACK_CHANNEL is optional) for notifictions
send_notification() {
  if [ ! -z ${SLACK_WEBHOOK_URL+x} ]; then
    local color='good'
    if [ $1 == 'ERROR' ]; then
      color='danger'
    elif [ $1 == 'WARN' ]; then
      color = 'warning'
    fi
    local message=""
    if [ -z ${SLACK_WEBHOOK_URL+x} ]; then
      message="payload={\"channel\": \"#$SLACK_CHANNEL\",\"attachments\":[{\"pretext\":\"$2\",\"text\":\"$3\",\"color\":\"$color\"}]}"
    else
      message="payload={\"attachments\":[{\"pretext\":\"$2\",\"text\":\"$3\",\"color\":\"$color\"}]}"
    fi

    curl -s -X POST --data-urlencode "$message" ${SLACK_WEBHOOK_URL}
  fi
}


update_target=$SATURN_HOME/update.sh

echo -n "$(date -u) Checking for auto-update script ($update_target) updates... "

if wget -O "$update_target.tmp" -T 10 -t 3 "https://raw.githubusercontent.com/sotcsa/L1-node/main/update.sh" && [[ -s "$update_target.tmp" ]] && [ "$(stat -c %s "$update_target.tmp")" -ne "$(stat -c %s "$update_target")" ]
then
  mv -f "$update_target.tmp" "$update_target"
  chmod +x "$update_target"
  echo -n "updated $update_target script successfully!"
  send_notification 'INFO' "[SATURN] update.sh updated" "$update_target script successfully updated!"
  exit
else
  echo -n "$update_target script up to date"
  rm -f "$update_target.tmp"
fi

run_target=$SATURN_HOME/run.sh

echo -n "$(date -u) Checking for run script ($run_target) updates... "

if wget -O "$run_target.tmp" -T 10 -t 3 "https://raw.githubusercontent.com/sotcsa/L1-node/main/run.sh" && [[ -s "$run_target.tmp" ]] && [ "$(stat -c %s "$run_target.tmp")" -ne "$(stat -c %s "$run_target")" ]
then
  mv -f "$run_target.tmp" "$run_target"
  chmod +x "$run_target"
  echo -n "updated $run_target script successfully!"
  send_notification 'INFO' "[SATURN] run.sh updated" "updated $run_target script successfully!"
  exit
else
  echo -n "$run_target script up to date"
  rm -f "$run_target.tmp"
fi

echo -n "$(date -u) Checking for Saturn $SATURN_NETWORK network L1 node updates... "

out=$(sudo docker pull ghcr.io/filecoin-saturn/l1-node:$SATURN_NETWORK)

if [[ $out != *"up to date"* ]]; then
  echo -n "$(date -u) New Saturn $SATURN_NETWORK network L1 node version found!"

  random_sleep="$(( RANDOM % 3600 ))"
  echo -n "$(date -u) Waiting for $random_sleep seconds..."
  send_notification 'INFO' "[SATURN] NEW NODE VERSION" "New Saturn $SATURN_NETWORK network L1 node version found!\nSleeping $random_sleep seconds before node restart"
  sleep "$random_sleep"

  echo -n "$(date -u) Draining $SATURN_NETWORK network L1 node... "
  sudo docker kill --signal=SIGTERM saturn-node >> /dev/null || true
  sleep 900
  echo -n "restarting...."

  sudo docker pull ghcr.io/filecoin-saturn/l1-node:$SATURN_NETWORK || true
  sudo docker stop saturn-node || true
  sudo docker rm -f saturn-node || true
  sudo docker run --name saturn-node -it -d \
    --restart=unless-stopped \
    -v "$SATURN_HOME/shared:/usr/src/app/shared" \
    -e "FIL_WALLET_ADDRESS=$FIL_WALLET_ADDRESS" \
    -e "NODE_OPERATOR_EMAIL=$NODE_OPERATOR_EMAIL" \
    -e "SPEEDTEST_SERVER_CONFIG=$SPEEDTEST_SERVER_CONFIG" \
    --network host \
    --ulimit nofile=1000000 \
    ghcr.io/filecoin-saturn/l1-node:$SATURN_NETWORK
  sudo docker image prune -f

  echo -n "Updated to latest version successfully!"
  send_notification 'INFO' "[SATURN] NEW NODE VERSION" "Updated to latest version successfully!"
else
  echo -n "Saturn $SATURN_NETWORK network L1 node up to date"
fi
