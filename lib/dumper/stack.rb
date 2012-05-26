module Dumper
  class Stack
    attr_accessor :rails_env, :dispatcher, :framework, :rackup, :activerecord_config

    def initialize
      # Rackup?
      @rackup = find_instance_in_object_space(Rack::Server)

      # Rails?
      if defined?(::Rails)
        @framework = :rails
        @rails_env = Rails.env.to_s
        @rails_version = Rails::VERSION::STRING
        @is_supported_rails_version = (::Rails::VERSION::MAJOR >= 3)
        @activerecord_config = ActiveRecord::Base.configurations[@rails_env]
      else
        @framework = :ruby
      end

      # Which dispatcher?
      [ :unicorn, :passenger, :thin, :mongrel, :webrick ].find do |name|
        @dispatcher = send("#{name}?") ? name : nil
      end
    end

    def to_hash
      {
        framework: @framework,
        rails_env: @rails_env,
        rails_version: @rails_version,
        dispatcher: @dispatcher,
        activerecord_config: @activerecord_config.reject{|k,v| k == 'password' },
      }
    end

    # Compatibility
    def supported?
      @is_supported_rails_version && @dispatcher && %w(mysql mysql2).include?(@activerecord_config['adapter'])
    end

    # Dispatcher
    def unicorn?
      defined?(::Unicorn::HttpServer) && find_instance_in_object_space(::Unicorn::HttpServer)
    end

    def passenger?
      defined?(::Passenger::AbstractServer) || defined?(::IN_PHUSION_PASSENGER)
    end

    def thin?
      # defined?(::Thin::Server) && find_instance_in_object_space(Thin::Server)
      @rackup and @rackup.server.to_s.demodulize == 'Thin'
    end

    def mongrel?
      # defined?(::Mongrel::HttpServer)
      @rackup and @rackup.server.to_s.demodulize == 'Mongrel'
    end

    def webrick?
      # defined?(::WEBrick::VERSION)
      @rackup and @rackup.server.to_s.demodulize == 'WEBrick'
    end

    def find_instance_in_object_space(klass)
      ObjectSpace.each_object(klass).first
    end
  end
end
