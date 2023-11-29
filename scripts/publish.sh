#!/bin/sh

VERSION_TAG=`grep bullion Gemfile.lock | head -n 1 | grep -oE '[0-9]+\.[0-9]+\.[0-9]+'`
docker tag bullion:local jgnagy/bullion:$VERSION_TAG
docker tag bullion:local jgnagy/bullion:latest
docker push jgnagy/bullion:$VERSION_TAG
docker push jgnagy/bullion:latest
