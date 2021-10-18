#!/bin/bash
curl -s https://fluxcd.io/install.sh | sudo bash

wget https://github.com/smallstep/cli/releases/download/v0.15.2/step-cli_0.15.2_amd64.deb
sudo dpkg -i step-cli_0.15.2_amd64.deb

cd cloud-native-app/gitops/infrastructure/linkerd

step certificate create identity.linkerd.cluster.local ca.crt ca.key \
--profile root-ca --no-password --insecure \
--san identity.linkerd.cluster.local

step certificate create identity.linkerd.cluster.local issuer.crt issuer.key \
--ca ca.crt --ca-key ca.key --profile intermediate-ca --not-after 8760h --no-password --insecure \
--san identity.linkerd.cluster.local

kubectl -n linkerd create secret generic certs \
--from-file=ca.crt --from-file=issuer.crt \
--from-file=issuer.key -oyaml --dry-run=client \
> certs.yaml

cd ../../..

registryUrl=https://$registryHost
appHostDnsLabel=`echo $appHostName | cut -d '.' -f 1`
registryHostDnsLabel=`echo $registryHost | cut -d '.' -f 1`


exp=$(date -d '+8760 hour' +"%Y-%m-%dT%H:%M:%SZ")
sed -i "s/{cert_expiry}/$exp/g" gitops/clusters/production/infrastructure-linkerd.yaml
sed -i "s/{registryHost}/$registryHost/g" gitops/clusters/production/infrastructure-harbor.yaml
sed -i "s%{registryUrl}%$registryUrl%g" gitops/clusters/production/infrastructure-harbor.yaml
sed -i "s%{registryUrl}%$registryUrl%g" gitops/clusters/production/infrastructure-seed.yaml
sed -i "s/{cluster_issuer_email}/$cluster_issuer_email/g" gitops/clusters/production/infrastructure-certmanager.yaml

sed -i "s/{cicdWebhookHost}/$appHostName/g" gitops/clusters/production/app-devops.yaml
sed -i "s/{registryHost}/$registryHost/g" gitops/clusters/production/app-devops.yaml
sed -i "s/{appHostName}/$appHostName/g" gitops/clusters/production/app-devops.yaml
sed -i "s/{sendGridApiKey}/$sendGridApiKey/g" gitops/clusters/production/app-devops.yaml

sed -i "s/{registryHostDnsLabel}/$registryHostDnsLabel/g" gitops/clusters/production/infrastructure-harbor-nginx.yaml
sed -i "s/{appHostDnsLabel}/$appHostDnsLabel/g" gitops/clusters/production/infrastructure-nginx.yaml

cd gitops/app/core

kubectl create secret docker-registry regcred \
--docker-server="https://$registryHost" --docker-username=conexp  --docker-password=FTA@CNCF0n@zure3  --docker-email=user@mycompany.com -n conexp-mvp -oyaml --dry-run=client \
> regcred-conexp.yaml

kubectl create secret docker-registry regcred \
--docker-server="https://$registryHost" --docker-username=conexp  --docker-password=FTA@CNCF0n@zure3  --docker-email=user@mycompany.com -n openfaas-fn -oyaml --dry-run=client \
> regcred-openfaas.yaml

cd ../../..

git add *
git commit -m  "Auto commit prep files"
git push -u origin master

flux bootstrap github \
  --owner="$owner"> \
  --repository=cloud-native-app \
  --path=gitops/clusters/production \
  --personal

curl -H "Authorization: token $GITHUB_TOKEN" \
  -X POST  \
  -H "Accept: application/vnd.github.v3+json" \
  https://api.github.com/repos/$owner/cloud-native-app/hooks \
  -d "{\"config\":{\"url\":\"https://$appHostName/cd\",\"content_type\":\"json\"}}"
