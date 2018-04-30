#!/bin/bash

mkdir -p /srv/registry

docker run -d \
  -p 5000:5000 \
  --restart=always \
  --name registry \
  -v /srv/registry:/var/lib/registry \
  registry:2
