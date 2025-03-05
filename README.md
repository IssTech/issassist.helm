IssAssist Helm Chart
=====================
This is an IssAssist Helm chart for easy installation on Kubernetes 
environments.


Prerequisites
--------------
You need access to the following repositories on your GitHub account:
- https://github.com/IssTech/issassist-utils
- https://github.com/IssTech/IssAssist-api
- https://github.com/IssTech/issassist-frontend
- https://github.com/IssTech/issassist-tsm-agent

If you need access, [contact us](https://www.isstech.io/kontakt)!

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

### Step 2: Install Secret Generator

This is a necessary dependency, just like Cert Manager. It generates passwords.

```shell
git clone https://github.com/IssTech/secret-generator.helm
helm upgrade -i --wait secret-generator \
  --set fullnameOverride=issassist-secret-generator \
  --create-namespace --namespace issassist \
  secret-generator.helm/chart
```

### Step 3: Install IssAssist

```shell
git clone --recurse-submodules https://github.com/IssTech/issassist.helm
helm upgrade -i issassist \
  --create-namespace --namespace issassist \
  --set imageCredentials.username="$GITHUB_USERNAME" \
  --set imageCredentials.password="$GITHUB_TOKEN"
  issassist.helm
```

Uninstall
------------
_This will not uninstall Cert Manager._

```shell
helm uninstall issassist --namespace issassist --wait ; \
  helm uninstall secret-generator --namespace issassist --wait ; \
  kubectl delete namespace issassist --wait=true
```

Remove downloaded repositories:
```shell
rm -rf secret-generator.helm issassist.helm
```
