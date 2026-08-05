# EKS + Karpenter + shared ALB routing

This Terraform project uses an existing VPC and subnets to create:

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

- An existing VPC and at least two private subnets in different Availability Zones
- Public subnets tagged `kubernetes.io/role/elb=1` so the controller can discover them for the internet-facing ALB
- Terraform 1.8+
- AWS CLI authenticated with permissions to use the supplied VPC and create EKS, EC2, IAM, SQS, EventBridge, and ELB resources
- `kubectl`
- Access to the public Terraform Registry and Helm repositories

## Deploy with Jenkins

Create an infrastructure Pipeline job that uses the repository's `Jenkinsfile`. The Jenkins agent
must have Terraform, AWS CLI, and AWS credentials (or an instance/task role) with
the required permissions. Build parameters are:

- `VPC_ID`: the existing VPC ID
- `SUBNET_IDS`: comma-separated private subnet IDs spanning at least two Availability Zones
- `AWS_REGION`: the AWS region containing the VPC
- `ACTION`: `plan`, `apply`, or `destroy`

The pipeline converts `SUBNET_IDS` to Terraform's list format and exports both
network parameters as `TF_VAR_` environment variables. Destroy requires an
interactive Jenkins confirmation.

State is local to the Jenkins workspace by default. Configure an S3 backend with
state locking before using this pipeline for shared or production infrastructure.

## Deploy disposable CRUD stacks with Jenkins

Create a second Pipeline job from the same repository and set its script path to
`Jenkins.deploy`. This job deploys independent todo applications into namespaces
named `crud-<stack_id>`, where `stack_id` is a randomly generated four-character
lowercase alphanumeric value.

Each stack contains one Nginx UI, one PostgREST backend, and one PostgreSQL
database. The UI proxies `/api/` to the namespace-local backend, and only the UI
is exposed through an Ingress. Every stack joins the existing `shared-ui`
IngressGroup, so the AWS Load Balancer Controller adds each hostname to the
shared ALB instead of creating another load balancer.

The Jenkins agent needs AWS CLI, `kubectl`, `curl`, OpenSSL, AWS credentials, and
permission to access the EKS cluster and manage namespaces and namespaced
resources. Pipeline parameters are:

- `ACTION`: `deploy` or `delete`
- `AWS_REGION`: region containing the EKS cluster
- `CLUSTER_NAME`: EKS cluster name
- `BASE_DOMAIN`: wildcard domain used for new stacks
- `STACK_ID`: required only for deletion

Before deploying, configure wildcard DNS for `*.<base_domain>` to resolve to the
shared ALB. DNS management is intentionally outside this project. For example,
with `BASE_DOMAIN=preview.example.com`, a generated ID of `a1b2` is available at:

```text
http://a1b2.preview.example.com
```

Run the job with `ACTION=deploy`; `STACK_ID` is ignored for deploys. The build
description and final log contain the generated ID, namespace, URL, and deletion
instructions. The pipeline waits for all three Deployments and verifies both the
internal API and public ALB route. A failed deploy automatically removes its
partially created namespace.

To remove that stack, run the same job with:

```text
ACTION=delete
STACK_ID=a1b2
```

Deletion is allowed only when the namespace has the ownership labels written by
`Jenkins.deploy`. Deleting the namespace removes its Secret, ConfigMaps,
Deployments, Services, Ingress, and database data. PostgreSQL uses `emptyDir`, so
its data is also lost whenever the database pod is replaced; this application is
for temporary testing only.

Multiple stacks may coexist and separate Jenkins builds may deploy concurrently.
The practical number is limited by cluster capacity and AWS ALB listener-rule and
target-group quotas. The demo API is intentionally unauthenticated and HTTP-only.

## Deploy locally

```bash
cp terraform.tfvars.example terraform.tfvars
# Set vpc_id and subnet_ids in terraform.tfvars.
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

1. EKS, IAM, SQS, and EventBridge
2. Helm releases and Kubernetes resources

## Existing network requirements

The supplied subnets are used for the EKS managed node group and Karpenter nodes,
so they should normally be private subnets with outbound access through NAT or
the required VPC endpoints. The internet-facing ALB discovers public subnets by
their `kubernetes.io/role/elb=1` tag; those public subnets do not need to be passed
in `SUBNET_IDS`.

## Production changes to consider

- Restrict the public EKS endpoint or use private access through a CI runner in the VPC
- Add Route 53 records and ACM-managed HTTPS
- Apply AWS WAF, access logs, deletion protection, and ALB security-group restrictions
- Pin the AL2023 AMI alias instead of using `al2023@latest`
- Define PodDisruptionBudgets and topology spread constraints
- Enforce which namespaces may join the shared ALB IngressGroup
- Use separate ALBs for namespaces belonging to different trust boundaries
- Add observability, backups, policy enforcement, and cost controls

## Destroy

Delete all disposable CRUD stacks and the Terraform-managed application Ingress
resources before destroying the infrastructure so the controller has time to
remove ALB rules and target groups:

```bash
kubectl get namespace -l app.kubernetes.io/part-of=crud-demo
# Delete each listed stack with Jenkins.deploy ACTION=delete, or after verifying
# the labels, delete its crud-<stack_id> namespace manually.
kubectl delete ingress ui -n dev0
kubectl delete ingress ui -n dev1
terraform destroy
```
