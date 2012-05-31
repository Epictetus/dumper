module Dumper
  module Database
    class MongoDB < Base
      DUMP_TOOL = 'mongodump'

      def command
        "#{@stack.configs[:mongodb][:dump_tool]} #{connection_options} #{additional_options} | gzip"
      end

      def connection_options
        [ :database, :host, :port, :username, :password ].map do |option|
          next if @stack.configs[:mongodb][option].blank?
          "--#{option}='#{@stack.configs[:mongodb][option]}'".gsub('--database', '--db')
        end.compact.join(' ')
      end

      def additional_options
        # '--oplog --out -'
        '--out -'
      end

      def config_for(rails_env=nil)
        return unless mongo = find_instance_in_object_space(Mongo::DB)

        {
          :host => mongo.connection.host,
          :port => mongo.connection.port,
          :database => mongo.name,
          :dump_tool => dump_tool_path
        }.tap do |h|
          if auth = mongo.connection.auths.first
            h.update(:username => auth['username'], :password => auth['password'])
          end
        end
      end
    end
  end
end
