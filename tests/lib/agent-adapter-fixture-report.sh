#!/usr/bin/env bash
# Submit the adapter fixture's explicit report and retain its store envelope.
set -euo pipefail
store=$1
attempts=$2
request=$(cat)
# Heartbeats share the sequence allocator; retry only a rejected stale sequence.
for _ in {1..10}; do
  status=0
  response=$(printf '%s\n' "$request" | /bin/bash "$store" mutate) || status=$?
  printf '%s\n' "$response" >>"$attempts"
  if [[ "$status" == 0 ]] && jq -e '.ok' <<<"$response" >/dev/null; then
    printf '%s\n' "$response"
    exit 0
  fi
  if ! jq -e '.ok==false and .error.code=="STALE_SEQUENCE"' <<<"$response" >/dev/null; then
    jq -c '.error' <<<"$response" >&2
    exit 1
  fi
  snapshot=$(/bin/bash "$store" snapshot)
  sequence=$(jq -er --argjson request "$request" '[.state.sessions[] | select(.provider==$request.args.provider and .providerSessionId==$request.args.providerSessionId and .producerEpoch==$request.args.producerEpoch)] | if length==1 then .[0].highWaterSequence+1 else error("fixture session disappeared") end' <<<"$snapshot")
  request=$(jq -c --argjson sequence "$sequence" '.args.sequence=$sequence' <<<"$request")
done
echo 'fixture report remained stale after ten rejected attempts' >&2
exit 1
