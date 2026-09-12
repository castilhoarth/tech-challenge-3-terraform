/*
resource "kubernetes_manifest" "toggle_prod_application" {
  manifest = {
    apiVersion = "argoproj.io/v1alpha1"
    kind       = "Application"

    metadata = {
      name      = "toggle-prod"
      namespace = "argocd"
    }

    spec = {
      project = "default"

      source = {
        repoURL        = "https://github.com/gerusalobo/toggle-master-devops.git"
        targetRevision = "main"
        path           = "k8s/apps/toggle-prod"

        directory = {
          recurse = true
        }
      }

      destination = {
        server    = "https://kubernetes.default.svc"
        namespace = "toggle-prod"
      }

      syncPolicy = {
        automated = {
          prune    = true
          selfHeal = true
        }

        syncOptions = [
          "CreateNamespace=false"
        ]
      }
    }
  }

  depends_on = [
    module.helm
  ]
}
*/

resource "terraform_data" "toggle_prod_application" {

  depends_on = [
    module.helm
  ]

  provisioner "local-exec" {
    command = <<-EOT
      aws eks update-kubeconfig \
        --region ${var.aws_region} \
        --name ${var.cluster_name}

      kubectl apply -f - <<'YAML'
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: toggle-prod
  namespace: argocd
spec:
  project: default
  source:
    repoURL: https://github.com/gerusalobo/toggle-master-devops.git
    targetRevision: main
    path: k8s/apps/toggle-prod
    directory:
      recurse: true
  destination:
    server: https://kubernetes.default.svc
    namespace: toggle-prod
  syncPolicy:
    automated:
      prune: true
      selfHeal: true
    syncOptions:
      - CreateNamespace=false
YAML
    EOT
  }
}