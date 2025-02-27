IssAssist Helm Chart
=====================
This is an IssAssist Helm chart for easy installation on Kubernetes 
environments.

Preparations
--------------

### Step 1: Install Cert Manager

_If your Kubernetes cluster already has Cert Manager installed, 
ignore this step. 
Cert Manager manages certificates in the entire cluster and should never be 
installed twice._

Follow the instructions in [Cert Manager's documentation](https://cert-manager.io/docs/installation/helm/).


### Step 2: Install IssAssist

```shell
helm upgrade -i issassist --create-namespace --namespace issassist .
```
