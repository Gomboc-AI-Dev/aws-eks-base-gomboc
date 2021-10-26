locals {
  kibana_domain_name = "kibana-${local.domain_suffix}"
  apm_domain_name    = "apm-${local.domain_suffix}"
}

resource "kubernetes_storage_class" "elk" {
  metadata {
    name = "elk"
  }
  storage_provisioner    = "kubernetes.io/aws-ebs"
  reclaim_policy         = "Retain"
  allow_volume_expansion = true
  parameters = {
    type      = "gp2"
    encrypted = true
    fsType    = "ext4"
  }
}

module "elastic_tls" {
  source = "../modules/self-signed-certificate"

  name                  = local.name
  common_name           = "elasticsearch-master"
  dns_names             = [local.domain_name, "*.${local.domain_name}", "elasticsearch-master", "elasticsearch-master.${kubernetes_namespace.elk.id}", "kibana", "kibana.${kubernetes_namespace.elk.id}", "kibana-kibana", "kibana-kibana.${kubernetes_namespace.elk.id}", "logstash", "logstash.${kubernetes_namespace.elk.id}"]
  validity_period_hours = 8760
  early_renewal_hours   = 336
}

resource "kubernetes_secret" "elasticsearch_credentials" {
  metadata {
    name      = "elastic-credentials"
    namespace = kubernetes_namespace.elk.id
  }

  data = {
    "username" = "elastic"
    "password" = random_string.elasticsearch_password.result
  }
}

resource "kubernetes_secret" "elasticsearch_certificates" {
  metadata {
    name      = "elastic-certificates"
    namespace = kubernetes_namespace.elk.id
  }

  data = {
    "tls.crt" = module.elastic_tls.cert_pem
    "tls.key" = module.elastic_tls.private_key_pem
    "tls.p8"  = module.elastic_tls.p8
  }
}

resource "kubernetes_secret" "elasticsearch_s3_user_creds" {
  metadata {
    name      = "elasticsearch-s3-user-creds"
    namespace = kubernetes_namespace.elk.id
  }

  data = {
    "aws_s3_user_access_key" = module.aws_iam_elastic_stack.access_key_id
    "aws_s3_user_secret_key" = module.aws_iam_elastic_stack.access_secret_key
  }
}

resource "random_string" "elasticsearch_password" {
  length  = 32
  special = false
  upper   = true
}

module "aws_iam_elastic_stack" {
  source = "../modules/aws-iam-user-with-policy"

  name = "${local.name}-elk"
  policy = jsonencode({
    "Version" : "2012-10-17",
    "Statement" : [
      {
        "Effect" : "Allow",
        "Action" : [
          "s3:ListBucket",
          "s3:GetBucketLocation",
          "s3:ListBucketMultipartUploads",
          "s3:ListBucketVersions"
        ],
        "Resource" : [
          "arn:aws:s3:::${local.elastic_stack_bucket_name}"
        ]
      },
      {
        "Effect" : "Allow",
        "Action" : [
          "s3:GetObject",
          "s3:PutObject",
          "s3:DeleteObject",
          "s3:AbortMultipartUpload",
          "s3:ListMultipartUploadParts"
        ],
        "Resource" : [
          "arn:aws:s3:::${local.elastic_stack_bucket_name}/*"
        ]
      }
    ]
  })
}
