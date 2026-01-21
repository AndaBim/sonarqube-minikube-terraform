resource "kubernetes_namespace" "sonarqube" {
  metadata {
    name = "sonarqube"
  }
}

resource "helm_release" "postgresql" {
  name      = "postgresql"
  namespace = kubernetes_namespace.sonarqube.metadata[0].name

  chart = "${path.module}/../helm/postgresql"

  timeout = 300
  wait    = true

  values = [
    file("${path.module}/../helm/postgresql/values.yaml")
  ]

  depends_on = [
    kubernetes_namespace.sonarqube
  ]
}


resource "helm_release" "sonarqube" {
  name      = "sonarqube"
  namespace = kubernetes_namespace.sonarqube.metadata[0].name

  repository = "https://SonarSource.github.io/helm-chart-sonarqube"
  chart      = "sonarqube"
  version    = "10.5.0"

  timeout = 1800
  wait    = true

  values = [
    file("${path.module}/values/sonarqube.yaml")
  ]

  depends_on = [
    kubernetes_namespace.sonarqube
  ]
}
