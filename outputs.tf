output "aws_eks_update_kubeconfig" {
  value = "aws eks update-kubeconfig --name ${var.aws_eks_cluster_name} --alias ${var.aws_eks_cluster_name}"
}

output "port_forward_command" {
  value = "kubectl port-forward -n ${var.podinfo_namespace} services/podinfo 9898:9898"
}
