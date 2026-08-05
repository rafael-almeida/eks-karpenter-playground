output "cluster_name" {
  value = module.eks.cluster_name
}

output "configure_kubectl" {
  value = "aws eks update-kubeconfig --region ${var.aws_region} --name ${module.eks.cluster_name}"
}

output "karpenter_interruption_queue" {
  value = module.karpenter.queue_name
}

output "test_commands" {
  description = "Run after the ALB address appears in kubectl get ingress -A."
  value = <<-EOT
    ALB=$(kubectl get ingress -n dev0 ui -o jsonpath='{.status.loadBalancer.ingress[0].hostname}')
    curl -H 'Host: ${var.dev0_host}' "http://$ALB/"
    curl -H 'Host: ${var.dev1_host}' "http://$ALB/"
  EOT
}
