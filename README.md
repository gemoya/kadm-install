## Instalación de Kubernetes v1.8
### Prerequisitos e instalación kubeadm
Utilizando Ubuntu 16.04 , se requiere instalar los prerequisitos y la versión de docker: 
docker-ce=17.03.1~ce-0~ubuntu-xenial para **TODOS los hosts que vayan a ser parte del cluster**, tanto rol de master como workers
`````shell
apt-get update
apt-get install -y \
    apt-transport-https \
    ca-certificates \
    curl \
    software-properties-common

curl -fsSL https://download.docker.com/linux/ubuntu/gpg | apt-key add -
add-apt-repository \
   "deb [arch=amd64] https://download.docker.com/linux/$(. /etc/os-release; echo "$ID") \
   $(lsb_release -cs) \
   stable"

apt-get update && apt-get install -y docker-ce=17.03.1~ce-0~ubuntu-xenial
```

Luego es necesario modificar el unit del servicio docker para que acepte algún docker-registry inseguro, para ello abrir el archivo /lib/systemd/system/docker.service y editar la línea con ***ExecStart=/usr/bin/dockerd -H fd://*** para que quede de la siguiente forma:

`````shell
ExecStart=/usr/bin/dockerd -H fd:// --insecure-registry=${REGISTRY_HOST_IP}:{REGISTRY_HOST_PORT}
```
**Esta instalación contempla que el registry exista en el host master y en el puerto 5000.**




### Instalación de Kubeadm, kubelet y kubectl para Kubernetes v1.8
#### Instalar kubeadm y levantar cluster
Para todos los hosts que vayan a pertenecer al cluster se debe ejecutar lo siguiente:
`````shell
apt-get update && apt-get install -y apt-transport-https
curl -s https://packages.cloud.google.com/apt/doc/apt-key.gpg | apt-key add -
cat <<EOF >/etc/apt/sources.list.d/kubernetes.list
deb http://apt.kubernetes.io/ kubernetes-xenial main
EOF
apt-get update

apt-get install kubeadm=1.8.3-00 kubelet=1.8.3-00 kubectl=1.8.3-00
```

#### Iniciar cluster con kubeadm desde nodo master
Iniciar
`````shell
kubeadm init --pod-network-cidr=10.244.0.0/16
```
Agregar archivo de configuración para kubeadm:
`````shell
mkdir -p $HOME/.kube
sudo cp -i /etc/kubernetes/admin.conf $HOME/.kube/config
sudo chown $(id -u):$(id -g) $HOME/.kube/config
```
Agregar flannel al cluster
`````shell
kubectl apply -f https://raw.githubusercontent.com/coreos/flannel/v0.9.1/Documentation/kube-flannel.yml
```

Al aplicar kubeadm init, se debe obtener una salida del tipo:
`````shell
kubeadm join --token <token> <master-ip>:<master-port> --discovery-token-ca-cert-hash sha256:<hash>
```
La cual debe ser utilizada para agregar en los hosts

Para comprobar que los nodos se encuentran en estado listo:
`````shell
kubectl get nodes
```

#### Instalar helm



Descargar el binario helm, descomprimirlo y agregarlo al PATH de binarios utilizables
`````shell
wget https://storage.googleapis.com/kubernetes-helm/helm-v2.7.2-linux-amd64.tar.gz
tar -xcvf helm-v2.7.2-linux-amd64.tar.gz
cp $PWD/linux-amd64/helm /usr/local/bin/
```
Luego agregar roles para utilizar helm con los privilegios requeridos:
`````shell
kubectl create sa tiller-deploy -n kube-system
kubectl create clusterrolebinding helm --clusterrole=cluster-admin --serviceaccount=kube-system:tiller-deploy
helm init --service-account=tiller-deploy
```

Para comprobar el estado de helm, se puede ejecutar:
`````shell
kubectl get po -n kube-system
```
donde debe aparecer un pod *tiller-deploy* en estado running.

## Instalar Deis Workflow
**En el nodo maestro:**

### Docker Registry

`````shell
mkdir -p /srv/registry

docker run -d \
  -p 5000:5000 \
  --restart=always \
  --name registry \
  -v /srv/registry:/var/lib/registry \
  registry:2
```

### Desplegar Deis Workflow
Instalar repositorio de Deis para Helm y descargar Chart:
`````shell
helm repo add deis https://charts.deis.com/workflow
helm fetch deis/workflow --untar
cd workflow
# edit values.yaml
```
Es necesario editar el archivo values.yaml para que contemple un registry externo y permita utilizar RBAC, estas ediciones son las siguientes al interior del archivo:

