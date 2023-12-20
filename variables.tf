variable "aws_account_id" {
  description = "環境取り違え防止のためTerraform実行対象のアカウントID"
  type        = number
}

variable "aws_region" {
  description = "リソース作成先のAWSリージョン"
  type        = string
}

variable "aws_vpc_cidr_block" {
  description = "VPC CIDR Block"
  type        = string
  default     = "10.0.0.0/16"
}

variable "aws_eks_cluster_name" {
  description = "EKSクラスター名"
  type        = string
}

variable "aws_eks_cluster_version" {
  description = "EKSクラスターバージョン"
  type        = string
}

variable "aws_eks_nodegroups" {
  description = "EKS Nodegroup数"
  type        = number
}

variable "podinfo_chart_version" {
  description = "podinfo chart version"
  type        = string
}

variable "podinfo_namespace" {
  description = "podinfo chart version"
  type        = string
  default     = "app"
}


# variable "edns_domain_filter" {
#   description = "ExternalDNSがDNSレコードを操作するホストゾーン名"
#   type        = string
# }

# variable "awslbc_chart_version" {
#   description = "AWS Load Balancer ControllerのChartバージョン"
#   type        = string
# }

# variable "awslbc_namespace" {
#   description = "AWS Load Balancer Contollerをデプロイするネームスペース"
#   type        = string
#   default     = "kube-system"
# }

# variable "edns_chart_version" {
#   description = "ExternalDNSのChartバージョン"
#   type        = string
# }

# variable "edns_namespace" {
#   description = "ExternalDNSをデプロイするネームスペース"
#   type        = string
#   default     = "kube-system"
# }
