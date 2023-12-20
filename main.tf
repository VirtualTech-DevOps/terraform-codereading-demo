provider "aws" {
  region              = var.aws_region
  allowed_account_ids = [var.aws_account_id]
}

resource "aws_vpc" "demo" {
  cidr_block = var.aws_vpc_cidr_block
}

data "aws_availability_zones" "available" {
  state = "available"
}

# {{{ public subnet

resource "aws_subnet" "public" {
  for_each = toset(data.aws_availability_zones.available.names)

  vpc_id            = aws_vpc.demo.id
  availability_zone = each.value
  cidr_block        = cidrsubnet(var.aws_vpc_cidr_block, 8, index(tolist(toset(data.aws_availability_zones.available.names)), each.key))
}

resource "aws_internet_gateway" "public" {
  vpc_id = aws_vpc.demo.id
}

resource "aws_route_table" "public" {
  vpc_id = aws_vpc.demo.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.public.id
  }
}

resource "aws_route_table_association" "public" {
  for_each = aws_subnet.public

  subnet_id      = each.value.id
  route_table_id = aws_route_table.public.id
}

# }}}

# {{{ private subnet

resource "aws_subnet" "private" {
  for_each = toset(data.aws_availability_zones.available.names)

  vpc_id            = aws_vpc.demo.id
  availability_zone = each.value
  cidr_block        = cidrsubnet(var.aws_vpc_cidr_block, 8, index(tolist(toset(data.aws_availability_zones.available.names)), each.key) + length(aws_subnet.public))
}

resource "aws_eip" "nat_gateway" {}

resource "aws_nat_gateway" "private" {
  subnet_id     = aws_subnet.public[data.aws_availability_zones.available.names[0]].id
  allocation_id = aws_eip.nat_gateway.id
}

resource "aws_route_table" "private" {
  vpc_id = aws_vpc.demo.id

  route {
    cidr_block     = "0.0.0.0/0"
    nat_gateway_id = aws_nat_gateway.private.id
  }
}

resource "aws_route_table_association" "private" {
  for_each = aws_subnet.private

  subnet_id      = each.value.id
  route_table_id = aws_route_table.private.id
}

# }}}

# {{{ eks

data "aws_iam_policy_document" "cluster_assume_role" {
  statement {
    effect = "Allow"

    principals {
      type        = "Service"
      identifiers = ["eks.amazonaws.com"]
    }

    actions = ["sts:AssumeRole"]
  }
}

resource "aws_iam_role" "cluster" {
  name_prefix        = "${var.aws_eks_cluster_name}-cluster-"
  assume_role_policy = data.aws_iam_policy_document.cluster_assume_role.json

  managed_policy_arns = [
    "arn:aws:iam::aws:policy/AmazonEKSClusterPolicy",
    "arn:aws:iam::aws:policy/AmazonEKSVPCResourceController",
  ]
}

resource "aws_eks_cluster" "demo" {
  name     = var.aws_eks_cluster_name
  role_arn = aws_iam_role.cluster.arn

  vpc_config {
    subnet_ids = [for k, v in aws_subnet.public : v.id]
  }

  version = var.aws_eks_cluster_version
}

# }}}

# {{{ nodegroup

data "aws_iam_policy_document" "nodegroup_assume_role" {
  statement {
    effect = "Allow"

    principals {
      type        = "Service"
      identifiers = ["ec2.amazonaws.com"]
    }

    actions = ["sts:AssumeRole"]
  }
}

resource "aws_iam_role" "nodegroup" {
  name_prefix        = "${aws_eks_cluster.demo.name}-nodegroup-"
  assume_role_policy = data.aws_iam_policy_document.nodegroup_assume_role.json

  managed_policy_arns = [
    "arn:aws:iam::aws:policy/AmazonEKSWorkerNodePolicy",
    "arn:aws:iam::aws:policy/AmazonEC2ContainerRegistryReadOnly",
    "arn:aws:iam::aws:policy/AmazonEKSWorkerNodePolicy",
    "arn:aws:iam::aws:policy/AmazonEKS_CNI_Policy",
    "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
  ]
}

