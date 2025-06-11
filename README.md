IssAssist Helm Chart
=====================
This is an IssAssist Helm chart for easy installation on Kubernetes 
environments.


Prerequisites
--------------
You need access to the following repositories on your GitHub account:
- https://github.com/IssTech/issassist-utils
- https://github.com/IssTech/issassist-api
- https://github.com/IssTech/issassist-webgui
- https://github.com/IssTech/issassist-tsm-agent

If you don't have access and want to try out IssAssist, feel free to [contact us](https://www.isstech.io/kontakt)!

Follow [GitHub's documentation](https://docs.github.com/en/authentication/keeping-your-account-and-data-secure/managing-your-personal-access-tokens#creating-a-personal-access-token-classic) 
to generate a Personal Access Token (PAT).
Make sure to select the scope **read:packages**, which allows Kubernetes to 
access the IssAssist container images (packages) using the token.

Then before the installation, define:
```shell
export GITHUB_USERNAME=your_github_username
export GITHUB_TOKEN=your_pat_token
```

Installation
--------------

### Step 1: Install Cert Manager

_If your Kubernetes cluster already has Cert Manager installed, 
ignore this step. 
Cert Manager manages certificates in the entire cluster and should never be 
installed twice._

Follow the instructions in 
[Cert Manager's documentation](https://cert-manager.io/docs/installation/helm/).

### Step 2: Install IssAssist

If you want to use another domain name than "issassist", you can change it in 
`global.publicDomainName="issassist"` below before executing the commands.

```shell
git clone https://github.com/IssTech/issassist.helm
helm upgrade -i issassist \
  --create-namespace --namespace issassist \
  --set global.publicDomainName="issassist" \
  --set imageCredentials.username="$GITHUB_USERNAME" \
  --set imageCredentials.password="$GITHUB_TOKEN" \
  ./issassist.helm
```

If you are not using publicly registered domain name, make sure to add your
domain name (default is "issassist") to your `/etc/hosts` file and make it
point to the IP address of your Kubernetes cluster.

#### Custom domain name on Minikube
If you use Minikube, run:
```shell
echo "$(minikube ip) issassist" >> /etc/hosts
```

### Step 3: Log in
To log in, go to: https://issassist/

> [!NOTE]
> The URL will of course be different if you have changed the domain name on 
> Step 2.

The username is **admin** and the password can be fetched by running:
```shell
kubectl get secrets admin-auth -n issassist -o jsonpath='{.data.password}' | base64 -d
```

Enjoy!

Uninstall
------------
_This will not uninstall Cert Manager._

```shell
helm uninstall issassist --namespace issassist --wait ; \
  kubectl delete namespace issassist --wait=true
```

Remove the downloaded repository:
```shell
rm -rf issassist.helm
```
