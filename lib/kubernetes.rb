module Kubernetes
  module_function
  # k8s 客户端，负责获取 k8s namespace list 便于查询
  def client
    @client ||= begin
      auth_options = {
          bearer_token_file: '/var/run/secrets/kubernetes.io/serviceaccount/token'
      }

      ssl_options = {
          ca_file: '/var/run/secrets/kubernetes.io/serviceaccount/ca.crt',
          verify_ssl: OpenSSL::SSL::VERIFY_PEER
      }

      Kubeclient::Client.new(
          "https://#{ENV['KUBERNETES_SERVICE_HOST']}:#{ENV['KUBERNETES_SERVICE_PORT']}/api/", 'v1', auth_options: auth_options,
          ssl_options: ssl_options
      )
    end
  end

# 设置为 development 环境可以获得如下 namespace 模拟数据，便于调试
  def namespaces
    if Loghouse::Application.development?
      %w[production staging review-123]
    else
      client.get_namespaces.map { |ns| ns.metadata.name }
    end
  end
end