resource "aws_eks_node_group" "demo" {
  cluster_name           = aws_eks_cluster.demo.name
  node_group_name_prefix = "${aws_eks_cluster.demo.name}-"
  node_role_arn          = aws_iam_role.nodegroup.arn
  subnet_ids             = [for k, v in aws_subnet.private : v.id]

  scaling_config {
    min_size     = 1
    max_size     = var.aws_eks_nodegroups
    desired_size = var.aws_eks_nodegroups
  }

  update_config {
    max_unavailable = 1
  }
}

# }}}

# {{{ eks addon

resource "aws_eks_addon" "vpc_cni" {
  cluster_name = aws_eks_cluster.demo.name
  addon_name   = "vpc-cni"
}

resource "aws_eks_addon" "coredns" {
  cluster_name = aws_eks_cluster.demo.name
  addon_name   = "coredns"
}

resource "aws_eks_addon" "kube_proxy" {
  cluster_name = aws_eks_cluster.demo.name
  addon_name   = "kube-proxy"
}

# resource "aws_eks_addon" "pod_identity_agent" {
#   cluster_name = aws_eks_cluster.demo.name
#   addon_name   = "eks-pod-identity-agent"
# }

# }}}

# {{{ helm

data "aws_eks_cluster" "demo" {
  name = aws_eks_cluster.demo.name
}

data "aws_eks_cluster_auth" "demo" {
  name = aws_eks_cluster.demo.name
}

provider "helm" {
  kubernetes {
    host                   = aws_eks_cluster.demo.endpoint
    cluster_ca_certificate = base64decode(data.aws_eks_cluster.demo.certificate_authority.0.data)
    token                  = data.aws_eks_cluster_auth.demo.token
  }
}

# }}}

# {{{ podinfo

resource "helm_release" "podinfo" {
  name             = "podinfo"
  repository       = "https://stefanprodan.github.io/podinfo"
  chart            = "podinfo"
  version          = var.podinfo_chart_version
  namespace        = var.podinfo_namespace
  create_namespace = true
  wait             = true

  set {
    name  = "replicaCount"
    value = var.aws_eks_nodegroups
  }
}

# }}}

# {{{ oidc

# resource "aws_iam_openid_connect_provider" "eks" {
#   url             = aws_eks_cluster.demo.identity[0].oidc[0].issuer
#   client_id_list  = ["sts.amazonaws.com"]
#   thumbprint_list = data.tls_certificate.eks.certificates.*.sha1_fingerprint
# }

# data "tls_certificate" "eks" {
#   url = aws_eks_cluster.demo.identity[0].oidc[0].issuer
# }

# }}}

# {{{ aws load balancer controller

# data "aws_iam_policy_document" "awslbc_assume_role" {
#   statement {
#     effect = "Allow"

#     principals {
#       type        = "Federated"
#       identifiers = [aws_iam_openid_connect_provider.eks.arn]
#     }

#     actions = ["sts:AssumeRoleWithWebIdentity"]

#     condition {
#       test     = "StringEquals"
#       variable = "${aws_iam_openid_connect_provider.eks.url}:sub"
#       values   = ["system:serviceaccount:${var.awslbc_namespace}:aws-load-balancer-controller"]
#     }

#     condition {
#       test     = "StringEquals"
#       variable = "${aws_iam_openid_connect_provider.eks.url}:aud"
#       values   = ["sts.amazonaws.com"]
#     }
#   }
# }

# resource "aws_iam_role" "awslbc" {
#   name_prefix        = "${aws_eks_cluster.demo.name}-awslbc-"
#   assume_role_policy = data.aws_iam_policy_document.awslbc_assume_role.json
# }

# data "http" "awslbc" {
#   url = "https://raw.githubusercontent.com/kubernetes-sigs/aws-load-balancer-controller/main/docs/install/iam_policy.json"
# }

