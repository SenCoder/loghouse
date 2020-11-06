class LoghouseQuery
  module Clickhouse
    class Query
      attr_reader :query
      def initialize(query, operator = nil)
        @query    = query
        @operator = operator
      end

      def subquery
        # subquery 为空直接返回
        return if query[:subquery].blank?
        # 创建 subquery
        @subquery ||= self.class.new(query[:subquery][:query], query[:subquery][:q_op])
      end

      def operator
        @operator.to_s.upcase
      end

      def to_s
        # Query 类构建构建 Expression 类
        result = "(#{Expression.new(query[:expression]).to_s})"

        result = [result, "#{subquery.operator}\n", subquery.to_s].join(' ') if subquery
        result
      end
    end
  end
end
