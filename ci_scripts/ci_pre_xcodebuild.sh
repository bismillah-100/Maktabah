#!/bin/sh

if [ -n "$WORKER_URL" ]; then
  /usr/libexec/PlistBuddy -c "Set :WorkerURL $WORKER_URL" ../Source/Direct-Info.plist
  /usr/libexec/PlistBuddy -c "Set :WorkerURL $WORKER_URL" ../Source/iOS-Info.plist
  echo "Injected WORKER_URL into Info.plist files."
else
  echo "WORKER_URL environment variable is not set."
fi