# resource "aws_iam_role_policy" "awslbc" {
#   role   = aws_iam_role.awslbc.id
#   policy = data.http.awslbc.response_body
# }

# resource "helm_release" "awslbc" {
#   name       = "aws-load-balancer-controller"
#   repository = "https://aws.github.io/eks-charts"
#   chart      = "aws-load-balancer-controller"
#   version    = var.awslbc_chart_version
#   namespace  = var.awslbc_namespace
#   wait       = true

#   set {
#     name  = "clusterName"
#     value = aws_eks_cluster.demo.name
#   }

#   set {
#     name  = "serviceAccount.create"
#     value = true
#   }

#   set {
#     name  = "serviceAccount.name"
#     value = "aws-load-balancer-controller"
#   }

#   set {
#     name  = "serviceAccount.annotations.eks\\.amazonaws\\.com/role-arn"
#     value = aws_iam_role.awslbc.arn
#   }

#   set {
#     name  = "enableCertManager"
#     value = false
#   }

#   set {
#     name  = "region"
#     value = var.aws_region
#   }

#   set {
#     name  = "vpcId"
#     value = aws_vpc.demo.id
#   }

#   set {
#     name  = "createIngressClassResource"
#     value = true
#   }
# }

# }}}

# {{{ external-dns

# data "aws_iam_policy_document" "edns_assume_role" {
#   statement {
#     effect = "Allow"

#     principals {
#       type        = "Federated"
#       identifiers = [aws_iam_openid_connect_provider.eks.arn]
#     }

#     actions = ["sts:AssumeRoleWithWebIdentity"]

#     condition {
#       test     = "StringEquals"
#       variable = "${aws_iam_openid_connect_provider.eks.url}:sub"
#       values   = ["system:serviceaccount:${var.edns_namespace}:external-dns"]
#     }

#     condition {
#       test     = "StringEquals"
#       variable = "${aws_iam_openid_connect_provider.eks.url}:aud"
#       values   = ["sts.amazonaws.com"]
#     }
#   }
# }

# resource "aws_iam_role" "edns" {
#   name_prefix        = "${aws_eks_cluster.demo.name}-edns-"
#   assume_role_policy = data.aws_iam_policy_document.edns_assume_role.json
# }

# data "aws_iam_policy_document" "edns" {
#   statement {
#     effect = "Allow"

#     resources = [
#       "arn:aws:route53:::hostedzone/*"
#     ]

#     actions = [
#       "route53:ChangeResourceRecordSets"
#     ]
#   }

#   statement {
#     effect = "Allow"

#     resources = ["*"]

#     actions = [
#       "route53:ListHostedZones",
#       "route53:ListResourceRecordSets",
#       "route53:ListTagsForResource"
#     ]
#   }
# }

# resource "aws_iam_role_policy" "edns" {
#   role   = aws_iam_role.edns.id
#   policy = data.aws_iam_policy_document.edns.json
# }

# resource "helm_release" "edns" {
#   name       = "external-dns"
#   repository = "https://kubernetes-sigs.github.io/external-dns/"
#   chart      = "external-dns"
#   version    = var.edns_chart_version
#   namespace  = var.edns_namespace
#   wait       = true

#   set {
#     name  = "serviceAccount.create"
#     value = true
#   }

#   set {
#     name  = "serviceAccount.name"
#     value = "external-dns"
#   }

#   set {
#     name  = "serviceAccount.annotations.eks\\.amazonaws\\.com/role-arn"
#     value = aws_iam_role.edns.arn
#   }

#   set_list {
#     name  = "sources"
#     value = ["service", "ingress"]
#   }

#   set_list {
#     name  = "domainFilters"
#     value = [var.edns_domain_filter]
#   }

#   set {
#     name  = "policy"
#     value = "sync"
#   }

#   set {
#     name  = "provider"
#     value = "aws"
#   }

#   set {
#     name  = "registry"
#     value = "txt"
#   }

#   set {
#     name  = "txtOwnerId"
#     value = aws_eks_cluster.demo.name
#   }
# }

# }}}
