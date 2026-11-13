output "node_ports" {
  description = "NodePorts das ferramentas (acesse por http://<IP do nó kind>:<porta>)"
  value = {
    front        = 30082
    grafana      = 30300
    prometheus   = 30090
    alertmanager = 30903
  }
}
