#!/bin/sh

# Starts the server
rake db:migrate
puma \
  -p ${BULLION_PORT:-9292} \
  -e ${RACK_ENV:-production} \
  -t ${MIN_THREADS:-2}:${MAX_THREADS:-32} \
  config.ru
