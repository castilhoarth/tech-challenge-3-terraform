resource "terraform_data" "toggle_prod_application" {

  input = {
    aws_region   = var.aws_region
    cluster_name = var.cluster_name
  }

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
  finalizers:
    - resources-finalizer.argocd.argoproj.io
spec:
  project: default
  source:
    repoURL: https://github.com/castilhoarth/tech-challenge-3-k8s.git
    targetRevision: main
    path: k8s/
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

  provisioner "local-exec" {
    when = destroy

    command = <<-EOT
      aws eks update-kubeconfig \
        --region ${self.input.aws_region} \
        --name ${self.input.cluster_name}

      kubectl delete application toggle-prod \
        -n argocd \
        --ignore-not-found=true \
        --wait=true
    EOT
  }
}