class User
  # PERMISSONS_FILE_PATH 环境变量保存用户权限配置文件路径
  # 用户认证交给 nginx 代理处理，loghouse 通过简单的配置进行权限管理
  PERMISSONS_FILE_PATH = ENV.fetch('PERMISSONS_FILE_PATH') { 'config/permissions.yml' }
  class PermissionsNotFound < StandardError; end

  class << self
    def current
      @current
    end

    def current=(user)
      @current = user.is_a?(self) ? user : new(user)
    end
  end

  attr_accessor :name, :permissions
  def initialize(name)
    @name        = name
    @permissions = YAML.load_file(PERMISSONS_FILE_PATH)[name]

    raise PermissionsNotFound, "No user permissions configured for user '#{self}'" if permissions.blank?
  end

  def allowed_to?(namespace)
    permissions.any? do |p|
      Regexp.new(p).match?(namespace)
    end
  end

  def available_namespaces
    Kubernetes.namespaces.select { |ns| allowed_to?(ns) }
  end

  def to_s
    name
  end
end
