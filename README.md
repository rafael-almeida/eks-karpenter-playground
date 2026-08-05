# EKS + Karpenter + shared ALB routing

This Terraform project creates:

- A three-AZ VPC with public and private subnets
- An EKS cluster
- A small managed node group for system controllers
- Karpenter IAM resources, interruption SQS queue, EventBridge rules, and Helm release
- An AWS Load Balancer Controller IAM role and Helm release
- `dev0` and `dev1` namespaces
- A `ui` Deployment and `ui` Service in each namespace
- Two namespace-local Ingress resources combined into one shared ALB

## Request routing

The client does not send a Kubernetes namespace. The ALB maps the request hostname to the Ingress rule belonging to that namespace:

```text
Host: dev0.example.com -> Ingress dev0/ui -> Service dev0/ui
Host: dev1.example.com -> Ingress dev1/ui -> Service dev1/ui
```

Both Ingress resources use:

```yaml
alb.ingress.kubernetes.io/group.name: shared-ui
```

Therefore, the AWS Load Balancer Controller places both host rules on one ALB.

## Prerequisites

- Terraform 1.8+
- AWS CLI authenticated with permissions to create VPC, EKS, EC2, IAM, SQS, EventBridge, and ELB resources
- `kubectl`
- Access to the public Terraform Registry and Helm repositories

## Deploy

```bash
cp terraform.tfvars.example terraform.tfvars
terraform init
terraform plan
terraform apply
```

Configure `kubectl`:

```bash
aws eks update-kubeconfig \
  --region us-east-1 \
  --name demo-karpenter-alb
```

Inspect the controllers and Karpenter objects:

```bash
kubectl get pods -n kube-system
kubectl get ec2nodeclass,nodepool
kubectl get ingress -A
```

The ALB can take several minutes to become active. Obtain its DNS name and test host-based routing without creating Route 53 records:

```bash
ALB=$(kubectl get ingress -n dev0 ui \
  -o jsonpath='{.status.loadBalancer.ingress[0].hostname}')

curl -H 'Host: dev0.example.com' "http://$ALB/"
curl -H 'Host: dev1.example.com' "http://$ALB/"
```

Expected responses:

```text
ui from namespace dev0
ui from namespace dev1
```

For normal browser access, create DNS records for `dev0.example.com` and `dev1.example.com` that point to the ALB. For production, add an ACM certificate and configure an HTTPS listener.

## Trigger Karpenter

The sample UI pods are small and may fit on the system node group. To demonstrate Karpenter, increase replicas and requests:

```bash
kubectl scale deployment/ui -n dev0 --replicas=30
kubectl get pods -n dev0 -w
kubectl get nodes -w
```

Karpenter should create EC2 capacity after pods become unschedulable.

## Bootstrap behavior

Terraform configures AWS infrastructure, Helm charts, and Kubernetes objects in one root module. Depending on network conditions and provider behavior, the first apply can encounter a temporary Kubernetes API connection error while EKS is becoming ready. Re-running `terraform apply` is safe. For stricter production workflows, split this into two states:

1. VPC, EKS, IAM, SQS, and EventBridge
2. Helm releases and Kubernetes resources

## Production changes to consider

- Replace the single NAT gateway with one NAT gateway per AZ
- Restrict the public EKS endpoint or use private access through a CI runner in the VPC
- Add Route 53 records and ACM-managed HTTPS
- Apply AWS WAF, access logs, deletion protection, and ALB security-group restrictions
- Pin the AL2023 AMI alias instead of using `al2023@latest`
- Define PodDisruptionBudgets and topology spread constraints
- Enforce which namespaces may join the shared ALB IngressGroup
- Use separate ALBs for namespaces belonging to different trust boundaries
- Add observability, backups, policy enforcement, and cost controls

## Destroy

Delete application Ingress resources before destroying the infrastructure so the controller has time to remove the ALB and target groups:

```bash
kubectl delete ingress ui -n dev0
kubectl delete ingress ui -n dev1
terraform destroy
```
