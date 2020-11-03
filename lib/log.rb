module Log
  module_function
  # 封装日志打印函数
  def log(msg, indent = 3)
    puts "- #{Time.now} #{'-' * indent}> #{msg}"
  end
end