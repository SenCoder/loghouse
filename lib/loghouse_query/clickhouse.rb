require 'loghouse_query/clickhouse/query'
require 'loghouse_query/clickhouse/expression'

class LoghouseQuery
  # 模块类似与类，但有以下不同
  # * 模块不能实例化，而类可以
  # * 模块没有子类
  # * 类可以通过 include 模块的方式继承模块的方式，为类添加方法
  #
  # include module 会为 class 引入 module 的方法，作为实例方法
  # extend  module 会为 class 引入 module 的方法，作为类方法
  module Clickhouse
    extend ActiveSupport::Concern
    MAX_GREEDY_SEARCH_PERIODS = 2

    # 不带参数的方法
    # Ruby 中的每个方法默认都会返回一个值。这个返回的值是最后一个语句的值。
    def result
      # 如果 result 不为空，直接返回 result 里面的内容；
      # 否则，返回 begin ... end 的执行结果
      @result ||= begin
        if parsed_time_to.present?
          result_older(parsed_time_to, limit, parsed_time_from)
        elsif parsed_time_from.present? && parsed_time_to.blank?
          result_newer(parsed_time_from, limit)
        elsif parsed_seek_to.present?
          result_from_seek_to
        # else WTF
        end
      end
    end

    # 构建原生查询 SQL
    def to_clickhouse(table, from, to, lim = nil)
      params = {
        select: '*',
        from: table,
        order: order_by,
        limit: lim
      }
      # 添加过滤条件
      if (where = to_clickhouse_where(from, to))
        params[:where] = where
      end

      ::Clickhouse.connection.to_select_query(params)
    end

    protected

    def result_older(start_time, lim, stop_at = nil)
      result = []
      time = start_time
      stop_at ||= start_time - LogsTables::RETENTION_PERIOD.hours * MAX_GREEDY_SEARCH_PERIODS

      while lim.positive? && (time >= stop_at)
        table = LogsTables::TABLE_NAME

        sql = to_clickhouse(table, nil, start_time, lim)

        res = LogEntry.from_result_set ::Clickhouse.connection.query(sql)

        result += res
        lim -= res.count
        # 时间节点向前移动一小时
        time = LogsTables.prev_time_partition(time)
      end
      result
    end

    def result_newer(start_time, lim, stop_at = nil)
      result = []
      time = start_time
      # stop_at = start_time + 2h
      stop_at ||= start_time + LogsTables::RETENTION_PERIOD.hours * MAX_GREEDY_SEARCH_PERIODS
      # 若 stop_at 超过了当前时间，重置为当前时间
      stop_at = Time.zone.now if stop_at > Time.zone.now

      while lim.positive? && (time <= stop_at)
        table = LogsTables::TABLE_NAME

        sql = to_clickhouse(table, start_time, nil, lim)

        res = LogEntry.from_result_set ::Clickhouse.connection.query(sql)

        result += res.reverse
        lim -= res.count
        # 修改 time 的值， start_time 会改变吗？
        # 时间节点向后移动一小时
        time = LogsTables.next_time_partition(time)
      end
      result.reverse
    end

    def result_from_seek_to
      lim = limit || Pagination::DEFAULT_PER_PAGE

      # 查询 parsed_seek_to 之前的数据
      # search before part
      before = result_older(parsed_seek_to, lim)

      # 查询 parsed_seek_to 之后的数据
      # search after part
      after = result_newer(parsed_seek_to, lim, Time.zone.now)

      # res 由前面两端数据各区一半拼接而成
      # todo: 这里查询返回的数据只用到了一半，考虑是否有优化空间
      res = after.last([before.count, lim / 2].min)
      res += before.first(lim - res.count)
      res
    end

    # 转换时间条件为查询语句
    def time_comparation(time, comparation)
      if time.nsec.zero?
        "#{LogsTables::TIMESTAMP_ATTRIBUTE} #{comparation}= #{to_clickhouse_time(time)}"
      else
        '(' + [
          [
            [LogsTables::TIMESTAMP_ATTRIBUTE, to_clickhouse_time(time)].join(' = '),
            [LogsTables::NSEC_ATTRIBUTE, time.nsec].join(" #{comparation} ")
          ].join(' AND '),
          [LogsTables::TIMESTAMP_ATTRIBUTE, to_clickhouse_time(time)].join(" #{comparation} "),
        ].join(') OR (') + ')'
      end
    end

    def to_clickhouse_time(time)
      "toDateTime('#{time.utc.strftime('%Y-%m-%d %H:%M:%S')}')"
    end

    def to_clickhouse_namespaces
      return if namespaces.blank?

      namespaces.map { |ns| "namespace = '#{ns}'" }.join(' OR ')
    end

    def partitions_list(from, to)
      if from.nil?
        from = to
      end

      if to.nil?
        to = from
      end

      dates = [from]
      while dates.last < (to - 1.day)
        dates << (dates.last + 1.day)
      end
      return "date in ('#{(dates.map { |element| element.utc.strftime('%Y-%m-%d') }).join("' , '")}')"
    end

    def to_clickhouse_where(from = nil, to = nil)
      where_parts = []
      where_parts << Query.new(parsed_query[:query]).to_s if parsed_query

      where_parts << partitions_list(from,to) if from or to

      where_parts << time_comparation(from, '>') if from
      where_parts << time_comparation(to, '<') if to

      where_parts << to_clickhouse_namespaces
      where_parts.compact!

      # 若 where_parts 为空直接返回
      return if where_parts.blank?

      "(#{where_parts.join(') AND (')})"
    end
  end
end
