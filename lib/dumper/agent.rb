require 'timeout'
require 'net/http'

module Dumper
  class Agent
    include Dumper::Utility::LoggingMethods

    API_VERSION = 1

    attr_reader :stack

    class << self
      def start(options = {})
        new(options).start
      end

      def start_if(options = {})
        start(options) if yield
      end
    end

    def initialize(options = {})
      log '**** Dumper requires :app_key! ****' if options[:app_key].blank?

      @stack = Dumper::Stack.new
      @api_base = options[:api_base] || 'http://dumper.io'
      @app_key = options[:app_key]
      @app_env = @stack.rails_env
      @app_name = ObjectSpace.each_object(Rails::Application).first.class.name.split("::").first
    end

    def start
      return unless @app_key and @stack.supported?
      log "stack: dispatcher = #{@stack.dispatcher}, framework = #{@stack.framework}, rackup = #{@stack.rackup}"

      @loop_thread = Thread.new { start_loop }
      @loop_thread[:name] = 'Loop Thread'
    end

    def start_loop
      sleep 3
      json = send_request(api: 'agent/register', json: MultiJson.encode(register_hash))
      @token = json[:token] if json && json[:token]
      sleep 3
      loop do
        json = send_request(api: 'agent/poll', params: { token: @token })
        if json
          # Promoted or demoted?
          if json[:token]
            @token = json[:token] # promote
          else
            @token = nil # demote
          end

          if json[:job]
            if pid = fork
              # Parent
              srand # Ruby 1.8.7 needs reseeding - http://bugs.ruby-lang.org/issues/4338
              Process.detach(pid)
            else
              # Child
              Dumper::Job.new(self, json[:job]).run_and_exit
            end
          end
        end
        sleep @token ? 60.seconds : 1.hour
      end
    end

    def register_hash
      {
        # :pid => Process.pid,
        # :host => Socket.gethostname,
        :agent_version => Dumper::VERSION,
        :app_name => @app_name,
        :stack => @stack.to_hash,
      }
    end

    def send_request(options)
      uri = URI.parse("#{@api_base}/api/#{options[:api]}")
      http = Net::HTTP.new(uri.host, uri.port)
      if uri.is_a? URI::HTTPS
        http.use_ssl = true
        http.verify_mode = OpenSSL::SSL::VERIFY_NONE
      end
      request = Net::HTTP::Post.new(uri.request_uri)
      request['x-app-key'] = @app_key
      request['x-app-env'] = @app_env
      request['x-api-version'] = API_VERSION.to_s
      request['user-agent'] = "Dumper-RailsAgent/#{Dumper::VERSION} (ruby #{::RUBY_VERSION} #{::RUBY_PLATFORM} / rails #{Rails::VERSION::STRING})"
      if options[:params]
        request.set_form_data(options[:params])
      else
        # Without empty string, WEBrick would complain WEBrick::HTTPStatus::LengthRequired for empty POSTs
        request.body = options[:json] || ''
        request['Content-Type'] = 'application/octet-stream'
      end

      response = http.request(request)
      if response.code == '200'
        log response.body, :debug
      else
        log '******** ERROR!! ********', :error
      end
      MultiJson.decode(response.body).with_indifferent_access
    rescue
      log_last_error
      {} # return empty hash
    end
  end
end
