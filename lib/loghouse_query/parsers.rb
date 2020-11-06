require 'loghouse_query_p'
require 'loghouse_query_time_p'

class LoghouseQuery
  class BadFormat < StandardError; end
  class BadTimeFormat < StandardError; end

  module Parsers
    extend ActiveSupport::Concern

    module ClassMethods
      def parser
        # 类变量是在类的所有实例中共享的变量，必须在类定义中被初始化
        # @@ 类变量赋值
        @@parser ||= LoghouseQueryP.new
      end

      def time_parser
        @@time_parser ||= LoghouseQueryTimeP.new
      end
    end

    def parser
      ## 推测是调用类方法
      self.class.parser
    end

    def time_parser
      ## 推测是调用类方法
      self.class.time_parser
    end

    def parsed_time_from
      # @ 实例变量赋值
      # 如果 @parsed_time_from 不为空，直接返回 result 里面的内容；
      # 否则，返回 ||= 的执行结果
      #
      # 调用 lib/loghouse_query_time_p.rb:16
      @parsed_time_from ||= time_parser.parse_time(time_params[:from]) if time_params[:from].present?
    end

    def parsed_time_to
      # 如果 @parsed_time_to 不为空，直接返回 result 里面的内容；
      # 否则，返回 ||= 的执行结果
      #
      # 调用 lib/loghouse_query_time_p.rb:16
      @parsed_time_to ||= time_parser.parse_time(time_params[:to]) if time_params[:to].present?
    end

    def parsed_seek_to
      @parsed_seek_to ||= begin
        return if time_params[:seek_to].blank?

        time = Chronic.parse(time_params[:seek_to])

        raise BadTimeFormat.new("Unable to parse seek_to '#{time_params[:seek_to]}'") if time.nil?
        time
      end
    end

    def parsed_query
      return if attributes[:query].blank?
      ## 推测是调用类方法
      @parsed_query ||= begin
        parser.parse attributes[:query]
      rescue Parslet::ParseFailed => e
        raise BadFormat.new("#{attributes[:query]}: #{e}")
      end
    end

    # 这个方法目前未使用
    def parse!
      parsed_query
      parsed_time_to
      parsed_time_from
    end
  end
end
