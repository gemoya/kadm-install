#!/bin/bash

SVC_IP=$(kubectl -n deis get svc | grep deis-router | awk '{print $3}')
SVC_PORTS=$(kubectl -n deis get svc | grep deis-router | awk '{print $5}')

NODE_HTTP=$(echo $SVC_PORTS | cut -d ":" -f2 | cut -d '/' -f1)
NODE_HTTPS=$(echo $SVC_PORTS | cut -d ":" -f3 | cut -d '/' -f1)
NODE_SSH=$(echo $SVC_PORTS | cut -d ":" -f4 | cut -d '/' -f1)
NODE_HEALTH=$(echo $SVC_PORTS | cut -d ":" -f5 | cut -d '/' -f1)


echo "global
	log /dev/log	local0
	log /dev/log	local1 notice
	chroot /var/lib/haproxy
	stats socket /run/haproxy/admin.sock mode 660 level admin
	stats timeout 30s
	user haproxy
	group haproxy
	daemon

	# Default SSL material locations
	ca-base /etc/ssl/certs
	crt-base /etc/ssl/private

	# Default ciphers to use on SSL-enabled listening sockets.
	# For more information, see ciphers(1SSL). This list is from:
	#  https://hynek.me/articles/hardening-your-web-servers-ssl-ciphers/
	ssl-default-bind-ciphers ECDH+AESGCM:DH+AESGCM:ECDH+AES256:DH+AES256:ECDH+AES128:DH+AES:ECDH+3DES:DH+3DES:RSA+AESGCM:RSA+AES:RSA+3DES:!aNULL:!MD5:!DSS
	ssl-default-bind-options no-sslv3

defaults
	log	global
	mode	http
	option	httplog
	option	dontlognull
        timeout connect 5000
        timeout client  50000
        timeout server  50000
	errorfile 400 /etc/haproxy/errors/400.http
	errorfile 403 /etc/haproxy/errors/403.http
	errorfile 408 /etc/haproxy/errors/408.http
	errorfile 500 /etc/haproxy/errors/500.http
	errorfile 502 /etc/haproxy/errors/502.http
	errorfile 503 /etc/haproxy/errors/503.http
	errorfile 504 /etc/haproxy/errors/504.http




frontend deis-builder
	mode tcp
	bind 0.0.0.0:2222
	default_backend deis-builder-cluster

frontend deis-http
	mode tcp
	bind 0.0.0.0:80
	default_backend deis-http-cluster

frontend deis-https
	mode tcp
	bind 0.0.0.0:443
	default_backend deis-https-cluster

backend deis-builder-cluster
	mode tcp
	server dbuilder-clusterip ${SVC_IP}:${NODE_SSH}

backend deis-http-cluster
	mode tcp
	server deis-http ${SVC_IP}:${NODE_HTTP}

backend deis-https-cluster
	mode tcp
	server deis-https ${SVC_IP}:${NODE_HTTPS}
" > haproxy.cfg