Registry externo:
`````shell
  registry_location: "off-cluster"
```
Utilizar RBAC:
`````shell
  use_rbac: true
```
Configuración registry externo:
`````shell
registry-token-refresher:
  # Time in minutes after which the token should be refreshed.
  # Leave it empty to use the default provider time.
  token_refresh_time: ""
  off_cluster_registry:
    hostname: "REGISTRY_HOST_IP:REGISTRY_HOST_PORT"
    organization: "cocha"
    username: ""
    password: ""
```
**Donde REGISTRY_HOST_IP:REGISTRY_HOST_PORT son los mismos utilizados en el unit de docker**
Ahora es posible desplegar Deis Workflow mediante  helm:
`````shell
helm install deis/workflow --namespace deis -f values.yaml
```
Se debe esperar que todos los pods se encuentren en estado running, esto se puede conocer mediante kubectl
`````shell
kubectl -n deis get pods
```
Una vez que todos los pods se encuentren en estado en ejecución se sigue con la configuración de HAproxy como punto de conexión entre el cluster y el exterior.

### Instalar HAproxy
El rol del HAproxy es redirigir el tráfico desde puertos estándar hacia los que son utilizados por los componentes de Deis  a través de un servicio de Kubernetes.
El primer paso es instalar haproxy:
`````shell
apt-get install haproxy -y
```

Después se requiere conocer los puertos del host tomados por Kubernetes para Deis para configurarlos en HAproxy:
`````shell
kubectl -n deis get svc | grep deis-router | awk '{print $5}'
```
La cual entregará una salida como la siguiente(**los puertos 3xxxx son aleatorios y cambian según cada instalación**)
`````shell
80:31639/TCP,443:30868/TCP,2222:31188/TCP,9090:31628/TCP
```
Para estos puertos se debe configurar como frontend 80,443, 2222 (9090 es opcional) y los backend serán la IP del master con los puertos 3xxxx. Siguiende el ejemplo anterior, asociación es la siguiente:
* Frontend 80 - Backend 31639
* Frontend 443 - Backend 30868
* Frontend 2222 - Backend 31188


Estos se deben agregar al final del archivo /etc/haproxy/haproxy.cfg tal como se muestra a continuación:
`````shell
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
	server deis-builder-nodo IP_MASTER:31188

backend deis-http-cluster
	mode tcp
	server deis-http-nodo IP_MASTER:31639

backend traefik-https-cluster
	mode tcp
	server deis-https-nodo IP_MASTER:30868
```
Nuevamente se hace énfasis en que los puertos 31188, 31639 y 30868 son ejemplos de esta guía y varían según cada instalación de Deis.

Una vez modificado el archivo de configuración, es necesario reiniciar el servicio:
`````shell
systemctl restart haproxy
```

### Utilizar Plataforma como Servicio
Estos pasos deben ser ejecutados desde un host que tenga acceso a los puertos 80, 443 y 2222  del nodo maestro del cluster Kubernetes. 

Es necesario disponer un registro wilcard hacia el nodo maestro por ejemplo *.dev.cocha.com o bien, en caso de no tenerlo, editar el archivo /etc/hosts desde el equipo en que se utilizará el cliente deis incluyendo las directivas mínimas para utilizar deis, a continuación se deja un ejemplo de /etc/hosts **utilizando el dominio dev.cocha.com**:
`````shell
IP_MASTER deis.dev.cocha.com
IP_MASTER deis-builder.dev.cocha.com
```
Posteriormente por cada aplicación:
`````shell
IP_MASTER nombre-aplicacion.dev.cocha.com
```

#### Instalación cliente deis
`````shell
curl -sSL http://deis.io/deis-cli/install-v2.sh | bash
sudo mv $PWD/deis /usr/local/bin/deis
deis version
```


#### Registro administrador 
El primer registro pertenece al administrador del cluster
`````shell
deis register http://deis.dev.cocha.com
```

#### Agregar llave ssh para operar con repositorio git
`````shell
deis keys:add ~/path/to/ssh_key.pub
```

#### Levantar aplicación mediante repositorio git
`````shell
git clone https://github.com/gemoya/example-go
cd example-go
deis create nombre-app
git push deis master
curl -i nombre-app.dev.cocha.com
```
recordar agregar nombre-app.dev.cocha.com en archivo /etc/hosts si no se tiene un wildcard apuntando al servidor master.

#### Registrar usuarios desde administrador
`````shell
deis register http://deis.dev.cocha.com --login=false
```
