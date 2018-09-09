# nix-helm simple example

# Requirements

- kubectl 1.11+
- minikube
- helm
- Nix

# Try it out

Download and make kubectl executable:

```
curl -LO https://storage.googleapis.com/kubernetes-release/release/v1.11.0/bin/linux/amd64/kubectl
chmod +x ./kubectl
```

Run Kubernetes in minikube:

```
minikube start --kubernetes-version=v1.11.0
```

Install Tiller service to cluster:

```
helm init --kube-context=minikube
```

Build environment (has to be done every time you change something):

```
nix-build .
```

Create resources on Kubernetes cluster:

```
./result/bin/nix-helm-simple create all
```

Expose url with minikube:

```
minikube service -n apps statics-simple --url
```

Visit the url in browser, and you should see "Welcome to simple example".
