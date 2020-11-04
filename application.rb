require_relative 'config/boot'

module Loghouse
  TIME_ZONE = ENV.fetch('TIME_ZONE') { 'Europe/Moscow' }

  class UnauthenticatedError < StandardError; end
  # 服务接口定义
  # rubocop:disable Metrics/ClassLength
  class Application < Sinatra::Base
    configure do
      use Rack::MethodOverride
      register Sinatra::RespondWith

      enable :logging
    end

    before do
      Time.zone          = TIME_ZONE
      Chronic.time_class = Time.zone
      User.current       = self.class.development? ? 'admin' : user_from_header
      @tab_queries       = LoghouseQuery.all.first(10)

      if request.path_info.match(/.csv$/)
        request.accept.unshift('text/csv')
        request.path_info = request.path_info.gsub(/.csv$/,'')
      end
    end

    # 对路由 / 的 get 请求被重定向到 /query
    get '/' do
      redirect '/query'
    end

    # 查询日志主页面
    get '/query', provides: [:html, :csv] do
      @query =  if params[:query_id]
                  @tab = params[:query_id]
                  LoghouseQuery.find!(params[:query_id])
                else
                  query_from_params
                end

      begin
        @query.validate!(name: false)
      rescue LoghouseQuery::BadFormat => e
        @error = "Bad query format: #{e}"
      rescue LoghouseQuery::BadTimeFormat => e
        @error = "Bad time format: #{e}"
      end

      respond_to do |f|
        f.html do
          @query.paginate(newer_than: params[:newer_than], older_than: params[:older_than], per_page: params[:per_page])

          if request.xhr?
            erb :_result, layout: false
          else
            erb :index
          end
        end

        f.csv { @query.csv_result(params[:shown_keys]) }
      end
    end

    # 查询模板管理
    # Queries management
    before '/queries*' do
      @tab = :queries
    end

    get '/queries' do
      @queries = LoghouseQuery.all

      erb :'queries/index'
    end

    # 获取查询添加页面
    get '/queries/new' do
      @query = query_from_params
      erb :'queries/new'
    end

    # post 提交添加的新查询
    post '/queries' do
      @query = query_from_params

      begin
        @query.save!

        return redirect '/queries'
      rescue LoghouseQuery::BadFormat => e
        @error = "Bad query format: #{e}"
      rescue LoghouseQuery::BadTimeFormat => e
        @error = "Bad time format: #{e}"
      rescue LoghouseQuery::Storable::NotValid => e
        @error = "Validation failed: #{e}"
      end

      erb :'queries/new'
    end

    # 获取更新查询页面
    get '/queries/:query_id/edit' do
      @query = LoghouseQuery.find!(params[:query_id])

      erb :'queries/edit'
    end

    # 拖动改变查询模板的顺序，该接口出现 500 错误
    put '/queries/update_order' do
      new_order = JSON.parse(params[:new_order])
      LoghouseQuery.update_order!(new_order)

      content_type :json
      { status: :ok }.to_json
    end

    # 提交查询修改请求，运行的 demo 该接口似乎是 post 实现而非 put
    put '/queries/:query_id' do
      @query = LoghouseQuery.find!(params[:query_id])
      begin
        @query.update!(query_from_params.attributes)

        return redirect '/queries'
      rescue LoghouseQuery::BadFormat => e
        @error = "Bad query format: #{e}"
      rescue LoghouseQuery::BadTimeFormat => e
        @error = "Bad time format: #{e}"
      rescue LoghouseQuery::Storable::NotValid => e
        @error = "Validation failed: #{e}"
      end

      erb :'queries/edit'
    end

    # 删除单条查询模板
    delete '/queries/:query_id' do
      query = LoghouseQuery.find!(params[:query_id])
      query.destroy!

      ''
    end

    # 批量删除查询模板
    delete '/queries' do
      LoghouseQuery.create_table!(true)

      ''
    end

    error UnauthenticatedError do |e|
      @status = 401
      @message = "Not Authenticated"

      render_error
    end

    error User::PermissionsNotFound do |e|
      @status = 403
      @message = e.message

      render_error
    end

    error do |e|
      @status = 500
      @message = 'Internal Server Error'

      render_error
    end

    helpers do
      def h(text)
        Rack::Utils.escape_html(text)
      end

      def follow?
        params[:follow] == 'on'
      end

      def version
        @version ||= ENV.fetch('GIT_REV') { `git rev-parse HEAD` }.to_s[0..7]
      end
    end

    private

    def query_from_params
      LoghouseQuery.new(name: params[:name], query: params[:query].to_s.strip, namespaces: params[:namespaces])
                   .time_params(format: params[:time_format], from: params[:time_from], to: params[:time_to],
                                seek_to: params[:seek_to])

    end

    def user_from_header
      auth_header = env['HTTP_AUTHORIZATION']

      raise UnauthenticatedError if auth_header.blank?

      Base64.decode64(auth_header.gsub(/Basic /, '')).split(':').first
    end

    def render_error
      status @status
      erb :error, layout: false
    end
  end
end
