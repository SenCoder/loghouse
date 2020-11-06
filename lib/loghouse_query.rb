require 'loghouse_query/parsers'
require 'loghouse_query/storable'
require 'loghouse_query/pagination'
require 'loghouse_query/clickhouse'
require 'loghouse_query/permissions'
require 'loghouse_query/csv'
require 'log_entry'
require 'log'

# lib\loghouse_query 的所有源文件为此类服务
# LoghouseQuery 通过 include 些模块，继承了其中的方法
class LoghouseQuery
  include Parsers
  include Storable
  include Pagination  # E:\Developer\loghouse\lib\loghouse_query\pagination.rb
  include Clickhouse  # E:\Developer\loghouse\lib\loghouse_query\clickhouse.rb
  include Permissions
  include CSV

  # 类的内部定义常量
  # 在类的外部访问常量，使用 classname::constant
  TIME_PARAMS_DEFAULTS = {
    format:  'seek_to',
    seek_to: 'now',
    from:    'now-15m',
    to:      'now'
  }.freeze

  # attr_accessor 属性通过实例直接访问可读也可写
  # attr_writer 属性过实例直接访问只能写不能读
  # attr_reader 属性过实例直接访问只能读不能写
  attr_accessor :attributes, :time_params, :persisted

  def initialize(attrs = {})
    attrs.symbolize_keys!
    @attributes = self.class.columns.dup
    @attributes.each do |k, v|
      @attributes[k] = attrs[k] if attrs[k].present?
    end
    @attributes[:id] ||= SecureRandom.uuid
    time_params({})
  end

  def time_params(params=nil)
    return @time_params if params.nil?

    @time_params = TIME_PARAMS_DEFAULTS.dup
    params.each do |k, v|
      @time_params[k] = params[k] if params[k].present?
    end

    case @time_params[:format]
    when 'seek_to'
      @time_params.slice!(:format, :seek_to)
    when params
      @time_params.slice!(:format, :from, :to)
    end
    self
  end

  def id
    attributes[:id]
  end

  def namespaces
    Array.wrap(attributes[:namespaces])
  end

  def order_by
    [attributes[:order_by], "#{LogsTables::TIMESTAMP_ATTRIBUTE} DESC", "#{LogsTables::NSEC_ATTRIBUTE} DESC"].compact.join(', ')
  end

  def validate_query!
    parsed_query # sort of validation: will fail if format is not correct
  end

  def validate_time_params!
    if time_params[:format] == 'range'
      parsed_time_from # sort of validation: will fail if format is not correct
      parsed_time_to # sort of validation: will fail if format is not correct
    else
      parsed_seek_to # sort of validation: will fail if format is not correct
    end
  end

  def validate!(options = {})
    super

    validate_query! unless options[:query] == false
    validate_time_params! unless options[:time_params] == false
  end
end

require 'log_entry'
